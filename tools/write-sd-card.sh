#!/usr/bin/env bash
# Write a ready-to-run Anyka AK3918 hack SD card from the backup taken 2026-08-05,
# with this project's fixes baked in.
#
#   sudo tools/write-sd-card.sh /dev/sdX (--ssid NAME | --keep-ssid)
#                                        [--time-source IP]
#                                        [--unit-name "Front Door"] [--stock]
#                                        [--force-wipe]
#
# The SSID decision is REQUIRED - see the block below. This header showed it as
# optional for a while, contradicting the tool's own usage string two hundred
# lines down; a comment that disagrees with the code it heads is worse than no
# comment, because it is read first and trusted.
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
CTL_SRC="$REPO/reference/sd-card-original/web_interface/ctl"
IDENTITY_SRC="$REPO/tools/identity"

# Where the project lives, for build.json's commit_url. Public repo, no secrets.
REPO_URL="https://github.com/jphein/anyka3918-gc1084-camera"

# NO BINARY IR-CUT PATCH IS SHIPPED. This is deliberate and hard-won.
#
# Two were tried on the live camera on 2026-08-06. Both are now reverted there,
# and neither belongs on a card:
#
#   libre_anyka_app  (gpio-ircut_a -> ircut_a)
#       CONFIRMED INERT by disassembly. It fixes the WRITE end of a two-ended
#       chain while the SENSE end stays broken in a file nobody patched: the
#       day/night thread photosensitive_switch_th_ex calls
#       ak_drv_ir_get_input_level(), which resolves into a DIFFERENT
#       libplat_drv.so build (385740be...) whose init fails the same way, so it
#       returns -1 and the thread bails before reaching any write. Shipping it
#       buys nothing and costs the whole per-boot node-name detection scheme.
#
#   ptz/lib/libplat_drv.so  (gpio-ircut_a/b -> ircut_a/b, ir-led -> IR_LED)
#       A REGRESSION, with an exact mechanism. ak_drv_ir_init stats BOTH names:
#       both fail -> driver disabled; exactly one -> 1-line mode (write and
#       hold, correct here); both -> 2-line mode, which pulses
#       a=v; b=!v; sleep 10ms; a=0; b=0 for a LATCHING solenoid. This board's
#       filter is hold-to-engage on ircut_a alone with 4-8 s travel, so every
#       command ended with the pin released and the filter parked OUT (magenta).
#       Renaming gpio-ircut_b ALONE caused it. Renaming only ircut_a would have
#       landed in 1-line mode and been harmless - THE MORE THOROUGH FIX WAS THE
#       HARMFUL ONE.
#
# Automatic day/night is NOT FIXABLE on this board at any level: the sense input
# is gpio-rf_feed, which does not exist here, and the fallback /sys/kernel/ain/ain0
# is measured pinned at a constant 2999. Do not spend a day on it.
#
# The patched binary is kept at reference/patches/ for documentation only.
# See docs/ptz.md and reference/patches/README.md.
LAA_STOCK_MD5="3458b8598ca9525a0d5e693ff5fd5d5c"   # stock, and what we ship

# Speaker volume. ak_adec_demo hardcodes the DAC volume to 6 - the MAXIMUM of a
# 0-6 range - with no CLI flag and no getenv. Upstream saw a volume that would
# not change, concluded "volume control fails when running", and told everyone to
# pre-attenuate the mp3. The control never failed; it was never exposed. And the
# workaround cannot work: the file is UPSTREAM of the ASLC compressor, which
# normalises it straight back up (10.3 dB measured into the camera, inaudible out).
#
# One byte fixes it. The `mov r1,#N` immediate at file offset 9356 (0xa48c-0x8000)
# feeds ak_ao_set_dac_volume, and because that value reaches the DAC by ioctl it
# sits DOWNSTREAM of ASLC and cannot be normalised away. ASLC is left ENABLED -
# it was never the problem, and with it on, quiet clips stay audible.
ADEC_STOCK_MD5="21a59c852dfb7af2fbaebd0994e24570"   # stock == the level-6 variant
ADEC_VOL_OFFSET=9356                                # 0xa48c - 0x8000
ADEC_DEFAULT_LEVEL=4                                # JP: "let's try in the middle for now"

# THE RULE BOTH OF THOSE TEACH, and the reason it is repeated in a shell script
# rather than left in the docs: a string that looks broken may be a DEAD PATH
# WHOSE FAILURE IS LOAD-BEARING. Every one of these binaries contains sysfs paths
# that plainly do not exist on this kernel. They read as a backlog of one-line
# fixes. Repairing one of them tipped a driver out of "disabled" and into a mode
# built for hardware this board does not have.
#
# Before repairing a wrong-looking path, establish (a) that it is actually
# executed and (b) WHAT CURRENTLY DEPENDS ON IT FAILING.
#
# The only patch on this card is the security fix below. It earns its place by
# closing a live remote root hole, and it is kernel-agnostic.

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
KEEP_SSID=0
TIME_SOURCE=""
UNIT_NAME=""
STOCK=0
FORCE_WIPE=0
# The SSH public key(s) allowed to log in. A path, NOT a key: a public key is an
# identifier (it carries user@host), this repo is public and deliberately
# scrubbed, and tools/hosts.local already set the precedent for "real values
# live in a gitignored local file". Default is that file; --authorized-keys
# overrides for a camera that should accept a different key.
AUTHORIZED_KEYS="$REPO/tools/authorized_keys.local"
NO_SSH=0
# Declared HERE, before any guard that appends to it. See the note where it used
# to live, next to APPDIR.
NOTES=()
while [ $# -gt 0 ]; do
  case "$1" in
    --ssid)        SSID="${2:-}"; shift 2 ;;
    --keep-ssid)   KEEP_SSID=1; shift ;;
    --time-source) TIME_SOURCE="${2:-}"; shift 2 ;;
    --unit-name)   UNIT_NAME="${2:-}"; shift 2 ;;
    --stock)       STOCK=1; shift ;;
    --force-wipe)  FORCE_WIPE=1; shift ;;
    --authorized-keys) AUTHORIZED_KEYS="${2:-}"; shift 2 ;;
    --no-ssh)      NO_SSH=1; shift ;;
    *) die "unknown option: $1" ;;
  esac
done

[ -n "$DEV" ] || die "usage: $0 /dev/sdX (--ssid NAME | --keep-ssid) [--time-source IP]
                        [--unit-name NAME] [--stock] [--force-wipe]
                        [--authorized-keys FILE] [--no-ssh]"

