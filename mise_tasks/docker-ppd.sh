#!/usr/bin/env zsh
#MISE description="List available HL-4570CDW PPDs in the container"
#MISE depends=["docker:build"]
set -euo pipefail

docker run --rm printbot-brother-test lpinfo -m | grep -i hl4570 || true
