#!/usr/bin/env zsh
#MISE description="Build the HL-4570CDW driver test image"
set -euo pipefail

docker build -t printbot-brother-test -f docker/Dockerfile .
