FROM debian:trixie-slim

ENV DEBIAN_FRONTEND=noninteractive
ENV SKIP_CUPS_START=1

COPY docker/entrypoint.sh /usr/local/bin/entrypoint.sh
COPY scripts/install-brother-drivers.sh /usr/local/sbin/install-brother-drivers

RUN chmod 755 /usr/local/bin/entrypoint.sh /usr/local/sbin/install-brother-drivers \
  && /usr/local/sbin/install-brother-drivers "HL-4570CDW"

ENTRYPOINT ["/usr/local/bin/entrypoint.sh"]
CMD ["bash", "-lc", "lpinfo -m | grep -i hl4570 || true; /usr/sbin/cupsd -f"]