# --unit-name is NOT the counterpart of --ssid, and deliberately so.
#
# --ssid is required because a wrong default strands a camera. A missing name
# strands nothing: an unnamed camera names ITSELF at first boot, from its own
# MAC, with no registry and no configuration. So the override is optional by
# design - it exists for the one camera JP wants to call "Front Door", not as a
# per-unit chore that has to be got right for every card.
#
# It only takes effect on a camera that has NEVER been named. Naming is
# write-once in flash, so passing --unit-name for a camera that already has a
# name does nothing at all. Say so out loud rather than let it look applied.
case "$UNIT_NAME" in
  *'"'*) die "--unit-name must not contain a double quote (it goes into JSON)" ;;
esac

# The SSID decision is REQUIRED, deliberately. Defaulting to the backup's baked-in
# value is how you produce a camera that associates with nothing: no network path,
# no console, and no indication of why. This project already lost a camera for four
# months to exactly that - the SSID it hardcoded was renamed, and a station looking
# for an absent SSID never sends auth frames, so it appears in NO association list
# and NO failed-auth log anywhere. See docs/troubleshooting.md.
#
# --keep-ssid is a one-word affirmation, not an inconvenience: it means "yes, I
# know what SSID is baked in and I want it".
if [ -n "$SSID" ] && [ "$KEEP_SSID" -eq 1 ]; then
  die "--ssid and --keep-ssid are mutually exclusive"
fi
if [ -z "$SSID" ] && [ "$KEEP_SSID" -eq 0 ]; then
  die "refusing to guess the WiFi SSID.
  Pass --ssid NAME to set it, or --keep-ssid to accept the backup's baked-in value.
  A card written for a retired SSID produces a camera with no network path and no
  console - the most expensive failure available on this hardware."
fi
[ -b "$DEV" ] || die "$DEV is not a block device"
[ -d "$BACKUP" ] || die "backup not found at $BACKUP"
[ "$(id -u)" -eq 0 ] || die "must run as root (writing a raw device)"

# --- safety: removable, not mounted as anything important, not the system disk
BASE="$(basename "$DEV")"
[ -e "/sys/block/$BASE/removable" ] || die "$DEV has no removable flag - is it a whole disk?"
[ "$(cat "/sys/block/$BASE/removable")" = "1" ] || die "$DEV is NOT removable. Refusing."
ROOTSRC="$(findmnt -no SOURCE / || true)"
case "$ROOTSRC" in *"$BASE"*) die "$DEV appears to host /. Refusing." ;; esac

# --- build identity, resolved BEFORE the erase so a broken toolchain costs
#     nothing. The card gets a marker saying which commit of this repo produced
#     it; the camera gets its own name at first boot. See docs/identity.md.
#
# safe.directory is needed because this runs as root against a repo owned by the
# invoking user - without it git refuses with "dubious ownership" and every card
# would silently be stamped "dev".
GIT_HASH="$(git -c safe.directory="$REPO" -C "$REPO" rev-parse --short=7 HEAD 2>/dev/null || true)"
GIT_BRANCH="$(git -c safe.directory="$REPO" -C "$REPO" rev-parse --abbrev-ref HEAD 2>/dev/null || true)"
if [ -n "$GIT_HASH" ]; then
  if git -c safe.directory="$REPO" -C "$REPO" diff --quiet HEAD 2>/dev/null; then
    GIT_DIRTY=false
  else
    GIT_DIRTY=true
  fi
else
  # realm-sigil's own convention for "provenance unknown".
  GIT_HASH="dev"; GIT_BRANCH="unknown"; GIT_DIRTY=true
fi
BUILT_AT="$(date -u +%Y-%m-%dT%H:%M:%SZ)"
BUILD_NAME=""
if [ -x "$IDENTITY_SRC/sigil-name.sh" ]; then
  BUILD_NAME="$("$IDENTITY_SRC/sigil-name.sh" --realm forge --hash "$GIT_HASH" 2>/dev/null || true)"
fi

# --- safety: does this device even LOOK like a camera card?
#
# Every check above answers "is this safe to erase in principle" - removable,
# not the system disk. None of them answers "is this the RIGHT card", and that
# is the question that actually goes wrong.
#
# THIS GUARD EXISTS BECAUSE IT ALMOST HAPPENED, 2026-08-06. Asked to write a
# card, the only removable device present was /dev/sdc: 29.7 GB, three
# partitions - NTFS "MULTITOOL", vfat "BOOTSTRAP", squashfs - all mounted. JP's
# bootable multitool card. It passes `removable=1`, it is not the system disk,
# and it would have been erased by anyone who typed ERASE at a prompt showing an
# lsblk listing they skimmed.
#
# The lsblk print below is the right design and it is not enough on its own: a
# listing you have to interpret is a guard that fails whenever the reader is in
# a hurry, which is exactly when this is run. So refuse by DEFAULT and make the
# operator override deliberately.
#
# A camera card is one of exactly two shapes: blank/unpartitioned, or a single
# FAT32 partition (a card this tool has written before, or a new card as sold).
# Anything else is somebody's else's data until proven otherwise.
PARTS="$(lsblk -lno NAME,FSTYPE,LABEL "$DEV" 2>/dev/null | tail -n +2)"
NPART="$(printf '%s' "$PARTS" | grep -c . || true)"
ODD=0
if [ "$NPART" -gt 1 ]; then
  ODD=1
elif [ "$NPART" -eq 1 ]; then
  case "$(printf '%s' "$PARTS" | awk '{print $2}')" in
    vfat|"") : ;;
    *) ODD=1 ;;
  esac
fi
if [ "$ODD" -eq 1 ] && [ "$FORCE_WIPE" -eq 0 ]; then
  MOUNTED="$(lsblk -lno NAME,MOUNTPOINT "$DEV" | awk 'NF>1 {print "      /dev/"$1" -> "$2}')"
  die "$DEV does not look like a camera card, so this tool is refusing it.

  A camera card is blank, or a single FAT32 partition. This device has $NPART
  partitions:

$(printf '%s' "$PARTS" | sed 's/^/      /')
${MOUNTED:+
  and these are MOUNTED RIGHT NOW - something is using this device:

$MOUNTED
}
  If that is genuinely the card you meant, pass --force-wipe. If it is a
  multitool, an installer, a backup or somebody's photos, this refusal just
  saved it."
fi

SIZE_H="$(lsblk -dno SIZE "$DEV" | tr -d ' ')"
MODEL="$(lsblk -dno MODEL "$DEV" | sed 's/ *$//')"
echo "Target : $DEV  ($SIZE_H, ${MODEL:-unknown})"
echo "Source : $BACKUP"
echo "Build  : ${BUILD_NAME:-<unnamed>}  (branch $GIT_BRANCH, dirty=$GIT_DIRTY)"
if [ -n "$UNIT_NAME" ]; then
  echo "Unit   : $UNIT_NAME  (--unit-name; applies ONLY to a camera never named before)"
