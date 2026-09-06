#!/usr/bin/env bash
set -euo pipefail

if [[ "$#" -gt 0 ]]; then
  exec "$@"
fi

# /etc/cups is the natural mount point for persistence, but mounting a volume
# over it hides the cupsd.conf the package shipped and CUPS refuses to start.
# Seed from the build-time copy whenever the directory is empty (first boot on a
# fresh volume), and never otherwise — printers.conf is the user's state.
if [[ -d /usr/share/cups-defaults ]] && [[ -z "$(ls -A /etc/cups 2>/dev/null)" ]]; then
  echo "entrypoint: /etc/cups empty — seeding from image defaults"
  cp -a /usr/share/cups-defaults/. /etc/cups/
fi

# CUPS 2.4 answers 400 Bad Request to any Host header that is not ServerName or
# a ServerAlias — so reaching the web UI through a reverse proxy fails on the
# hostname alone, whatever the ACLs say. Applied on every boot rather than in the
# Dockerfile because the seed above only runs on an empty volume: a deployment
# that already has state would otherwise never pick this up.
if [[ -n "${CUPS_SERVER_ALIAS:-}" ]] && ! grep -qxF "ServerAlias ${CUPS_SERVER_ALIAS}" /etc/cups/cupsd.conf; then
  echo "entrypoint: adding ServerAlias ${CUPS_SERVER_ALIAS}"
  printf '\nServerAlias %s\n' "${CUPS_SERVER_ALIAS}" >> /etc/cups/cupsd.conf
fi

# Drop CUPS's default `_cups` DNS-SD subtype, keeping `_print,_universal`. macOS reads
# `_cups` as "shared CUPS queue": the Add Printer dialog lists it as Bonjour
# Shared and assigns Apple's Generic PostScript PPD, which gates duplex behind an
# APOptionalDuplexer installable option that no server-side setting can reach.
# Without the subtype the queue reads as a plain IPP printer and macOS generates
# a driverless PPD from the attributes we already advertise — verified against
# this queue with `lpadmin -m everywhere`, which yields a real *OpenUI *Duplex
# block plus cupsPrintQuality Draft/Normal/High.
#
# Same reason as ServerAlias above, and it is why the Dockerfile could not do it:
# /etc/cups is a mounted volume, the seed only runs when that volume is empty, so
# an existing deployment never picks up a build-time edit to cupsd.conf. That is
# exactly how the first attempt at this shipped an image whose setting was inert.
CUPS_SUBTYPES='BrowseDNSSDSubTypes _print,_universal'
if ! grep -qxF "$CUPS_SUBTYPES" /etc/cups/cupsd.conf; then
  echo "entrypoint: setting ${CUPS_SUBTYPES} (drops _cups so macOS uses driverless)"
  sed -i '/^BrowseDNSSDSubTypes /d; /^DNSSDSubTypes /d' /etc/cups/cupsd.conf
  printf '\n%s\n' "$CUPS_SUBTYPES" >> /etc/cups/cupsd.conf
fi

# Refuse to start on a config cupsd will not parse. An unknown directive is only
# a warning to cupsd — it starts anyway and silently ignores the line — so a
# typo'd directive looks exactly like a working one from the outside. This shipped
# twice: `DNSSDSubTypes` (no such directive in CUPS 2.4; the real name carries the
# Browse prefix) reached production as a no-op both times, and nothing surfaced it
# until someone ran `cupsd -t` by hand.
if ! cupsd -t 2>&1 | tee /tmp/cupsd-t.log | grep -qi 'is OK'; then
  echo "entrypoint: FATAL cupsd rejected the config:" >&2
  cat /tmp/cupsd-t.log >&2
  exit 1
fi
if grep -qi 'unknown directive' /tmp/cupsd-t.log; then
  echo "entrypoint: FATAL cupsd.conf has an unknown directive — refusing to start:" >&2
  grep -i 'unknown directive' /tmp/cupsd-t.log >&2
  exit 1
fi

# CUPS admin needs a real Unix user in SystemGroup (lpadmin) — the package
# creates none, so without this every /admin request 401s no matter the
# password. Credentials come from env so a deployment can inject its own.
CUPSADMIN="${CUPSADMIN:-cupsadmin}"
CUPSPASSWORD="${CUPSPASSWORD:-cupsadmin}"
if ! id "$CUPSADMIN" >/dev/null 2>&1; then
  useradd -r -M -s /usr/sbin/nologin -G lpadmin "$CUPSADMIN"
fi
echo "${CUPSADMIN}:${CUPSPASSWORD}" | chpasswd
if [[ "$CUPSPASSWORD" == "cupsadmin" ]]; then
  echo "entrypoint: WARNING using the default admin password — set CUPSPASSWORD" >&2
fi

# Avahi is what turns a shared CUPS queue into an AirPrint service; CUPS does the
# DNS-SD advertising itself but needs a running daemon to register with, and
# avahi-daemon needs a system bus. Neither is PID 1, so failures here must be
# loud rather than silently leaving a non-discoverable printer.
if [[ -z "${SKIP_AVAHI:-}" ]]; then
  mkdir -p /run/dbus
  rm -f /run/dbus/pid
  dbus-daemon --system --fork
  avahi-daemon --daemonize --no-drop-root
  echo "entrypoint: avahi-daemon started (AirPrint advertisement enabled)"
fi

exec /usr/sbin/cupsd -f
