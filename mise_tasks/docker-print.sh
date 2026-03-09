#!/usr/bin/env zsh
#MISE description="Add printer and print test page (requires PRINTER_URI)"
#MISE depends=["docker:build"]
set -euo pipefail

docker run --rm -e PRINTER_URI -e PRINTER_NAME -e PPD_PATH --privileged printbot-brother-test bash -lc '
  cupsd
  sleep 2
  if [ -z "$PRINTER_URI" ]; then
    echo "PRINTER_URI is required" >&2
    exit 1
  fi
  if [ -z "$PPD_PATH" ]; then
    PPD_PATH="$(lpinfo -m | grep -i HL-4570 | head -n 1 | cut -d " " -f1)"
  fi
  if [ -z "$PPD_PATH" ]; then
    echo "PPD_PATH not found" >&2
    exit 1
  fi
  PRINTER_NAME="${PRINTER_NAME:-BrotherHL4570CDW}"
  lpadmin -p "$PRINTER_NAME" -E -v "$PRINTER_URI" -m "$PPD_PATH"
  lpstat -p -d
  lp -d "$PRINTER_NAME" /usr/share/cups/data/testprint
  lpstat -W all
  pkill cupsd || true
'