else
  echo "Unit   : self-named at first boot from the camera's own MAC"
fi
if [ "$STOCK" -eq 1 ]; then
  echo "Mode   : --stock (backup contents only, NO project fixes)"
else
  echo "Mode   : fixes applied (timezone, ptz_init_on_boot, ctl, RCE fix)"
  echo "IR-cut : stock binaries + direct-GPIO ctl + boot mitigation (no binary patch)"
fi

# --- network preflight, BEFORE the destructive step.
#
# This block exists because the warning it replaces fired at the END of the run.
# A warning that arrives after the card is written is documentation, not a guard:
# by then the only remaining action is to run the tool again. Both values below
# are "inherited from a backup and may no longer be real", and both fail SILENTLY
# on the camera - a wrong SSID never associates, a wrong time_source never syncs.
#
# Read straight out of the tarball so this can run before anything is erased.
#
# --wildcards and a leading * are load-bearing: this archive stores members as
# "./anyka_hack/gergesettings.txt", so an exact-name extract matches NOTHING and
# returns empty. That failure is silent, and it would have turned this whole guard
# into a block that always prints <unreadable> - a guard that cannot fail loudly is
# not a guard, which is the entire point of moving these checks up here.
BAKED_SETTINGS="$(tar -xzOf "$BACKUP/yicam-files.tar.gz" \
                    --wildcards '*anyka_hack/gergesettings.txt' 2>/dev/null || true)"
BAKED_SSID="$(printf '%s\n' "$BAKED_SETTINGS" | sed -n 's/^wifi_ssid=//p' | head -1)"
BAKED_TS="$(printf '%s\n' "$BAKED_SETTINGS"   | sed -n 's/^time_source=//p' | head -1)"

echo
echo "Network settings this card will carry:"
if [ -n "$SSID" ]; then
  printf '  SSID        : %s  (set by --ssid)\n' "$SSID"
  echo   "                NOTE: the PSK is NOT changed. If this network uses a different"
  echo   "                key, edit wifi_password= on the card before first boot."
else
  printf '  SSID        : %s  (INHERITED from the backup, kept by --keep-ssid)\n' "${BAKED_SSID:-<unreadable>}"
  echo   "                >> Confirm this SSID is still broadcasting. A camera looking for"
  echo   "                >> an absent SSID is invisible: no association, no auth failure,"
  echo   "                >> nothing in any log. It looks exactly like dead hardware."
fi
if [ -n "$TIME_SOURCE" ]; then
  printf '  time_source : %s  (set by --time-source)\n' "$TIME_SOURCE"
else
  printf '  time_source : %s  (INHERITED from the backup)\n' "${BAKED_TS:-<unreadable>}"
  echo   "                >> If that is not this camera's gateway, NTP silently never syncs"
  echo   "                >> and the clock sits at 1969. Use --time-source."
fi
if [ -z "$BAKED_SSID" ]; then
  # --keep-ssid means "keep the value I can see". If we cannot show it, that
  # instruction is meaningless and the dangerous case is exactly this one.
  [ "$KEEP_SSID" -eq 1 ] && die "cannot read wifi_ssid out of the backup, so --keep-ssid
  cannot be confirmed. Refusing to write a card whose SSID nobody has seen.
  Pass --ssid NAME explicitly, or check $BACKUP/yicam-files.tar.gz."
  warn "could not read wifi_ssid out of the backup (harmless - --ssid overrides it anyway)"
fi

# --- SSH preflight, also BEFORE the destructive step, and for the same reason.
#
# THE KEY TYPE IS NOT A PREFERENCE HERE, IT IS A HARD CONSTRAINT, and getting it
# wrong fails SILENTLY - which is why this is a guard and not a doc note.
#
# The dropbear on these cameras is v2016.74. MEASURED from the binary: it offers
# ssh-dss, ssh-rsa and ecdsa-sha2-nistp256/384/521, and NO ssh-ed25519.
# Confirmed on a live camera with a control - an ed25519 key placed IN
# authorized_keys was refused while an ECDSA key in the same file on the same
# server succeeded, which rules out "not authorized" as the explanation.
# (curve25519-sha256@libssh.org IS in the binary. That is key EXCHANGE, not a
# key type. Do not read it as ed25519 support.)
#
# ssh-rsa is technically accepted by the daemon but is SHA-1 signed, which
# OpenSSH 8.8+ refuses by default at both ends - so it "works" only for a client
# that has been specially configured, forever.
#
# An unusable key does not produce an error on the camera. It produces a camera
# that accepts nobody. If telnet has since been turned off, that is a card pull.
SSH_OK=0
SSH_KEYCOUNT=0
if [ "$STOCK" -eq 1 ]; then
  echo
  echo "SSH: not installed (--stock ships no scripts)"
elif [ "$NO_SSH" -eq 1 ]; then
  echo
  echo "SSH: not installed (--no-ssh)"
  NOTES+=("SSH was NOT installed (--no-ssh). This camera's only remote access is")
  NOTES+=("  telnet and the writable-root FTP, both gated by a reusable password.")
elif [ ! -f "$AUTHORIZED_KEYS" ]; then
  echo
  echo "SSH: not installed - no authorized-keys file at $AUTHORIZED_KEYS"
  warn "no SSH public key found, so this card gets NO SSH."
  NOTES+=("SSH NOT installed: $AUTHORIZED_KEYS does not exist.")
  NOTES+=("  Create it (one ECDSA public key per line) or pass --authorized-keys FILE.")
  NOTES+=("  Until then this camera's only remote access is telnet + writable-root FTP.")
