#!/usr/bin/env bash
# Write a ready-to-run Anyka AK3918 hack SD card from the backup taken 2026-08-05,
# with this project's fixes baked in.
#
#   sudo tools/write-sd-card.sh /dev/sdX [--ssid NAME] [--time-source IP] [--stock]
#
# The card is the camera's brain: /Factory/config.sh is what the stock firmware
# executes at boot (the SD exploit), and /mnt/anyka_hack/ holds every binary the
# hack starts. No card, no RTSP, no PTZ, no telnet.
#
# Refuses to touch anything that isn't a removable device, and asks before
# erasing. See docs/sd-card.md for what ends up on the card and why.
set -euo pipefail

# $HOME is /root under sudo, so resolve the invoking user's home instead.
INVOKER_HOME="$HOME"
if [ -n "${SUDO_USER:-}" ]; then
  INVOKER_HOME="$(getent passwd "$SUDO_USER" | cut -d: -f6)"
fi
BACKUP="${BACKUP:-$INVOKER_HOME/Backups/anyka-yicam-sd-2026-08-05}"
LABEL="YICAM"
VOLID="8D1BDED7"

# Repo root, so we can overlay files that live here rather than in the backup.
REPO="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
OVERLAY="$REPO/tools/card-overlay"
CTL_SRC="$REPO/reference/sd-card-original/web_interface/ctl"

# The IR-cut fix. Two builds of the vendor kernel disagree about the sysfs node
# name, so the card carries BOTH binaries and the launcher picks one per boot.
# See tools/card-overlay/.../run_libre_anyka_app.sh for the full reasoning.
LAA_STOCK_MD5="3458b8598ca9525a0d5e693ff5fd5d5c"   # writes gpio-ircut_a (2022 build)
LAA_PATCH_MD5="351d54e853ee6774e50e9704986bd6b6"   # writes ircut_a      (2023 build)
LAA_PATCH_SRC="$REPO/reference/patches/libre_anyka_app.node-ircut_a"

# ---------------------------------------------------------------------------
# DO NOT ADD A libplat_drv.so PATCH HERE. It has been tried; it is a regression.
#
# That library (ptz/lib/libplat_drv.so, md5 f5769ff013d7a3094e73ee76e312cad0)
# contains gpio-ircut_a, gpio-ircut_b and ir-led, none of which exist as nodes
# on the 2023 build. It reads as an obvious unfinished job, exactly like the
# libre_anyka_app patch below. It is not.
#
# Patching those strings on the live camera on 2026-08-06 STOPPED the IR-cut
# solenoid from clicking. JP had been driving it from Home Assistant for weeks.
# Rolling the library back restored it. Manual IR-cut control (set_ir_cut, which
# is what HA uses) does not go through sysfs at all, so "fixing" the sysfs paths
# only introduces a second writer that fights the one that works.
#
# The general rule, which is the thing worth keeping: a string that looks broken
# may be a dead path whose failure is LOAD-BEARING. Establish that a path is
# actually executed before correcting it. See docs/ptz.md.
# ---------------------------------------------------------------------------

# The pre-auth root RCE fix for cgi-bin/header. UNLIKE the binary patch this is
# NOT kernel-build-specific, so it applies unconditionally with no detection.
# Verified by demonstrating the hole and then its absence on the live camera -
# NOT by a harness, because an earlier version passed one while still permitting
# PATH/IFS/LD_PRELOAD hijacking. Never swap this file without re-running the
# live exploit test; the md5 below is what was actually verified.
HEADER_FIX_SRC="$REPO/reference/patches/cgi-bin-header.hardened"
HEADER_FIX_MD5="934ce4814d4fc90edec82275769986c5"
HEADER_STOCK_MD5="997a3c6e65e66d29a47a7c59c8964685"

# Fixes applied to gergesettings.txt on the card. POSIX TZ counts hours WEST of
# Greenwich, so the shipped GMT-08:00 actually means UTC+8 - 15 hours out.
FIX_TIME_ZONE="PST8PDT,M3.2.0,M11.1.0"
FIX_PTZ_INIT="1"

die() { printf 'error: %s\n' "$*" >&2; exit 1; }
warn() { printf 'WARNING: %s\n' "$*" >&2; }

DEV="${1:-}"; shift || true
SSID=""
TIME_SOURCE=""
STOCK=0
while [ $# -gt 0 ]; do
  case "$1" in
    --ssid)        SSID="${2:-}"; shift 2 ;;
    --time-source) TIME_SOURCE="${2:-}"; shift 2 ;;
    --stock)       STOCK=1; shift ;;
    *) die "unknown option: $1" ;;
  esac
