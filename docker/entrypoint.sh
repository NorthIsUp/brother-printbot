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