else
  # Classify every key line from the FILE rather than trusting the filename or
  # the operator's intent. Count usable and unusable separately: a file that
  # contains only unusable keys is a MISCONFIGURATION, not an absence, and the
  # camera it produces would look correct and accept nobody.
  # Matched with a leading (^|space) rather than anchored hard at ^, because a
  # real authorized_keys line may carry an options prefix
  # (command="...", no-port-forwarding, from="..."), and anchoring would score a
  # perfectly good key as unusable and abort the run. Comment lines are dropped
  # first so a key type MENTIONED in a comment cannot be counted as present -
  # which is the mirror-image error and the one that fails silently.
  SSH_KEYSRC="$(grep -vE '^[[:space:]]*(#|$)' "$AUTHORIZED_KEYS" || true)"
  SSH_KEYCOUNT=$(printf '%s\n' "$SSH_KEYSRC" \
                   | grep -cE '(^|[[:space:]])ecdsa-sha2-nistp(256|384|521)[[:space:]]' || true)
  SSH_BADTYPES=$(printf '%s\n' "$SSH_KEYSRC" \
                   | grep -oE '(^|[[:space:]])(ssh-ed25519|ssh-rsa|ssh-dss|sk-[a-z0-9@.-]+)[[:space:]]' \
                   | sed 's/[[:space:]]//g' | sort -u | tr '\n' ' ' || true)
  # sed, not `tr -d '[:space:]'`. tr deletes the NEWLINES too, so every match
  # collapses into one token and two distinct bad types print as
  # "ssh-ed25519ssh-rsa" - a message that names the problem wrongly at exactly
  # the moment someone is relying on it to tell them which key to replace.
  echo
  echo "SSH: $SSH_KEYCOUNT usable ECDSA key(s) in $(basename "$AUTHORIZED_KEYS")"
  if [ -n "$SSH_BADTYPES" ]; then
    warn "these key types CANNOT authenticate to dropbear 2016.74: $SSH_BADTYPES"
    NOTES+=("authorized_keys contains key types this camera cannot use: $SSH_BADTYPES")
    NOTES+=("  They are inert - they will be installed and will never authenticate.")
  fi
  if [ "$SSH_KEYCOUNT" -eq 0 ]; then
    die "$AUTHORIZED_KEYS contains no ECDSA key, only: ${SSH_BADTYPES:-nothing recognisable}.
  Dropbear 2016.74 cannot authenticate any of those, so this card would produce a
  camera that accepts NOBODY over SSH - which looks identical to a working one
  until you need it.
  Generate one:   ssh-keygen -t ecdsa -b 256 -C anyka-cameras -f ~/.ssh/anyka_ecdsa
  then put ~/.ssh/anyka_ecdsa.pub in $AUTHORIZED_KEYS.
  Or pass --no-ssh to write a telnet-only card deliberately."
  fi
  command -v dropbearkey >/dev/null 2>&1 || die "dropbearkey not found (apt install dropbear-bin).
  It generates this camera's own host key. Refusing to fall back to the key that
  ships with the hack: that key's PRIVATE half is published in the upstream repo,
  so it authenticates nothing and lets anyone impersonate this camera."
  SSH_OK=1
fi

echo
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