done

[ -n "$DEV" ] || die "usage: $0 /dev/sdX [--ssid NAME] [--time-source IP] [--stock]"
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
if [ "$STOCK" -eq 1 ]; then
  echo "Mode   : --stock (backup contents only, NO project fixes)"
else
  echo "Mode   : fixes applied (timezone, ptz_init_on_boot, ctl, RCE fix, IR-cut selection)"
fi
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
CONFIG_SH="$MNT/Factory/config.sh"
APPDIR="$MNT/anyka_hack/libre_anyka_app"
NOTES=()

if [ -n "$SSID" ]; then
  echo "==> setting wifi_ssid=$SSID"
  sed -i "s|^wifi_ssid=.*|wifi_ssid=$SSID|" "$SETTINGS"
  NOTES+=("wifi_password is UNCHANGED - edit $SETTINGS on the card if this SSID uses a different key.")
fi

if [ -n "$TIME_SOURCE" ]; then
  echo "==> setting time_source=$TIME_SOURCE"
  sed -i "s|^time_source=.*|time_source=$TIME_SOURCE|" "$SETTINGS"
fi

if [ "$STOCK" -eq 0 ]; then

  # --- 1. timezone. The backup ships GMT-08:00, which POSIX reads as UTC+8.
  echo "==> fixing time_zone -> $FIX_TIME_ZONE"
  sed -i "s|^time_zone=.*|time_zone=$FIX_TIME_ZONE|" "$SETTINGS"

  # --- 2. home the PTZ axes on boot (the daemon needs init_ptz, never init)
  echo "==> setting ptz_init_on_boot=$FIX_PTZ_INIT"
  sed -i "s|^ptz_init_on_boot=.*|ptz_init_on_boot=$FIX_PTZ_INIT|" "$SETTINGS"

  # --- 3. our fast control endpoint (not upstream's)
  if [ -f "$CTL_SRC" ]; then
    echo "==> installing /cgi-bin/ctl"
    install -m 755 "$CTL_SRC" "$MNT/anyka_hack/web_interface/www/cgi-bin/ctl"
  else
    warn "ctl not found at $CTL_SRC - skipping"
    NOTES+=("cgi-bin/ctl was NOT installed (source missing).")
  fi

  # --- 3b. hardened cgi-bin/header (pre-auth root RCE fix)
  HDR_DST="$MNT/anyka_hack/web_interface/www/cgi-bin/header"
  if [ ! -f "$HEADER_FIX_SRC" ]; then
    NOTES+=("cgi-bin/header is UNPATCHED - the pre-auth root RCE on port 80 is LIVE on this card.")
    NOTES+=("  -> the camera VLAN's isolation is the only thing mitigating it. See docs/web-ui.md.")
  else
    hgot="$(md5sum "$HEADER_FIX_SRC" | cut -d' ' -f1)"
    if [ "$hgot" != "$HEADER_FIX_MD5" ]; then
      warn "hardened header md5 is $hgot, expected $HEADER_FIX_MD5 - NOT installing it"
      NOTES+=("cgi-bin/header REJECTED on md5 mismatch - the pre-auth root RCE is LIVE on this card.")
    else
      # sanity-check what we are replacing, so a changed backup is noticed
      if [ -f "$HDR_DST" ]; then
        sgot="$(md5sum "$HDR_DST" | cut -d' ' -f1)"
        [ "$sgot" = "$HEADER_STOCK_MD5" ] || \
          warn "backup's cgi-bin/header is $sgot, not the expected stock $HEADER_STOCK_MD5 - replacing anyway"
      fi
      echo "==> installing hardened cgi-bin/header (pre-auth RCE fix)"
      install -m 755 "$HEADER_FIX_SRC" "$HDR_DST"
    fi
  fi

  # --- 4. somewhere for ctl's play/sounds commands to look
  echo "==> creating /sounds (16 kHz mono mp3, pre-attenuated)"
  mkdir -p "$MNT/sounds"

  # --- 5. fix upstream's missing bracket, which stops the sensor symlink from
  #        ever being recreated if flash is reset:  if [ ! -e "$FILE"; then
  if grep -q 'if \[ ! -e "\$FILE"; then' "$CONFIG_SH" 2>/dev/null; then
    echo "==> fixing the missing ']' in Factory/config.sh"
    sed -i 's|if \[ ! -e "\$FILE"; then|if [ ! -e "$FILE" ]; then|' "$CONFIG_SH"
  fi

  # --- 6. IR-cut: ship both binaries, let the launcher pick per boot
  STOCK_BIN="$APPDIR/libre_anyka_app"
  if [ ! -f "$STOCK_BIN" ]; then
    warn "libre_anyka_app not found in the backup - skipping the IR-cut fix"
    NOTES+=("IR-cut day/night fix NOT applied (binary missing from backup).")
  else
    got="$(md5sum "$STOCK_BIN" | cut -d' ' -f1)"
    if [ "$got" != "$LAA_STOCK_MD5" ]; then
      warn "libre_anyka_app md5 is $got, expected $LAA_STOCK_MD5"
      warn "the backup has changed - NOT applying the IR-cut fix"
      NOTES+=("IR-cut day/night fix NOT applied (unexpected binary in backup).")
    else
      echo "==> installing IR-cut node detection"
      mv "$STOCK_BIN" "$APPDIR/libre_anyka_app.node-gpio-ircut_a"

      if [ -f "$LAA_PATCH_SRC" ]; then
        pgot="$(md5sum "$LAA_PATCH_SRC" | cut -d' ' -f1)"
        if [ "$pgot" = "$LAA_PATCH_MD5" ]; then
          install -m 755 "$LAA_PATCH_SRC" "$APPDIR/libre_anyka_app.node-ircut_a"
          echo "    both builds installed - launcher will detect per boot"
        else
          warn "patched binary md5 is $pgot, expected $LAA_PATCH_MD5 - NOT installing it"
          NOTES+=("Patched IR-cut binary REJECTED on md5 mismatch; card falls back to stock.")
        fi
      else
        NOTES+=("No patched IR-cut binary at $LAA_PATCH_SRC.")
        NOTES+=("  -> automatic day/night IR-cut switching will NOT work on a 2023-build camera.")
        NOTES+=("  -> the card is still correct on a 2022-build camera. Nothing is broken.")
      fi

      # our launcher does the detection; keep upstream's for reference
      if [ -f "$OVERLAY/anyka_hack/libre_anyka_app/run_libre_anyka_app.sh" ]; then
        mv "$APPDIR/run_libre_anyka_app.sh" "$APPDIR/run_libre_anyka_app.sh.upstream" 2>/dev/null || true
        install -m 755 "$OVERLAY/anyka_hack/libre_anyka_app/run_libre_anyka_app.sh" \
                       "$APPDIR/run_libre_anyka_app.sh"
      else
        die "overlay launcher missing at $OVERLAY - refusing to leave the card with a renamed binary and no launcher"
      fi
    fi
  fi
