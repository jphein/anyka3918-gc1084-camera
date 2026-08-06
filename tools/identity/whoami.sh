#!/bin/sh
# Answer "what is this camera, and what is it running?" in one command.
# Runs ON THE CAMERA, over telnet or dropbear:
#
#   /mnt/anyka_hack/identity/whoami.sh
#
# Reads the two markers and prints them side by side. It does NOT compute
# anything - if a field is missing here, it is missing on the device, and that
# is the fact worth seeing.
#
#   unit   comes from flash and belongs to the CAMERA (survives a card swap)
#   build  comes from the card and belongs to the ARTEFACT (follows the card)
#
# There is deliberately no HTTP endpoint for this. Both markers are readable
# with cat, the web UI's post-auth surface already means root on this firmware,
# and adding a pre-auth endpoint to a camera with this project's history is a
# cost with no matching need. See docs/identity.md.

R="${IDENTITY_TEST_ROOT:-}"
UNIT="$R/data/unit.json"                # mtd7 - survives a firmware update
UNIT_LEGACY="$R/etc/jffs2/unit.json"    # mtd6 = updater slot C - an update erases it
BUILD="$R/mnt/anyka_hack/build.json"

field() { sed -n 's/.*"'"$2"'": *"\([^"]*\)".*/\1/p' "$1" 2>/dev/null | head -1; }

u="$UNIT"
[ -f "$u" ] || u="$UNIT_LEGACY"

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
  echo "  hash     $(field "$BUILD" hash)  branch $(field "$BUILD" branch)  dirty $(sed -n 's/.*"dirty": *\([a-z]*\).*/\1/p' "$BUILD" | head -1)"
  echo "  built    $(field "$BUILD" built)"
  echo "  writer   $(field "$BUILD" writer_host)"
else
  echo "  UNKNOWN - no $BUILD."
  echo "  This card was written before build stamping existed, or by --stock."
fi

# The timestamps are only as good as the clock that made them. This camera has
# no RTC: if NTP has not synced, date reports 1970. A 1970 'named' means the
# marker was written on a boot with no working time_source - which is itself
# worth knowing, so it is reported rather than hidden.
echo "clock:"
echo "  now      $(date -u +%Y-%m-%dT%H:%M:%SZ 2>/dev/null)  (1970 = NTP never synced; see docs/troubleshooting.md)"