# Vaultwarden item holding the camera's root password. Deliberately a NAME, not
# a value: this file is in a public repo. Override with VAULT_ITEM=... if a
# camera ever needs its own credential rather than the shared one.
VAULT_ITEM="${VAULT_ITEM:-anyka-cam1-root}"
APPDIR="$MNT/anyka_hack/libre_anyka_app"
# NOTES is declared up with the argument parsing, NOT here. It used to be
# initialised at this line, which is AFTER the pre-erase preflights - so any
# note added by a guard that runs before the erase was silently discarded by the
# re-initialisation. Nothing failed; the notes just never printed. Moving a
# declaration below its first use is invisible in review because both halves
# look correct on their own.

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

  # --- 5a2. the root password comes from the VAULT, never from this repo.
  #
  # Factory/config.sh sets the root password on EVERY boot, so the card is the
  # authoritative copy: changing it on a running camera and not here means the
  # next reboot silently reverts it. That is exactly what happened on 2026-08-06
  # -- the live camera and its own card were both updated, and this writer, the
  # source every FUTURE card is generated from, was missed. A spare card written
  # hours earlier still carried the old value.
  #
  # The same credential is accepted by telnet AND by the writable-root FTP that
  # rc.local starts on all interfaces, so it is not a convenience password.
  #
  # Fails closed: no vault, no card. A card that silently falls back to the
  # backup's placeholder would be worse than no card, because it would look
  # identical to a correct one.
  # The vault session belongs to the INVOKING user, not to root, so `bw` under
  # sudo finds no session -- which looks identical to a locked vault, and
  # `sudo -u "$SUDO_USER" -i bw ...` hangs on a login shell. Accept the value
  # through the environment instead:
  #
  #     export ANYKA_ROOT_PW="$(bw get password anyka-cam1-root)"
  #     sudo -E tools/write-sd-card.sh /dev/sdX --ssid NAME
  #
  # Passed in the ENVIRONMENT rather than as an argument, so it never appears in
  # argv where any user on the box could read it out of `ps`.
  ROOT_PW="${ANYKA_ROOT_PW:-}"
  [ -z "$ROOT_PW" ] && ROOT_PW="$(bw get password "$VAULT_ITEM" 2>/dev/null || true)"
  if [ -z "$ROOT_PW" ]; then
    die "could not read '$VAULT_ITEM' from the vault (is bw unlocked?).
  Refusing to write a card whose root password nobody has seen - the alternative
  is a card that silently ships the backup's placeholder."
  fi
  case "$ROOT_PW" in
    *[\'\"\\/]*) die "the vault password contains a quote, backslash or slash, which
  this substitution cannot safely embed in Factory/config.sh. Regenerate it." ;;
  esac
  if grep -q '^NEW_PASSWORD=' "$CONFIG_SH" 2>/dev/null; then
    sed -i "s|^NEW_PASSWORD=.*|NEW_PASSWORD='$ROOT_PW'|" "$CONFIG_SH"
    # Verify the EFFECT, not the invocation: exactly one assignment, and it is
    # not the placeholder we started from.
    if [ "$(grep -c '^NEW_PASSWORD=' "$CONFIG_SH")" != "1" ] \
       || grep -q "^NEW_PASSWORD=.donkey" "$CONFIG_SH"; then
      die "the root-password substitution did not take. Refusing to ship this card."
    fi
    echo "==> root password set from vault item '$VAULT_ITEM' (not shown)"
  else
    die "Factory/config.sh has no NEW_PASSWORD= line - the card's password
  mechanism has changed and this writer's assumption is stale. Stopping."
  fi

  # --- 5b. restore the isp_*.conf symlink on every boot.
  #
  # FIXING THE BRACKET ABOVE IS NOT ENOUGH, and that is the whole point of this
  # block. Upstream's guard tests the WRONG FILE:
  #
  #     FILE="/mnt/isp_gc1084.conf"
  #     if [ ! -e "$FILE" ]; then  tar -xzf ... ; ln -s ... /etc/jffs2/ ;  fi
  #
  # It tests the TARGET, on the card, to decide whether to create the SYMLINK,
  # in flash. Those are two different questions and the answer to the first is
  # almost always "it exists" - so whenever the symlink alone goes missing, the
  # condition is false and it is never recreated. Repairing the bracket makes
  # the broken guard run correctly; it does not make it ask the right thing.
  #
  # And the symlink does go missing, routinely: /usr/sbin/update.sh's
  # update_ispconfig() is an UNGUARDED `rm -rf /etc/jffs2/isp*.conf` that runs
  # on every firmware update - including one that flashes nothing. Without this,
  # any successful update costs video permanently. See docs/firmware-update.md.
  #
  # Inserted BEFORE gergehack.sh rather than appended after it, unlike the
  # IR-cut and identity hooks: gergehack.sh insmods the sensor module and starts
  # the video app, so a repair that ran afterwards would be one boot too late.
  #
  # Globs over whatever the card actually carries instead of hardcoding
  # isp_gc1084.conf - the bag is not all one sensor, and a hardcoded name would
  # be silently correct here and silently wrong on an H63 board.
  #
  # Tests before linking rather than `ln -sf` unconditionally: /etc/jffs2 is a
  # 64 KB partition at 88% full, and an unconditional relink would burn a jffs2
  # write on every boot of every camera forever to fix something that is almost
  # never broken.
  if grep -q 'isp_\*.conf' "$CONFIG_SH" 2>/dev/null; then
    echo "==> isp symlink repair already present in Factory/config.sh"
  else
    echo "==> adding the isp symlink repair to Factory/config.sh"
    ISP_REPAIR='
# restore any isp_*.conf symlink that update.sh'"'"'s update_ispconfig() deleted.
# Upstream'"'"'s guard above tests the target on the card, not the symlink, so it
# never fires for this. See docs/firmware-update.md.
for f in /mnt/isp_*.conf; do
  [ -e "$f" ] || continue
  [ -e "/etc/jffs2/${f##*/}" ] || ln -s "$f" /etc/jffs2/
done
'
    awk -v block="$ISP_REPAIR" '
      /^\/etc\/jffs2\/gergehack\.sh$/ && !done { print block; done = 1 }
      { print }
    ' "$CONFIG_SH" > "$CONFIG_SH.new" && mv "$CONFIG_SH.new" "$CONFIG_SH"
    grep -q 'isp_\*.conf' "$CONFIG_SH" || {
      warn "isp symlink repair was NOT inserted - Factory/config.sh has no bare"
      warn "  /etc/jffs2/gergehack.sh line to anchor to. Insert it by hand."
      NOTES+=("isp symlink repair MISSING from Factory/config.sh - a firmware update")
      NOTES+=("  would cost this camera its video permanently. See docs/firmware-update.md.")
    }
  fi

  # --- 6. assert the vendor app on this card is the STOCK binary.
  #
  # This is a guard, not a fix: if someone patches the backup (or restores an
  # older one taken while the ircut patch was applied), a card would silently
  # ship a binary we deliberately do not ship. Loud, non-fatal, and it names the
  # md5 so the mismatch is diagnosable.
  if [ -f "$APPDIR/libre_anyka_app" ]; then
    got="$(md5sum "$APPDIR/libre_anyka_app" | cut -d' ' -f1)"
    if [ "$got" != "$LAA_STOCK_MD5" ]; then
      warn "libre_anyka_app on this card is $got, expected stock $LAA_STOCK_MD5"
      NOTES+=("libre_anyka_app is NOT the stock binary ($got).")
      NOTES+=("  -> if this is the ircut patch, it is INERT but unwanted; see docs/ptz.md.")
    fi
  else
    warn "libre_anyka_app not found in the backup - the camera will have no RTSP"
    NOTES+=("libre_anyka_app MISSING from the backup. This card will not stream.")
  fi

  # --- 7. keep the IR-cut filter out of the magenta position on every boot.
  #
  # JP relies on this: "we used to apply the ircut filter to fix the magenta on
  # startup bug". It is on his live card at /Factory/config.sh, with his comment,
  # and it was ONLY ever missing from the backup - so no card this tool has ever
  # produced had it, and every fresh camera boots magenta and stays that way.
  #
  # This is a user-relied-on behaviour, not a workaround we invented. Do not drop
  # it because it looks like a hack; it is the ONLY automatic IR-cut action that
  # works on this board (see docs/ptz.md - automatic day/night is unfixable here,
  # the sense input the vendor driver wants does not exist on this hardware).
  #
  # The 60 s delay is deliberate: gergehack.sh and the module loads have to finish
  # before /sys/user-gpio/ is populated.
  #
  # Appending puts it at line 33, which is exactly where it sits on JP's live card
  # - the backup's config.sh is 30 lines, +blank +comment +command. That match is
  # a useful check on two things at once: the placement is right, and gergehack.sh
  # RETURNS rather than blocking (otherwise JP's own line would never have run).
  if grep -q 'user-gpio/ircut_a' "$CONFIG_SH" 2>/dev/null; then
    echo "==> boot-time IR-cut mitigation already present in Factory/config.sh"
  else
    echo "==> adding the boot-time IR-cut mitigation to Factory/config.sh"
    cat >> "$CONFIG_SH" <<'IRCUT'

# keep the IR cut filter in the non-pink position on every boot
(sleep 60; echo 1 > /sys/user-gpio/ircut_a) &
IRCUT
  fi

  # --- 8. give the camera a name of its own, once, at first boot.
  #
  # Backlog gap 1: "a camera has no identity - every card is the same card".
  # The fix has to be in TWO places because there are two different facts:
  #
  #   the UNIT  is the camera, and its name must survive a card swap
  #             -> /data/unit.json (mtd7). NOT /etc/jffs2: that is mtd6, slot
  #                "C" of the stock updater, so a firmware update erases it.
  #                See reference/usr-sbin/README.md.
  #   the BUILD is the card,   and its version must follow the card   -> here
  #
  # This installs the unit half. The camera derives its own name from its own
  # MAC at first boot, so a camera taken out of the bag today names itself with
  # zero configuration and no registry to keep in sync. Write-once: re-writing
  # a card never renames a camera.
  #
  # The word tables are a pinned snapshot of realm-sigil's generated tables -
  # see tools/identity/PINNED.md. They are pinned because the word COUNT is the
  # modulus, so a word added upstream would rename every camera in the bag.
  echo "==> installing the identity toolkit + first-boot naming hook"
  ID_DST="$MNT/anyka_hack/identity"
  mkdir -p "$ID_DST"
  # `cp` for the data files, NOT `install -m 644`.
  #
  # FAT32 has no permission bits at all - a file's apparent mode is synthesised
  # from the mount's fmask/dmask, so `install -m 644` asks the kernel for a mode
  # the filesystem cannot store. Whether that is silently ignored or returns
  # EPERM depends on the mount options, and under `set -e` the EPERM case would
  # abort this script AFTER the card was erased. NOT MEASURED: no vfat mount was
  # available on the workstation to settle which happens here.
  #
  # `cp` never asks the question. `install -m 755` is kept for the scripts only
  # because the ctl install above already does exactly that and is known to work
  # on a real card - so it is a proven path, not a fresh bet.
  for f in sigil-name.sh name-unit.sh whoami.sh fleet.adjectives fleet.nouns; do
    if [ -f "$IDENTITY_SRC/$f" ]; then
      case "$f" in
        *.sh) install -m 755 "$IDENTITY_SRC/$f" "$ID_DST/$f" ;;
        *)    cp "$IDENTITY_SRC/$f" "$ID_DST/$f" ;;
      esac
    else
      warn "identity file missing: $IDENTITY_SRC/$f"
      NOTES+=("identity toolkit INCOMPLETE ($f missing) - this camera will not name itself.")
    fi
  done
  # forge tables are NOT shipped: build names are resolved here, on the
  # workstation, and baked into build.json. The camera never needs them.

  if [ -n "$UNIT_NAME" ]; then
    echo "==> pre-naming this camera \"$UNIT_NAME\" (only if it has never been named)"
    printf '%s\n' "$UNIT_NAME" > "$ID_DST/unit-name.override"
    NOTES+=("--unit-name only applies to a camera with NO existing name. Naming is")
    NOTES+=("  write-once in flash, so a camera that already has one keeps it.")
  fi

  # Same seam and same shape as the IR-cut line above: appended to config.sh,
  # backgrounded, and idempotent on re-write. name-unit.sh does its own waiting
  # for the MAC rather than guessing a sleep, because the interface only appears
  # once gergehack.sh has run wifi_manage.sh.
  if grep -q 'identity/name-unit.sh' "$CONFIG_SH" 2>/dev/null; then
    echo "==> first-boot naming hook already present in Factory/config.sh"
  else
    echo "==> adding the first-boot naming hook to Factory/config.sh"
    # Invoked via `sh`, and tested with -f rather than -x, ON PURPOSE. On FAT32
    # the execute bit comes from the mount's fmask, not from the file, so an -x
    # test is really a test of how the kernel happened to mount the card.
    #
    # MEASURED, on the real camera: exec off the card does work - gergehack.sh
    # runs /mnt/anyka_hack/ptz/run_ptz.sh and start_web_interface.sh directly.
    # So this is not fixing a known breakage; it is refusing to make a
    # write-once naming decision depend on a mount option. A hook that silently
    # never runs is this project's signature failure.
    cat >> "$CONFIG_SH" <<'IDENTITY'

