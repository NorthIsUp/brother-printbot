#!/usr/bin/env zsh
#MISE description="Verify driver appears and show recent CUPS errors"
#MISE depends=["docker:build"]
set -euo pipefail

docker run --rm printbot-brother-test bash -lc "
  cupsd
  sleep 2
  lpinfo -m | grep -i hl4570 || true
  if [ -f /var/log/cups/error_log ]; then
    grep -Ei 'hl-4570|brother|ppd|filter|error|unable' /var/log/cups/error_log | tail -n 200 || true
  fi
  pkill cupsd || true
"
