#!/usr/bin/env zsh
#MISE description="Run CUPS in the container (http://localhost:631)"
set -euo pipefail

docker run --rm -it -p 631:631 --privileged printbot-brother-test
