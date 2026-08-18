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

# Some Brother binaries are x86 with no ARM build and no source; see
# brother_arm_fixup below. They get emulated.
if [[ "$arch" != "i386" && "$arch" != "amd64" ]]; then
  dpkg --add-architecture i386
  extra_packages+=(qemu-user-static libc6:i386)
fi

# filter<model> shells out to both. Without `file` it cannot detect the input
# type and falls through to its a2ps branch; without a2ps that branch emits
# nothing — a blank page from a completely healthy-looking queue.
extra_packages+=(file a2ps)

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

# ---------------------------------------------------------------------------
# Make Brother's x86 binaries usable on ARM.
#
# oh_brother.zsh targets the HL2270DW shape: drop in Brother's own armv7l
# rawtobr3, recompile brcupsconfig from source, done. Two of those assumptions
# do not hold for every model, and both fail silently.
#
#   1. It copies armv7l/rawtobr3 into the model's lpd/ directory. The
#      HL-4570CDW lpr package contains no rawtobr3, and grep over the unpacked
#      package finds no reference to one. The copy is inert, so the only genuine
#      ARM substitution does nothing for this model.
#
#   2. It installs the compiled binary as `brcupsconfig4`, but Brother's own
#      cupswrapper for this model calls `brcupsconfpt1`. Same source, different
#      name — so a perfectly good native binary lands beside the i386 one it was
#      supposed to replace. Derive the name from Brother's script instead.
#
# What remains is genuinely sourceless: brhl4570cdwfilter (2.2 MB raster
# converter; hl4570cdwlpr-src is a 404) and brprintconf_<model>. No ARM build of
# either exists — Brother's generic ARM package ships only rawtobr3 and
# brprintconflsr3, and its PPD is *ColorDevice: False, so it is not a colour
# substitute. Emulation is what is left, and it is method 1 in the
# brother-in-arms README.
# ---------------------------------------------------------------------------

elf_machine() { # -> e_machine, non-zero exit when not an ELF
  [[ "$(head -c4 "$1" | od -An -tx1 | tr -d ' \n')" == "7f454c46" ]] || return 1
  od -An -tu1 -j18 -N1 "$1" | tr -d ' '
}

host_elf_machine() {
  case "$(uname -m)" in
    x86_64) echo 62 ;;
    i?86) echo 3 ;;
    aarch64 | arm64) echo 183 ;;
    armv7l | armhf) echo 40 ;;
    *) echo "" ;;
  esac
}

build_native_cupsconfig() {
  local model_dir="$1" src wrapper name out
  src="$(find "$REPO_DIR" "$(dirname "$REPO_DIR")" -type f -name brcupsconfig.c 2>/dev/null | head -n1)"
  [[ -n "$src" ]] || { echo "  no brcupsconfig.c found; skipping native build."; return 1; }

  wrapper="$(find "$model_dir/cupswrapper" -maxdepth 1 -type f -name 'cupswrapper*' 2>/dev/null | head -n1)"
  name="$(grep -ohE 'brcupsconf[a-z0-9]+' "$wrapper" 2>/dev/null | sort -u | head -n1)"
  [[ -n "$name" ]] || name=brcupsconfig4

  out="$model_dir/cupswrapper/$name"
  if gcc -pipe -O2 -w "$src" -o "$out.native" 2>/dev/null; then
    mv -f "$out.native" "$out"
    chmod 755 "$out"
    echo "  compiled brcupsconfig.c -> $name ($(uname -m) native)"
    return 0
  fi
  rm -f "$out.native"
  echo "  WARNING: brcupsconfig.c failed to compile." >&2
  return 1
}

shim_foreign_binaries() {
  local host mach real shimmed=0 f
  host="$(host_elf_machine)"
  [[ -n "$host" ]] || return 0
  [[ "$host" == 3 || "$host" == 62 ]] && return 0

  while IFS= read -r f; do
    [[ -f "$f" ]] || continue
    mach="$(elf_machine "$f")" || continue
    [[ "$mach" == "$host" ]] && continue
    [[ "$mach" == 40 && "$host" == 183 ]] && continue # armhf runs on arm64
    if [[ "$mach" != 3 ]]; then
      echo "  WARNING: $f is ELF machine $mach, unhandled on $(uname -m)." >&2
      continue
    fi
    if ! command -v qemu-i386-static >/dev/null 2>&1; then
      echo "  ERROR: $f is i386 but qemu-i386-static is missing." >&2
      return 1
    fi
    real="${f}.i386"
    [[ -f "$real" ]] || mv "$f" "$real"
    cat >"$f" <<SHIM
#!/bin/sh
# Brother ships this only as a 32-bit x86 binary, with no source and no ARM
# build. Emulate it so the vendor colour path works on ARM.
exec qemu-i386-static "\$(dirname "\$0")/$(basename "$real")" "\$@"
SHIM
    chmod 755 "$f"
    echo "  shimmed i386 -> qemu: $f"
    shimmed=$((shimmed + 1))
  done < <(find /usr/local/Brother /opt/brother /usr/bin -maxdepth 6 -type f 2>/dev/null)

  echo "  $shimmed binaries now run under qemu-i386-static."
  return 0
}

brother_arm_fixup() {
  local model_dir
  model_dir="$(find /usr/local/Brother/Printer -maxdepth 1 -mindepth 1 -type d 2>/dev/null | head -n1)"
  [[ -n "$model_dir" ]] || { echo "  no Brother model dir; skipping." >&2; return 0; }
  build_native_cupsconfig "$model_dir" || true # prefer native where source exists
  shim_foreign_binaries                        # emulate whatever is left
}

echo "Adapting Brother binaries for $(uname -m):"
brother_arm_fixup || echo "WARNING: ARM fixup incomplete; expect blank pages." >&2

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