fi

echo
echo "==> settings on this card:"
grep -E '^(wifi_ssid|sensor_kern_module|time_source|time_zone|ptz_init_on_boot|run_)' "$SETTINGS" \
  | sed 's/^/    /'
echo "    (wifi_password is set but not shown)"

# The backup's time_source points at a router that may no longer exist.
BAKED_TS="$(sed -n 's/^time_source=//p' "$SETTINGS")"
if [ -z "$TIME_SOURCE" ]; then
  NOTES+=("time_source is $BAKED_TS, inherited from the backup. If that is not this")
  NOTES+=("  camera's gateway, NTP will silently never sync. Use --time-source.")
fi

sync
echo
echo "Done. Card is ready for an AK3918 camera."

if [ "${#NOTES[@]}" -gt 0 ]; then
  echo
  echo "Notes:"
  for n in "${NOTES[@]}"; do echo "  * $n"; done
fi

echo
echo "Reminders:"
echo "  * THE CARD WINS. gergehack.sh diffs this card's gergesettings.txt and"
echo "    gergehack.sh against the camera's flash copies on EVERY boot; if they"
echo "    differ it copies card -> flash and REBOOTS. So editing only"
echo "    /etc/jffs2/gergesettings.txt over telnet silently reverts next boot."
echo "    Change settings on the card, or edit both copies together."
echo "  * This card works in ANY of these cameras. The IR-cut binary is chosen"
echo "    at every boot from which /sys/user-gpio node exists, so swapping the"
echo "    card between units is safe and self-correcting."
echo "  * The card sets the root password from Factory/config.sh on every boot."
echo "  * sensor_kern_module points at the GC1084 module ON THIS CARD. If the new"
echo "    camera has a different image sensor, video will not come up until that"
echo "    line and isp_gc1084.conf are swapped for the right sensor."
echo "  * Each camera needs its own card - the card is not shareable between units."
