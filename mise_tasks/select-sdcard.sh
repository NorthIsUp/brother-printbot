#!/usr/bin/env zsh
#MISE description="Select SD card for burning"
#MISE raw=true

set -e

# Logging functions
log-info() { print -P "%F{green}[select-sdcard] $1%f" >&2 }
log-exit() { print -P "%F{red}[select-sdcard] $1%f" >&2; exit 1 }

local sd_cards=()
for disk in $(diskutil list | grep "physical" | awk '{print $1}'); do
    log-info "🔄 checking disk: $disk..."
    info=$(diskutil info $disk)
    if echo "$info" | grep -iq "Device Identifier:.*disk0"; then
        continue
    elif echo "$info" | grep -iqE "Protocol:.*(Secure Digital|USB)"; then
        sd_cards+=($disk)
        log-info "✅ found SD Card: $disk"
        diskutil info $disk | grep -E "Device Node:|Device / Media Name:|Protocol:|Disk Size:" | while read -r line; do
            log-info "  $line"
        done
    fi
done

case $#sd_cards in
    0)  log-exit "❌ No SD card detected." ;;
    1)  log-info "✅ using ${sd_cards[1]}"; sd_card="${sd_cards[1]}" ;;
    *)  log-exit "⚠️  More than one Storage Device detected: $sd_cards" ;;
esac

log-info "✅ SD card found: $sd_card"
print $sd_card
