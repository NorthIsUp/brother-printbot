FROM debian:trixie-slim

ENV DEBIAN_FRONTEND=noninteractive
ENV SKIP_CUPS_START=1

COPY docker/entrypoint.sh /usr/local/bin/entrypoint.sh
COPY scripts/install-brother-drivers.sh /usr/local/sbin/install-brother-drivers

RUN chmod 755 /usr/local/bin/entrypoint.sh /usr/local/sbin/install-brother-drivers \
  && /usr/local/sbin/install-brother-drivers "HL-4570CDW"

# AirPrint = a shared CUPS queue advertised over DNS-SD. CUPS does the
# advertising itself but only when an Avahi daemon is present to register with,
# and avahi needs a system bus. cups-filters supplies the raster path Apple
# clients require; without it the queue advertises with no URF key and iOS
# ignores it — which is exactly why the HL-4570CDW is invisible unbridged.
RUN apt-get update \
  && apt-get install -y --no-install-recommends \
       avahi-daemon \
       avahi-utils \
       dbus \
       cups-filters \
  && rm -rf /var/lib/apt/lists/*

# Listen beyond loopback and share queues by default: in Kubernetes the web UI is
# reached from another pod, and an unshared queue is never advertised at all.
# Done with sed, not cupsctl — cupsctl talks to a running cupsd, which there is
# not at build time. `Allow all` goes on every Location, including /admin:
# without it CUPS returns a flat 403 rather than prompting, so the queue cannot
# be added through the web UI from another pod. Admin still requires Basic auth
# as a member of SystemGroup, and the only exposure is the tailnet + home LAN.
# Encryption Required is dropped for the same reason: the tailscale ingress
# terminates TLS and proxies plain HTTP, so CUPS insisting on its own TLS just
# returns 426 Upgrade Required and the admin UI is unreachable.
RUN sed -i \
      -e 's/^Listen localhost:631/Listen 0.0.0.0:631/' \
      -e 's/^Browsing Off/Browsing On/' \
      /etc/cups/cupsd.conf \
  && printf '\nDefaultShared Yes\n' >> /etc/cups/cupsd.conf \
  && sed -i 's|^  Order allow,deny$|  Order allow,deny\n  Allow all|' /etc/cups/cupsd.conf \
  && sed -i '/^  Encryption Required$/d' /etc/cups/cupsd.conf \
  && printf '\nDefaultEncryption Never\n' >> /etc/cups/cupsd.conf

# Kept so the entrypoint can repopulate /etc/cups when a volume is mounted over
# it. Without this, persisting printers.conf costs you cupsd.conf.
RUN cp -a /etc/cups /usr/share/cups-defaults

EXPOSE 631/tcp 5353/udp

ENTRYPOINT ["/usr/local/bin/entrypoint.sh"]
CMD []
