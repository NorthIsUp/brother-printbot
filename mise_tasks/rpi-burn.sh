#!/usr/bin/env zsh
#MISE description="Flash an image with rpi-imager (set IMAGE_URI, DEST_DEVICE)"
#USAGE flag "--verify"
#USAGE flag "--sha256=<sha256>"
#USAGE flag "--brother-model <model>" default="HL-4570CDW"
#USAGE flag "--ts-auth-key <key>" default="tskey-auth-kWhmmJ1B9D21CNTRL-FixArAZ45nWNTD4ANh9CnWs5F2ZQ5aiK"
#USAGE flag "--ssh-authorized-key <key>" default="ssh-ed25519 AAAAC3NzaC1lZDI1NTE5AAAAIBe8UzvU95pM3C912JI0wl1LgOeoUkheO3fgy7baPSyd"
#USAGE flag "--image-uri <uri>" default="https://downloads.raspberrypi.com/raspios_lite_arm64/images/raspios_lite_arm64-2025-12-04/2025-12-04-raspios-trixie-arm64-lite.img.xz"
#USAGE flag "--dest-device <device>" default="auto"
#USAGE flag "--userdata-path <path>" default="cloud-init/user-data.yaml"
#USAGE flag "--network-config-path <path>" default="cloud-init/network-config.yaml"
#USAGE flag "--rpi-imager-bin <path>" default="/Applications/Raspberry Pi Imager.app/Contents/MacOS/rpi-imager"

set -euo pipefail

[[ ${usage_dest_device-} == "auto" ]] && DEST_DEVICE="$(mise select-sdcard)" || DEST_DEVICE="$usage_dest_device"

if [[ ! -e "$DEST_DEVICE" ]]; then
  echo "SD card not found at $DEST_DEVICE" >&2
  exit 1
fi

args=(--cli)

[[ ${usage_verify-} ]] || args+=(--disable-verify)
[[ ${usage_sha256-} ]] && args+=(--sha256 "$usage_sha256")

tmp_userdata=$(mktemp)
sed \
  -e "s|__TS_AUTHKEY__|${usage_ts_auth_key}|g" \
  -e "s|__BROTHER_MODEL__|${usage_brother_model}|g" \
  -e "s|__SSH_AUTHORIZED_KEY__|${usage_ssh_authorized_key}|g" \
  "$usage_userdata_path" > "$tmp_userdata"

cat "$tmp_userdata"

args+=(--cloudinit-userdata "$tmp_userdata")
if [[ -f "$usage_network_config_path" ]]; then
  args+=(--cloudinit-networkconfig "$usage_network_config_path")
fi

"$usage_rpi_imager_bin" "${args[@]}" "$usage_image_uri" "$DEST_DEVICE"

rm -f "$tmp_userdata"
