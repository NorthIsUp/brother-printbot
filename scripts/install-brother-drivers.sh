#!/usr/bin/env bash
set -euo pipefail

MODEL="${1:-HL-4570CDW}"
BROTHER_IN_ARMS_REF="${BROTHER_IN_ARMS_REF:-master}"
REPO_DIR="${REPO_DIR:-/opt/brother-in-arms}"
PRINTER_NAME="${PRINTER_NAME:-BrotherHL4570CDW}"
PRINTER_URI="${PRINTER_URI:-}"
PPD_PATH="${PPD_PATH:-}"

arch="$(dpkg --print-architecture)"
extra_packages=()
if [[ "$arch" == "arm64" ]]; then
  dpkg --add-architecture armhf
  extra_packages+=(libc6:armhf libstdc++6:armhf)
fi

if [[ -f /etc/os-release ]]; then
  . /etc/os-release
  if [[ "${ID:-}" == "raspbian" || "${ID_LIKE:-}" == *"raspbian"* ]]; then
    extra_packages+=(avahi-daemon avahi-utils usbutils)
  fi
fi

apt-get update
apt-get install -y --no-install-recommends \
  ca-certificates \
  curl \
  dpkg-dev \
  build-essential \
  gcc \
  git \
  ghostscript \
  make \
  psutils \
  cups \
  cups-bsd \
  cups-client \
  sudo \
  xz-utils \
  zsh \
  "${extra_packages[@]}"

mkdir -p /var/spool/lpd

if [[ -d "$REPO_DIR/.git" ]]; then
  git -C "$REPO_DIR" fetch --prune
  git -C "$REPO_DIR" checkout "$BROTHER_IN_ARMS_REF"
  git -C "$REPO_DIR" pull --ff-only
else
  git clone https://github.com/alexivkin/brother-in-arms.git "$REPO_DIR"
  git -C "$REPO_DIR" checkout "$BROTHER_IN_ARMS_REF"
fi

sed -i 's/sudo systemctl restart cups/sudo systemctl restart cups || true/' "$REPO_DIR/oh_brother.zsh"

zsh "$REPO_DIR/oh_brother.zsh" "$MODEL"

if [[ -z "${SKIP_CUPS_START:-}" ]]; then
  if command -v systemctl >/dev/null 2>&1; then
    systemctl enable --now cups || systemctl restart cups || true
  elif command -v cupsd >/dev/null 2>&1; then
    if ! lpstat -r 2>/dev/null | grep -q "scheduler is running"; then
      cupsd || true
    fi
  fi
fi

wait_for_cups() {
  local attempts=30
  while (( attempts > 0 )); do
    if lpstat -r 2>/dev/null | grep -q "scheduler is running"; then
      return 0
    fi
    sleep 1
    attempts=$(( attempts - 1 ))
  done

  echo "CUPS did not become ready in time." >&2
  return 1
}

wait_for_cups || true

if lpinfo -m 2>/dev/null | grep -qi "HL-4570"; then
  echo "HL-4570 driver appears in CUPS models."
else
  echo "HL-4570 driver not found in CUPS models." >&2
fi

if [[ -f /var/log/cups/error_log ]]; then
  echo "Recent CUPS errors (if any):"
  grep -Ei "hl-4570|brother|ppd|filter|error|unable" /var/log/cups/error_log | tail -n 200 || true
elif command -v journalctl >/dev/null 2>&1; then
  echo "Recent CUPS journal (filtered):"
  journalctl -u cups --no-pager | grep -Ei "hl-4570|brother|ppd|filter|error|unable" | tail -n 200 || true
fi

if [[ -n "$PRINTER_URI" ]]; then
  if [[ -z "$PPD_PATH" ]]; then
    PPD_PATH="$(lpinfo -m | awk '/HL-4570/ {print $1; exit}')"
  fi

  if [[ -n "$PPD_PATH" ]]; then
    lpadmin -p "$PRINTER_NAME" -E -v "$PRINTER_URI" -m "$PPD_PATH"
    if [[ -f /usr/share/cups/data/testprint ]]; then
      lp -d "$PRINTER_NAME" /usr/share/cups/data/testprint || true
    else
      echo "Test page not found at '/usr/share/cups/data/testprint'." >&2
    fi
  else
    echo "PPD not found; set 'PPD_PATH' and re-run." >&2
  fi
fi
