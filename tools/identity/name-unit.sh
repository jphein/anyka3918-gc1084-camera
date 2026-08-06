#!/bin/sh
# Give this camera its name, once, at first boot. Runs ON THE CAMERA.
#
# Installed by tools/write-sd-card.sh to /mnt/anyka_hack/identity/name-unit.sh
# and launched in the background from /Factory/config.sh.
#
# WHY THE NAME LIVES IN FLASH AND NOT ON THE CARD
# -----------------------------------------------
# The card is the build; the camera is the unit. Move a card between cameras and
# each camera must keep its own name while the build version follows the card -
# that split is the whole point, and it is what makes a bag of identical cameras
# inspectable. So this writes to /etc/jffs2, which survives a card swap.
#
# It writes a file of its OWN NAME rather than a line in gergesettings.txt, and
# that is not a style choice. gergehack.sh diffs the card's gergesettings.txt
# against the flash copy on EVERY boot and, if they differ, copies card -> flash
# and REBOOTS. A per-unit value in that file would make every card per-unit and
# fire the copy-and-reboot path on every swap. gergehack.sh compares exactly two
# filenames - gergesettings.txt and gergehack.sh - so anything else in
# /etc/jffs2 is left alone. /etc/jffs2/webui.hash already relies on this.
#
# WRITE-ONCE, DELIBERATELY
# ------------------------
# If a marker already exists this exits without touching it. Re-writing a card,
# upgrading a build, or swapping a card must never rename a camera.
#
# WHY /data AND NOT /etc/jffs2
# ----------------------------
# Both survive a card swap, so that is not the discriminator. The updater is.
#
# /etc/jffs2 is mtd6, which is slot "C" of the stock updater - a firmware update
# carrying usr.jffs2 overwrites the WHOLE partition. /data is mtd7, slot "D",
# which update.sh never writes. See reference/usr-sbin/README.md, which resolved
# the slot->mtd mapping out of /proc/mtd and the updater binary.
#
# Two caveats recorded there, both respected here:
#   * "D" is REACHABLE - `updater local D=<file>` would resolve, there is no
#     name whitelist. /data is unwritten by the shipped scripts, not unwritable.
#   * update_factory_data.sh does `rm -rf /data/audio_file/*`. So the marker
#     goes at the TOP of /data and never inside audio_file/.
#
# /etc/jffs2 remains a last-resort fallback, loudly logged, and the marker
# records which store it landed in.
#
# THE ONE THING THAT MAKES THIS SURVIVABLE ANYWAY
# -----------------------------------------------
# The name is derived from the MAC, so it is IDEMPOTENT. If a marker is ever
# wiped - by an update, a reflash, anything - the next boot re-derives the SAME
# name from the SAME MAC. The backlog's worry about a wipe producing "a fleet of
# strangers" is true for assigned or random ids; it is not true here.
#
# The exception is --unit-name: an override is NOT derivable, so a wiped
# override is genuinely lost unless the card still carries it. That asymmetry is
# the actual cost of overriding, and it is why self-naming is the default.
#
# NOTHING IS WRITTEN TO THE SD CARD. The card is FAT32 and this runs during
# boot, when power loss is most likely. jffs2 is journalling; FAT is not.

# IDENTITY_TEST_ROOT exists so this script can be exercised on a workstation
# against a fake tree - see selftest.sh. It is empty on the camera and nothing
# in the boot environment sets it. A boot script that cannot be run anywhere but
# on the device is a boot script nobody tests, and this one gets exactly one
# chance per camera to be right.
R="${IDENTITY_TEST_ROOT:-}"

MARKER="$R/data/unit.json"              # primary: mtd7, not touched by update.sh
MARKER_LEGACY="$R/etc/jffs2/unit.json"  # mtd6 = updater slot C. Read, avoid writing.
DIR="$R/mnt/anyka_hack/identity"
OVERRIDE="$DIR/unit-name.override"
NETDIR="$R/sys/class/net"

# Minimum free space (KB) required before writing a ~300 byte file. The margin
# is for jffs2's garbage collector, not for the file. /data has ~760 KB free so
# this should never bite; it exists because the fallback partition has ~8 KB.
FLOOR_KB=4

# The MAC only appears once wifi_manage.sh has brought the interface up, which
# happens inside gergehack.sh - i.e. possibly after this is launched. Poll rather
# than guess a delay.
# Overridable for selftest.sh only; nothing in the boot environment sets these.
WAIT_MAX="${IDENTITY_WAIT_MAX:-300}"
WAIT_STEP="${IDENTITY_WAIT_STEP:-5}"

log() { echo "identity: $*"; }