# name this camera once, from its own MAC (docs/identity.md)
[ -f /mnt/anyka_hack/identity/name-unit.sh ] && sh /mnt/anyka_hack/identity/name-unit.sh &
IDENTITY
  fi

  # --- 8b. key-only SSH, with a host key this camera actually owns.
  #
  # 🔴 THE HOST KEY THAT SHIPS WITH THE HACK IS PUBLISHED. Measured 2026-08-06:
  # the dropbear_ecdsa_host_key in the backup, on both of JP's cameras, and in
  # the upstream repo's SD_card_contents are all md5 d643a89f07f51cb32412d66fd34ef34b
  # - fetched over plain HTTP from gitea.raspiweb.com to confirm it, not inferred
  # from the fact that two cameras matched.
  #
  # So its PRIVATE half is downloadable by anyone. Host-key verification is the
  # one thing SSH adds over telnet against someone already on the camera VLAN,
  # and a published key inverts it: an impersonator verifies correctly and the
  # client shows no warning at all. Every card therefore gets a FRESH key, and
  # the published one is overwritten rather than left lying on the card.
  #
  # GENERATED HERE, ON THE WORKSTATION, NOT ON THE CAMERA. dropbear's -R would
  # generate one at first boot and it would be a worse key: the camera reports
  # ~180 bits in /proc/sys/kernel/random/entropy_avail, which is a poor source
  # for something long-lived. This box has a real CSPRNG; the camera does not.
  #
  # ECDSA and not ed25519 - see the preflight above. That is a property of
  # dropbear 2016.74, not a preference.
  SSH_DIR="$MNT/anyka_hack/dropbear"
  SSH_CARD_KEY="$SSH_DIR/dropbear_ecdsa_host_key"
  if [ "$SSH_OK" -eq 1 ]; then
    echo "==> generating this card's own SSH host key + installing key-only SSH"
    mkdir -p "$SSH_DIR"
    # Generated to a temp file on a REAL filesystem, then copied. dropbearkey
    # creates its output 0600, and FAT32 cannot store that - rather than find out
    # per-mount whether the mode request is ignored or fails, generate where the
    # permission bits mean something and copy the bytes across.
    SSH_TMP="$(mktemp)"
    rm -f "$SSH_TMP"
    if dropbearkey -t ecdsa -s 256 -f "$SSH_TMP" >/dev/null 2>&1 && [ -s "$SSH_TMP" ]; then
      cp "$SSH_TMP" "$SSH_CARD_KEY"
      shred -u "$SSH_TMP" 2>/dev/null || rm -f "$SSH_TMP"
    else
      rm -f "$SSH_TMP"
      die "dropbearkey failed to produce a host key. Refusing to ship the published one."
    fi
    # Assert the EFFECT: a real key landed AND it is not the published one. Both
    # halves matter - a zero-byte file and the upstream key are both "a file that
    # exists", and this script's own history is full of guards that checked
    # existence when they meant content.
    got="$(md5sum "$SSH_CARD_KEY" | cut -d' ' -f1)"
    [ -s "$SSH_CARD_KEY" ] || die "host key did not land on the card. Do not ship this card."
    [ "$got" != "d643a89f07f51cb32412d66fd34ef34b" ] \
      || die "the card still carries the PUBLISHED upstream host key. Do not ship this card."
    echo "    host key: $got (fresh, unique to this card)"

    cp "$AUTHORIZED_KEYS" "$SSH_DIR/authorized_keys"
    if [ -f "$REPO/tools/ssh/ssh-up.sh" ]; then
      install -m 755 "$REPO/tools/ssh/ssh-up.sh" "$SSH_DIR/ssh-up.sh"
    else
      die "tools/ssh/ssh-up.sh is missing - nothing would start SSH on this card."
    fi

    # --- the boot hook, and WHERE it goes is the whole story.
    #
    # INSERTED BEFORE gergehack.sh, exactly like the isp repair above and
    # UNLIKE the IR-cut and identity hooks, which are appended after it.
    #
    # BECAUSE GERGEHACK.SH NEVER RETURNS. Its last statement is
    #
    #     if [[ $run_ipc == 0 ]] && [[ $rootfs_modified == 0 ]]; then
    #       while [ 1 ]; do sleep 30; done
    #     fi
    #
    # and Factory/config.sh calls it synchronously. MEASURED on both of JP's
    # cameras: `ps` shows config.sh and gergehack.sh both still resident with a
    # `sleep 30` under them, indefinitely. The backup every card is built from
    # carries rootfs_modified=0, and this script never changes it - so the loop
    # fires on every card this tool has ever written.
    #
    # Proven rather than reasoned: a tracer appended as the LAST line of
    # config.sh never ran across two reboots, and the same hook placed here came
    # up 32 seconds after a cold boot.
    #
    # >>> ANYTHING APPENDED TO Factory/config.sh AFTER THE gergehack.sh LINE IS
    # >>> DEAD CODE. Do not "tidy" this hook down to join the others.
    #
    # rootfs_modified is deliberately NOT flipped to 1 to make gergehack return:
    # it is a claim about whether this camera's rootfs launches anyka_ipc,
    # changing it alters vendor-app behaviour, and editing gergesettings.txt also
    # triggers gergehack's own card->flash sync AND A REBOOT.
    if grep -q 'dropbear/ssh-up.sh' "$CONFIG_SH" 2>/dev/null; then
      echo "==> SSH boot hook already present in Factory/config.sh"
    else
      echo "==> adding the SSH boot hook to Factory/config.sh (before gergehack.sh)"
      SSH_HOOK='
