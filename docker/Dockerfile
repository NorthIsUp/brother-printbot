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

# macOS imposes "Pages per Sheet" itself and still sends number-up, so pdftopdf
# imposed a second time and 4-up printed as 16-up. Shim pdftopdf for jobs macOS
# has already laid out; the .convs entry undercuts cups-filters' cost 66 so cupsd
# picks the wrapper. Must come after cups-filters, which provides the real
# pdftopdf the wrapper execs. See docker/filter/pdftopdf-nonup for the full why.
COPY docker/filter/pdftopdf-nonup /usr/lib/cups/filter/pdftopdf-nonup
COPY docker/mime/macos-nonup.convs /usr/share/cups/mime/macos-nonup.convs
RUN chmod 755 /usr/lib/cups/filter/pdftopdf-nonup \
  && chown root:root /usr/lib/cups/filter/pdftopdf-nonup

# DNSSDSubTypes drops CUPS's default `_cups` subtype, keeping only `_print`.
# That subtype is what macOS reads as "this is a shared CUPS queue": the Add
# Printer dialog then lists the queue as "Bonjour Shared" and hands it the
# Generic PostScript driver, whose duplex is gated behind an APOptionalDuplexer
# installable option that nothing here can set. Result: no duplex and one
# quality level, despite the queue advertising Duplex=T and PQ4-5.
#
# Without `_cups` the queue reads as a plain IPP printer and macOS generates a
# driverless PPD from the advertised attributes instead. Verified against this
# queue with `lpadmin -m everywhere`, which yields "BR-Script3 - IPP Everywhere"
# carrying a real *OpenUI *Duplex block and cupsPrintQuality Draft/Normal/High.
#
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
  && printf '\nDefaultEncryption Never\n' >> /etc/cups/cupsd.conf \
  && printf '\nDNSSDSubTypes _print\n' >> /etc/cups/cupsd.conf

# Brother's GPL BR-Script3 PPD, rebranded 4070 -> 4570 (see the header in the
# file). This is the queue's PPD, NOT Brother's hl4570cdw.ppd.
#
# The printer has a real PostScript 3 interpreter in firmware: its own
# `@PJL INFO CONFIG` reports LANGUAGES = PCL, POSTSCRIPT, PCLXL, XL2HB. So the
# whole vendor driver chain is avoidable - CUPS renders PostScript, pstops hands
# it to the socket backend, and the printer rasterises for itself, in colour,
# with no Brother binary and no x86 emulation anywhere.
#
# Brother's own PPD cannot be used for this: every one of its options has empty
# invocation code ("          ") because the values are meant to be consumed by
# Brother's own chain rather than sent to the printer. Point a queue at it and
# paper size, duplex and colour silently stop working.
#
# Note the blocker is NOT brcupsconfpt1, which install-brother-drivers already
# rebuilds from Brother's GPL source and which runs natively as aarch64 here.
# That binary emits no printer bytes at all — it shells out to brprintconf to
# write a config file. The wall is one layer further down: brprintconf_hl4570cdw
# and brhl4570cdwfilter are i386-only, stripped, and their source is a 404. So
# the native path stays closed on arm64 no matter what happens to the wrapper.
COPY docker/ppd/BR4570_2_GPL.ppd /usr/share/ppd/BR4570_2_GPL.ppd

# Kept so the entrypoint can repopulate /etc/cups when a volume is mounted over
# it. Without this, persisting printers.conf costs you cupsd.conf.
RUN cp -a /etc/cups /usr/share/cups-defaults

EXPOSE 631/tcp 5353/udp

ENTRYPOINT ["/usr/local/bin/entrypoint.sh"]
CMD []