# --- already named? then we are done, and that is the common case.
if [ -f "$MARKER" ]; then
  log "already named: $(sed -n 's/.*"name": *"\([^"]*\)".*/\1/p' "$MARKER" | head -1)"
  exit 0
fi
if [ -f "$MARKER_LEGACY" ]; then
  # A marker written before /data became the primary store. Honour it - the name
  # is the camera's and must not change - but say where it is, because a
  # firmware update will erase mtd6 and take it with it. The name is
  # MAC-derived, so losing it self-heals to the identical name; an override
  # would not.
  log "already named (LEGACY store $MARKER_LEGACY, mtd6 - a firmware update erases this): $(sed -n 's/.*"name": *"\([^"]*\)".*/\1/p' "$MARKER_LEGACY" | head -1)"
  exit 0
fi

# --- find this camera's MAC.
#
# wlan0 first because this board is WiFi-only - the 80-pin AK3918EN080 does not
# wire up the Ethernet MAC at all, so there is no second real candidate. The
# scan is a fallback for a build that names the interface differently, and it
# skips loopback and the all-zero address a driver reports before it is ready.
mac=""
waited=0
while :; do
  if [ -r "$NETDIR/wlan0/address" ]; then
    mac=$(cat "$NETDIR/wlan0/address" 2>/dev/null)
  fi
  if [ -z "$mac" ] || [ "$mac" = "00:00:00:00:00:00" ]; then
    mac=""
    for f in "$NETDIR"/*/address; do
      [ -r "$f" ] || continue
      case "$f" in */lo/address) continue ;; esac
      candidate=$(cat "$f" 2>/dev/null)
      [ -n "$candidate" ] && [ "$candidate" != "00:00:00:00:00:00" ] && { mac="$candidate"; break; }
    done
  fi
  [ -n "$mac" ] && break
  [ "$waited" -ge "$WAIT_MAX" ] && break
  sleep "$WAIT_STEP"
  waited=$((waited + WAIT_STEP))
done

if [ -z "$mac" ]; then
  # Deliberately writes NOTHING. A camera with no name is a camera you have to
  # look up in the lease table - annoying. A camera named from a fabricated seed
  # is a camera whose name means nothing, and it would be write-once wrong
  # forever. The next boot tries again.
  log "no MAC after ${WAIT_MAX}s - NOT naming this camera. Will retry next boot."
  exit 0
fi

# --- compute the name (or take JP's override verbatim)
if [ -r "$OVERRIDE" ]; then
  name=$(head -1 "$OVERRIDE" | tr -d '\r' | sed 's/"/'"'"'/g')
  short="$name"
  seed=""
  source="override"
  log "using the name from $OVERRIDE"
else
  # `sh <script>` rather than executing it directly. On FAT32 the execute bit
  # comes from the mount's fmask, not from the file, so relying on it would make
  # a write-once naming decision depend on a mount option. Exec off the card is
  # known to work on this camera (gergehack.sh runs card scripts directly) -
  # this is belt and braces on the one action that cannot be retried.
  if [ ! -f "$DIR/sigil-name.sh" ]; then
    log "ERROR $DIR/sigil-name.sh is missing - cannot name this camera"
    exit 0
  fi
  name=$(sh "$DIR/sigil-name.sh" --realm fleet --mac "$mac" 2>/dev/null)
  short=$(sh "$DIR/sigil-name.sh" --realm fleet --mac "$mac" --field short 2>/dev/null)
  seed=$(sh "$DIR/sigil-name.sh" --realm fleet --mac "$mac" --field seed 2>/dev/null)
  source="mac"
  if [ -z "$name" ]; then
    log "ERROR sigil-name.sh produced nothing for MAC $mac - NOT naming. Retry next boot."
    exit 0
  fi
fi

# --- pick a store with room for it
# busybox awk is MEASURED present - login_validate.sh and settings_submit.sh on
# the stock card both use it. df and date are not used by any card script, so
# their presence is assumed, not measured; both are handled if they are absent
# or unparseable rather than allowed to produce a wrong answer.
dest="$MARKER"; store="/data"
if [ ! -d "$R/data" ]; then
  log "WARNING /data is absent - falling back to $MARKER_LEGACY (mtd6), which a"
  log "WARNING firmware update ERASES. The name is MAC-derived so it re-derives"
  log "WARNING identically after a wipe, but an --unit-name override would not."
  dest="$MARKER_LEGACY"; store="/etc/jffs2"
fi
free_kb=$(df "$(dirname "$dest")" 2>/dev/null | awk 'END {print $4}')
case "$free_kb" in
  ''|*[!0-9]*) log "cannot read free space on $store - writing anyway (~300 bytes)" ;;
  *) if [ "$free_kb" -lt "$FLOOR_KB" ]; then
       log "ERROR $store has only ${free_kb}KB free (floor ${FLOOR_KB}KB) - NOT naming."
       log "ERROR Filling a nearly-full jffs2 partition is worse than being unnamed."
       exit 0
     fi ;;
esac

# --- write it. rename() is atomic on jffs2, so a power cut leaves either the
# old state (unnamed) or the complete file - never a half-written marker that
# the write-once check would then refuse to replace.
tmp="$dest.tmp"
{
  echo '{'
  echo '  "kind": "unit",'
  echo "  \"name\": \"$name\","
  echo "  \"short\": \"$short\","
  echo '  "realm": "fleet",'
  echo "  \"mac\": \"$mac\","
  echo "  \"sigil_seed\": \"$seed\","
  echo "  \"source\": \"$source\","
  echo "  \"store\": \"$store\","
  echo "  \"named\": \"$(date -u +%Y-%m-%dT%H:%M:%SZ 2>/dev/null)\","
  echo '  "corpus": "realm-sigil 7cd4e46 fleet 32x32"'
  echo '}'
} > "$tmp" 2>/dev/null

if [ ! -s "$tmp" ]; then
  log "ERROR could not write $tmp - NOT naming this camera. Retry next boot."
  rm -f "$tmp" 2>/dev/null
  exit 0
fi
if mv "$tmp" "$dest" 2>/dev/null; then
  sync
  log "this camera is now \"$name\"  ($dest)"
else
  log "ERROR could not install $dest - NOT naming this camera. Retry next boot."
  rm -f "$tmp" 2>/dev/null
fi
exit 0
