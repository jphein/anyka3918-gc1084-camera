#!/bin/sh
# Answer "what is this camera, and what is it running?" in one command.
# Runs ON THE CAMERA, over telnet or dropbear:
#
#   /mnt/anyka_hack/identity/whoami.sh            human-readable
#   /mnt/anyka_hack/identity/whoami.sh --json     one flat blob, for enumerators
#
#   unit   comes from flash and belongs to the CAMERA (survives a card swap)
#   build  comes from the card and belongs to the ARTEFACT (follows the card)
#   fw     comes from /usr/fw_version and belongs to the FLASH (read LIVE)
#
# THREE VERSION FACTS, AND WHY NOTHING IN --json IS CALLED "version"
# -----------------------------------------------------------------
# The vendor's fw_version describes what is in flash. The card build stamp
# describes which commit of this repo wrote the SD card. The unit name describes
# the physical camera. They change at different times for different reasons, and
# a reader that collapses them into one field called "version" is wrong about
# two of the three. So --json emits fw_version / card_build / unit_name and
# nothing bare. (build.json itself keeps sigil's own field names, because there
# the surrounding "kind": "build" makes them unambiguous.)
#
# fw_version is read LIVE on every invocation and never cached into a marker.
# The markers are written once and the flash can change underneath them, so a
# marker carrying a firmware version would report a stale one with total
# confidence - this project's signature failure mode.
#
# READING THIS COSTS NO TOKEN, and that is load-bearing
# ----------------------------------------------------
# /tmp/token.txt is the WEB UI's session token and the camera holds exactly one:
# minting a new one silently invalidates every other session, which has already
# flipped an HA switch off in production (docs/home-assistant.md:113-116).
#
# A telnet or dropbear login never touches that file, so a fleet sweep over this
# script cannot reproduce that. Routing identity through a `ctl` verb would NOT
# be equivalent: ctl VALIDATES /tmp/token.txt, so an enumerator would first have
# to log in to obtain one - which is exactly the minting that breaks HA. This
# also never touches port 3000, where a bare TCP connect kills the snapshot
# server.
#
# See docs/identity.md for the unauthenticated-HTTP option deliberately NOT
# taken, and why that is a policy call rather than a technical one.

R="${IDENTITY_TEST_ROOT:-}"
UNIT="$R/data/unit.json"                # mtd7 - update.sh never targets slot D
UNIT_LEGACY="$R/etc/jffs2/unit.json"    # mtd6 = updater slot C - an update erases it
BUILD="$R/mnt/anyka_hack/build.json"
FW="$R/usr/fw_version"

JSON=0
[ "${1:-}" = "--json" ] && JSON=1

field() { sed -n 's/.*"'"$2"'": *"\([^"]*\)".*/\1/p' "$1" 2>/dev/null | head -1; }
bool()  { sed -n 's/.*"'"$2"'": *\([a-z]*\).*/\1/p' "$1" 2>/dev/null | head -1; }

u="$UNIT"
[ -f "$u" ] || u="$UNIT_LEGACY"
fw=""
[ -r "$FW" ] && fw=$(head -1 "$FW" 2>/dev/null | tr -d '\r')

if [ "$JSON" -eq 1 ]; then
  # Every key is ALWAYS present, null when unknown. An enumerator must never
  # have to tell "absent" from "unknown" - that distinction is where inventories
  # start guessing.
  s() {  # quoted string, or null
    if [ -n "$2" ]; then printf '  "%s": "%s",\n' "$1" "$2"
    else printf '  "%s": null,\n' "$1"; fi
  }
  b() {  # bare boolean, or null
    case "$2" in true|false) printf '  "%s": %s,\n' "$1" "$2" ;;
                 *)          printf '  "%s": null,\n' "$1" ;; esac
  }
  echo '{'
  s unit_name   "$(field "$u" name)"
  s unit_short  "$(field "$u" short)"
  s unit_mac    "$(field "$u" mac)"
  s unit_source "$(field "$u" source)"
  s unit_store  "$(field "$u" store)"
  s unit_named  "$(field "$u" named)"
  s card_build  "$(field "$BUILD" version)"
  s card_hash   "$(field "$BUILD" hash)"
  s card_branch "$(field "$BUILD" branch)"
  b card_dirty  "$(bool  "$BUILD" dirty)"
  s card_built  "$(field "$BUILD" built)"
  b card_stock  "$(bool  "$BUILD" stock)"
  s fw_version  "$fw"
  # read_at is LAST so it carries no trailing comma, and it is stamped live so a
  # caller can tell a fresh read from a cached one. 1970 means NTP never synced:
  # report it, do not hide it.
  printf '  "read_at": "%s"\n' "$(date -u +%Y-%m-%dT%H:%M:%SZ 2>/dev/null)"
  echo '}'
  exit 0
fi

echo "unit:"
if [ -f "$u" ]; then
  echo "  name   $(field "$u" name)"
  echo "  mac    $(field "$u" mac)"
  echo "  named  $(field "$u" named)   (source: $(field "$u" source), store: $u)"
  [ "$u" = "$UNIT_LEGACY" ] && echo "  NOTE   this marker is on mtd6, which a firmware update ERASES."
else
  echo "  UNNAMED - no marker in $UNIT or $UNIT_LEGACY."
  echo "  Either this camera has never completed a boot with an identity-aware"
  echo "  card, or naming was skipped because no MAC appeared. Check the boot"
  echo "  console for lines starting 'identity:'."
fi

echo "build:"
if [ -f "$BUILD" ]; then
  echo "  version  $(field "$BUILD" version)"
  echo "  hash     $(field "$BUILD" hash)  branch $(field "$BUILD" branch)  dirty $(bool "$BUILD" dirty)"
  echo "  built    $(field "$BUILD" built)"
  echo "  writer   $(field "$BUILD" writer_host)"
  # Two states that are NOT "behind" - they are UNIDENTIFIABLE, which is a
  # different problem with a different fix (rewrite from a clean commit).
  # Called out because "dev" is a sentinel that reads like a value, and a human
  # scanning this output will not necessarily register the difference.
  [ "$(field "$BUILD" hash)" = "dev" ] && \
    echo "  !!       hash is \"dev\" - a SENTINEL, not a version. git could not identify" && \
    echo "           the checkout when this card was written, so this card cannot tell" && \
    echo "           you which commit produced it. Rewrite from a clean checkout."
  [ "$(bool "$BUILD" dirty)" = "true" ] && \
    echo "  !!       dirty=true - the working tree had uncommitted changes, so the hash" && \
    echo "           above does NOT fully describe what is on this card."
  [ "$(bool "$BUILD" stock)" = "true" ] && \
    echo "  !!       stock=true - written with --stock. This card carries NONE of the" && \
    echo "           project fixes, and no identity toolkit either."
else
  echo "  UNKNOWN - no $BUILD."
  echo "  This card was written before build stamping existed, or by --stock."
fi

echo "firmware:"
if [ -n "$fw" ]; then
  echo "  fw_version  $fw   (read LIVE from /usr/fw_version, never from a marker)"
else
  echo "  UNKNOWN - $FW is missing or unreadable."
fi

# The timestamps are only as good as the clock that made them. This camera has
# no RTC: if NTP has not synced, date reports 1970. A 1970 'named' means the
# marker was written on a boot with no working time_source - which is itself
# worth knowing, so it is reported rather than hidden.
echo "clock:"
echo "  now      $(date -u +%Y-%m-%dT%H:%M:%SZ 2>/dev/null)  (1970 = NTP never synced; see docs/troubleshooting.md)"
