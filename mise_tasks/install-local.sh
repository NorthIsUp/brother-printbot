#!/usr/bin/env zsh
#MISE description="Run driver install script on this machine"
set -euo pipefail

sudo scripts/install-brother-drivers.sh "HL-4570CDW"
