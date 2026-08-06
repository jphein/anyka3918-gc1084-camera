#!/usr/bin/env bash
# Write a ready-to-run Anyka AK3918 hack SD card from the backup taken 2026-08-05.
#
#   sudo tools/write-sd-card.sh /dev/sdX [--ssid NAME]
#
# The card is the camera's brain: /Factory/config.sh is what the stock firmware
# executes at boot (the SD exploit), and /mnt/anyka_hack/ holds every binary the
# hack starts. No card, no RTSP, no PTZ, no telnet.
#
# Refuses to touch anything that isn't a removable device, and asks before
# erasing. See reference/sd-card-original/README.md for what's on the card.
set -euo pipefail

# $HOME is /root under sudo, so resolve the invoking user's home instead.
INVOKER_HOME="$HOME"
if [ -n "${SUDO_USER:-}" ]; then
  INVOKER_HOME="$(getent passwd "$SUDO_USER" | cut -d: -f6)"
fi
BACKUP="${BACKUP:-$INVOKER_HOME/Backups/anyka-yicam-sd-2026-08-05}"
LABEL="YICAM"
VOLID="8D1BDED7"

die() { printf 'error: %s\n' "$*" >&2; exit 1; }

DEV="${1:-}"; shift || true
SSID=""
while [ $# -gt 0 ]; do
  case "$1" in
    --ssid)     SSID="${2:-}"; shift 2 ;;
    *) die "unknown option: $1" ;;
  esac
done

[ -n "$DEV" ] || die "usage: $0 /dev/sdX [--ssid NAME]"
[ -b "$DEV" ] || die "$DEV is not a block device"
[ -d "$BACKUP" ] || die "backup not found at $BACKUP"
[ "$(id -u)" -eq 0 ] || die "must run as root (writing a raw device)"

# --- safety: removable, not mounted as anything important, not the system disk
BASE="$(basename "$DEV")"
[ -e "/sys/block/$BASE/removable" ] || die "$DEV has no removable flag - is it a whole disk?"
[ "$(cat "/sys/block/$BASE/removable")" = "1" ] || die "$DEV is NOT removable. Refusing."
ROOTSRC="$(findmnt -no SOURCE / || true)"
case "$ROOTSRC" in *"$BASE"*) die "$DEV appears to host /. Refusing." ;; esac

SIZE_H="$(lsblk -dno SIZE "$DEV" | tr -d ' ')"
MODEL="$(lsblk -dno MODEL "$DEV" | sed 's/ *$//')"
echo "Target : $DEV  ($SIZE_H, ${MODEL:-unknown})"
echo "Source : $BACKUP"
lsblk -o NAME,SIZE,FSTYPE,LABEL,MOUNTPOINT "$DEV"
echo
read -r -p "This ERASES $DEV. Type ERASE to continue: " confirm
[ "$confirm" = "ERASE" ] || die "aborted"

echo "==> unmounting any existing partitions"
for p in $(lsblk -lno NAME "$DEV" | tail -n +2); do umount "/dev/$p" 2>/dev/null || true; done

echo "==> writing partition table + FAT32 boot sector (first 4MB, byte-exact)"
dd if="$BACKUP/header-first-4MB.img" of="$DEV" bs=1M count=4 conv=fsync status=none
partprobe "$DEV"; sleep 2

PART="${DEV}1"; [ -b "$PART" ] || PART="${DEV}p1"
[ -b "$PART" ] || die "no partition 1 appeared on $DEV"

# The header only carries FAT structures sized for the ORIGINAL 7.4GB card, so
# always rebuild the filesystem to match whatever card is actually in hand.
echo "==> formatting $PART as FAT32 (label $LABEL, volume id $VOLID)"
mkfs.vfat -F 32 -n "$LABEL" -i "$VOLID" "$PART" >/dev/null

MNT="$(mktemp -d)"
trap 'umount "$MNT" 2>/dev/null || true; rmdir "$MNT" 2>/dev/null || true' EXIT
mount "$PART" "$MNT"

echo "==> extracting camera payload"
tar -xzf "$BACKUP/yicam-files.tar.gz" -C "$MNT"

SETTINGS="$MNT/anyka_hack/gergesettings.txt"
if [ -n "$SSID" ]; then
  echo "==> setting wifi_ssid=$SSID"
  sed -i "s|^wifi_ssid=.*|wifi_ssid=$SSID|" "$SETTINGS"
  echo "    NOTE: wifi_password is unchanged - edit $SETTINGS if this SSID uses a different key."
fi

echo
echo "==> WiFi/sensor settings on this card:"
grep -E '^(wifi_ssid|sensor_kern_module|time_source|ptz_init_on_boot|run_)' "$SETTINGS" \
  | sed 's/^/    /'
echo "    (wifi_password is set but not shown)"

sync
echo
echo "Done. Card is ready for an AK3918 camera."
echo
echo "Reminders:"
echo "  * THE CARD WINS. gergehack.sh diffs this card's gergesettings.txt and"
echo "    gergehack.sh against the camera's flash copies on EVERY boot; if they"
echo "    differ it copies card -> flash and REBOOTS. So editing only"
echo "    /etc/jffs2/gergesettings.txt over telnet silently reverts next boot."
echo "    Change settings on the card, or edit both copies together."
echo "  * The card sets the root password from Factory/config.sh on every boot."
echo "  * sensor_kern_module points at the GC1084 module ON THIS CARD. If the new"
echo "    camera has a different image sensor, video will not come up until that"
echo "    line and isp_gc1084.conf are swapped for the right sensor."
echo "  * Each camera needs its own card - the card is not shareable between units."