# key-only SSH. MUST stay BEFORE gergehack.sh: gergehack never returns (it ends
# in an infinite sleep loop when rootfs_modified=0), so anything after it in
# this file never executes. See tools/ssh/ssh-up.sh.
[ -f /mnt/anyka_hack/dropbear/ssh-up.sh ] && sh /mnt/anyka_hack/dropbear/ssh-up.sh &
'
      awk -v block="$SSH_HOOK" '
        /^\/etc\/jffs2\/gergehack\.sh$/ && !done { print block; done = 1 }
        { print }
      ' "$CONFIG_SH" > "$CONFIG_SH.new" && mv "$CONFIG_SH.new" "$CONFIG_SH"
      # Verify placement, not just presence: a hook that landed AFTER the
      # gergehack line would be silently dead, which is the exact failure this
      # whole block exists to avoid.
      hookline="$(grep -n '^\[ -f /mnt/anyka_hack/dropbear/ssh-up.sh \]' "$CONFIG_SH" | cut -d: -f1)"
      gergeline="$(grep -n '^/etc/jffs2/gergehack.sh$' "$CONFIG_SH" | cut -d: -f1)"
      if [ -z "$hookline" ] || [ -z "$gergeline" ] || [ "$hookline" -gt "$gergeline" ]; then
        warn "SSH boot hook is missing or lands AFTER gergehack.sh - it would never run."
        NOTES+=("SSH boot hook NOT correctly placed in Factory/config.sh. SSH will not")
        NOTES+=("  start on this card. Insert it by hand ABOVE the /etc/jffs2/gergehack.sh line.")
      fi
    fi
  elif [ -f "$SSH_CARD_KEY" ]; then
    # No SSH on this card - but the published private key still arrived here from
    # the backup, and a key whose private half is on the public internet has no
    # business sitting on a card in a drawer. Nothing starts it today; that is an
    # argument for deleting it being free, not for keeping it.
    rm -f "$SSH_CARD_KEY"
    echo "==> removed the PUBLISHED upstream dropbear host key from this card"
    NOTES+=("The published upstream dropbear host key was deleted from this card.")
  fi

  # --- 9. the speaker volume ladder: six one-byte variants of ak_adec_demo.
  #
  # ctl takes an optional &level=1..6 and runs ak_adec_demo.volN. Absent,
  # malformed or out-of-range falls back to the default binary (level
  # $ADEC_DEFAULT_LEVEL), and a missing variant falls back the same way - which
  # is deliberate, because a volume control that can wedge the speaker into
  # silence is worse than no volume control.
  #
  # That fallback is exactly why this section has to exist and has to be checked.
  # Without it a fresh card has no ladder at all: every .volN is missing, every
  # -x test fails, and the camera quietly reverts to the too-loud stock level
  # with no error anywhere. A hook that silently never runs is this project's
  # signature failure, so the result is ASSERTED below, not assumed.
  #
  # Generated here rather than committed: six 36 KB binaries that differ from
  # each other by ONE BYTE do not belong in git.
  ADEC_DIR="$MNT/anyka_hack/ak_adec_demo"
  if [ -f "$ADEC_DIR/ak_adec_demo" ]; then
    # .orig is seeded ONCE, from whatever the backup shipped, and every variant
    # is cut from .orig rather than from the live file. Without that guard a
    # second run would ladder an already-laddered binary and every level would be
    # wrong by the previous default - silently, since all six would still exist.
    [ -f "$ADEC_DIR/ak_adec_demo.orig" ] || cp "$ADEC_DIR/ak_adec_demo" "$ADEC_DIR/ak_adec_demo.orig"

    adec_base="$(md5sum "$ADEC_DIR/ak_adec_demo.orig" | cut -d' ' -f1)"
    if [ "$adec_base" != "$ADEC_STOCK_MD5" ]; then
      warn "ak_adec_demo base is $adec_base, expected stock $ADEC_STOCK_MD5 - NOT building the ladder"
      NOTES+=("speaker volume ladder SKIPPED: base binary is $adec_base, not stock.")
      NOTES+=("  -> ctl's &level= will silently fall back to the default at every level.")
    else
      echo "==> building the speaker volume ladder (default level $ADEC_DEFAULT_LEVEL)"
      for n in 1 2 3 4 5 6; do
        cp "$ADEC_DIR/ak_adec_demo.orig" "$ADEC_DIR/ak_adec_demo.vol$n"
        printf "\0$n" | dd of="$ADEC_DIR/ak_adec_demo.vol$n" \
          bs=1 seek="$ADEC_VOL_OFFSET" conv=notrunc status=none
      done
      cp "$ADEC_DIR/ak_adec_demo.vol$ADEC_DEFAULT_LEVEL" "$ADEC_DIR/ak_adec_demo"

      # REPORT what was installed; do not merely assert a constant. A gate that
      # checks a stale expectation is worse than no gate, because it reads as
      # verification - and repo/device copies have already been observed to
      # drift once today (see docs/backlog.md item 8).
      for n in 1 2 3 4 5 6; do
        printf '      vol%s  %s\n' "$n" "$(md5sum "$ADEC_DIR/ak_adec_demo.vol$n" | cut -d' ' -f1)"
      done

      # The self-check with teeth: vol6 IS the stock file, zero bytes changed,
      # because stock is already level 6. So one comparison proves BOTH that the
      # base was stock and that ADEC_VOL_OFFSET landed on the right byte. If the
      # offset were wrong, vol6 would differ from stock and this would catch it.
      adec_v6="$(md5sum "$ADEC_DIR/ak_adec_demo.vol6" | cut -d' ' -f1)"
      if [ "$adec_v6" != "$ADEC_STOCK_MD5" ]; then
        warn "ladder self-check FAILED: vol6 is $adec_v6, must equal stock $ADEC_STOCK_MD5"
        NOTES+=("volume ladder is WRONG: vol6 must be byte-identical to stock.")
        NOTES+=("  -> ADEC_VOL_OFFSET is suspect. Do not ship this card.")
      fi
    fi
  else
    warn "ak_adec_demo not found in the backup - this card will have no volume control"
    NOTES+=("ak_adec_demo MISSING: ctl's &level= will do nothing on this card.")
  fi
fi

# --- the build marker. Written on EVERY card including --stock.
#
# --stock means "no project FIXES", and this is not a fix - it is a label, and
# nothing on the camera executes it. An unlabelled stock card is precisely the
# "every card is the same card" problem, and it is the card you least want to be
# holding unlabelled when you are comparing it against a patched one.
#
# Field names follow realm-sigil's version response where they apply. The
# server-only fields (started, uptime, pid, runtime) are omitted - a card is not
# a running process.
#
# DELIBERATELY ABSENT: wifi_ssid, wifi_password and time_source. Only booleans
# saying whether each was set. This file is the one that gets copied into
# tickets and pasted into chat; it must not be the second place the real SSID
# and the real VLAN address live.
echo "==> writing build marker /anyka_hack/build.json"
COMMIT_URL=""
[ "$GIT_HASH" != "dev" ] && COMMIT_URL="$REPO_URL/commit/$GIT_HASH"
cat > "$MNT/anyka_hack/build.json" <<JSON
{
  "kind": "build",
  "name": "anyka3918-gc1084-camera",
  "description": "AK3918 + GC1084 camera SD card",
  "version": "${BUILD_NAME:-unknown}",
  "hash": "$GIT_HASH",
  "branch": "$GIT_BRANCH",
  "dirty": $GIT_DIRTY,
  "built": "$BUILT_AT",
  "realm": "forge",
  "repo": "$REPO_URL",
  "commit_url": "$COMMIT_URL",
  "stock": $([ "$STOCK" -eq 1 ] && echo true || echo false),
  "backup": "$(basename "$BACKUP")",
  "writer_host": "$(hostname)",
  "ssid_set": $([ -n "$SSID" ] && echo true || echo false),
  "time_source_set": $([ -n "$TIME_SOURCE" ] && echo true || echo false)
}
JSON
if [ "$GIT_HASH" = "dev" ]; then
  NOTES+=("build.json says hash=dev - git could not identify this checkout, so this")
  NOTES+=("  card cannot tell you which commit produced it. Fix the checkout and rewrite.")
elif [ "$GIT_DIRTY" = "true" ]; then
  NOTES+=("build.json is marked dirty=true - the working tree had uncommitted changes,")
  NOTES+=("  so \"$GIT_HASH\" does NOT fully describe what is on this card.")
fi

echo
echo "==> settings on this card:"
grep -E '^(wifi_ssid|sensor_kern_module|time_source|time_zone|ptz_init_on_boot|run_)' "$SETTINGS" \
  | sed 's/^/    /'
echo "    (wifi_password is set but not shown)"

echo
echo "==> identity on this card:"
echo "    build : ${BUILD_NAME:-unknown}   [$GIT_BRANCH, dirty=$GIT_DIRTY]"
if [ "$STOCK" -eq 1 ]; then
  echo "    unit  : NOT installed (--stock ships no scripts, so no self-naming)"
elif [ -n "$UNIT_NAME" ]; then
  echo "    unit  : \"$UNIT_NAME\" if this camera has never been named, else unchanged"
else
  echo "    unit  : self-named at first boot from the camera's own MAC"
fi

# Both inherited-value hazards are surfaced in the preflight above, before the
# erase, where they can still change the outcome. Repeated here only so they
# survive in a scrollback the operator reads after the fact.
if [ -z "$TIME_SOURCE" ]; then
  NOTES+=("time_source was INHERITED from the backup. If it is not this camera's")
  NOTES+=("  gateway, NTP silently never syncs. Use --time-source.")
fi
if [ "$KEEP_SSID" -eq 1 ]; then
  NOTES+=("wifi_ssid was INHERITED from the backup (--keep-ssid). If that SSID has")
  NOTES+=("  been retired, this camera will be invisible - no association, no logs.")
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
echo "  * This card works in ANY of these cameras. Nothing on it is specific to a"
echo "    kernel build - the only patch is cgi-bin/header, which is kernel-agnostic."
echo "  * IR-cut: MANUAL ONLY, and that is the correct configuration. ctl writes"
echo "    /sys/user-gpio/ircut_a directly, and Factory/config.sh sets the filter to"
echo "    the non-magenta position 60s into every boot. Automatic day/night is NOT"
echo "    fixable on this board - the sense input the vendor driver wants does not"
echo "    exist here. See docs/ptz.md before trying."
echo "  * IDENTITY IS SPLIT ON PURPOSE. The camera's name lives in its own flash"
echo "    (/data/unit.json, mtd7 - the partition the stock updater does not touch)"
echo "    and survives a card swap; the stock update.sh never targets slot D, so a"
echo "    vendor firmware update leaves it alone too. The build version lives"
echo "    on the card (/anyka_hack/build.json) and follows it. So moving a card"
echo "    between cameras moves the BUILD, never the NAME - which is what makes a"
echo "    bag of identical cameras inspectable. Ask a camera who it is with:"
echo "        /mnt/anyka_hack/identity/whoami.sh"
echo "    Naming is write-once: rewriting this card never renames a camera."
echo "  * The card sets the root password from Factory/config.sh on every boot."
if [ "$SSH_OK" -eq 1 ]; then
echo "  * SSH IS KEY-ONLY AND THIS CARD'S HOST KEY IS UNIQUE TO IT. Password login"
echo "    is disabled (dropbear -s), so the root password never crosses the wire."
echo "    The camera ADOPTS this card's host key on first boot into /data/dropbear"
echo "    and KEEPS IT afterwards - rewriting a card does not change a camera's"
echo "    identity, which is what stops routine rewrites training you to click"
echo "    through host-key warnings. authorized_keys, by contrast, is refreshed"
echo "    from the card every boot, so revoking a key means rewriting the card."
echo "  * ECDSA ONLY. This dropbear is v2016.74 and has no ed25519 at all; an"
echo "    ed25519 key installs cleanly and then authenticates nobody."
echo "  * The SSH hook sits BEFORE the gergehack.sh line in Factory/config.sh"
echo "    because gergehack NEVER RETURNS - it ends in an infinite sleep loop"
echo "    whenever rootfs_modified=0, which is what the backup carries. Anything"
echo "    appended AFTER that line is dead code. Do not move the hook."
fi
echo "  * sensor_kern_module points at the GC1084 module ON THIS CARD. If the new"
echo "    camera has a different image sensor, video will not come up until that"
echo "    line and isp_gc1084.conf are swapped for the right sensor."
echo "  * Each camera needs its own card - the card is not shareable between units."
