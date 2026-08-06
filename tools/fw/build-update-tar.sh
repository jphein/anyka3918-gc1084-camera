#!/usr/bin/env bash
# Assemble an update.tar for the stock AK3918 updater, with the rails this
# firmware does not have.
#
#   tools/fw/build-update-tar.sh --out update.tar --fw-version 6.0.24.11_...  \
#       [--special tools/fw/special.sh] [--usr-sqsh4 FILE] [--root-sqsh4 FILE] \
#       [--uimage FILE] [--no-md5]
#
# WRITES NOTHING TO ANY DEVICE. It produces a file. Putting that file at
# /mnt/update/update.tar on a card is what arms it.
#
# WHY THIS EXISTS RATHER THAN `tar cf`
# ------------------------------------
# The vendor updater performs exactly TWO checks on a local image: it opens, and
# it fits. No squashfs magic, no header consistency, and md5 only when a .md5
# file happens to be present - the check sits inside `if [ -e ]`. It then
# reports success and reboots, and the device dies later at first read of the
# missing region. There is no point in that pipeline where the truth is told.
#
# So every check worth having has to happen HERE, on a workstation, where being
# wrong costs nothing.
set -euo pipefail

die()  { printf 'error: %s\n' "$*" >&2; exit 1; }
warn() { printf 'WARNING: %s\n' "$*" >&2; }

# Partition sizes, from /proc/mtd on the live camera (reference/usr-sbin/README.md).
# The updater's bounds check is sound and rejects an oversized image BEFORE the
# erase - but it rejects it on the device, after the card is written and the
# camera is booting. Checking here turns that into a build error.
SZ_KERNEL=1572864     # 0x180000  mtd1 KERNEL
SZ_A=1048576          # 0x100000  mtd4 A     -> /        squashfs
SZ_B=3100672          # 0x2f5000  mtd5 B     -> /usr     squashfs

# The version installed on the camera this repo was written against. Only used
# to warn - the TF gate is `tar_ver != dev_ver`, so an EQUAL version silently
# does nothing at all, which looks exactly like a tarball that was never found.
KNOWN_DEV_VER="6.0.24.10_202401091113"

OUT=""; FW_VERSION=""; SPECIAL=""; USR_SQSH=""; ROOT_SQSH=""; UIMAGE=""; DO_MD5=1
while [ $# -gt 0 ]; do
  case "$1" in
    --out)         OUT="${2:-}"; shift 2 ;;
    --fw-version)  FW_VERSION="${2:-}"; shift 2 ;;
    --special)     SPECIAL="${2:-}"; shift 2 ;;
    --usr-sqsh4)   USR_SQSH="${2:-}"; shift 2 ;;
    --root-sqsh4)  ROOT_SQSH="${2:-}"; shift 2 ;;
    --uimage)      UIMAGE="${2:-}"; shift 2 ;;
    --no-md5)      DO_MD5=0; shift ;;
    *) die "unknown option: $1" ;;
  esac
done

[ -n "$OUT" ] || die "--out is required"
[ -n "$FW_VERSION" ] || die "--fw-version is required.

  It is NOT optional on the device either: update.sh reads /tmp/fw_version
  unconditionally at line 271, before any gate. A tarball without it fails
  there, after the camera has already unmounted the card."

# ---------------------------------------------------------------------------
# RAIL 1: usr.jffs2 can never be produced by this tool. Not by a flag, not by a
# path, not by an --i-know-what-im-doing escape.
#
# usr.jffs2 goes to slot C, which is mtd6, which is /etc/jffs2. `C=` is a
# WHOLE-PARTITION erase - erase_info.start = 0, length = mtd_info.size, one
# MEMERASE ioctl over all 64 KB. That partition holds the entire hack: the
# exploit entry point, gergehack.sh, the root password, webui.hash,
# gergesettings.txt, AND anyka_cfg.ini with the WiFi SSID and password.
#
# One write costs telnet, the hack, both passwords and the network config
# together. A camera that comes back with no WiFi credentials and no telnet is
# not debuggable over the network at all - it is a device you have to physically
# retrieve. There is no use case that justifies the flag existing.
# ---------------------------------------------------------------------------

# RAIL 2: refuse a fw_version that would make the tarball a silent no-op.
if [ "$FW_VERSION" = "$KNOWN_DEV_VER" ]; then
  die "--fw-version equals the version this repo last saw installed ($KNOWN_DEV_VER).

  The TF gate is 'tar_ver != dev_ver', so an equal version means update.sh
  exits 1 having done nothing. On the camera that is indistinguishable from a
  tarball that was never found: same silence, same working camera, no clue.
  Pick a different version string."
fi
case "$FW_VERSION" in
  *[!0-9A-Za-z._-]*) die "--fw-version contains characters that will not survive a shell compare: $FW_VERSION" ;;
esac

STAGE="$(mktemp -d)"
trap 'rm -rf "$STAGE"' EXIT

printf '%s\n' "$FW_VERSION" > "$STAGE/fw_version"
MEMBERS=("fw_version")
FLASHES=()

add_image() { # $1 = member name, $2 = source file, $3 = partition size, $4 = slot
  local name="$1" src="$2" max="$3" slot="$4" sz
  [ -f "$src" ] || die "$name source not found: $src"
  sz=$(stat -c%s "$src")
  # The updater's own bounds check is evaluated before the erase and rejects an
  # oversized image untouched - the one safety property in the pipeline that
  # genuinely works. Reproduce it here so the failure is a build error rather
  # than a trip to the camera.
  [ "$sz" -le "$max" ] || die "$name is $sz bytes, larger than slot $slot ($max bytes).
  The device would reject this - 'image file large than mtd partition' - but only
  after you had written a card and booted it."
  cp "$src" "$STAGE/$name"
  MEMBERS+=("$name")
  FLASHES+=("$slot <- $name  ($sz bytes of $max, $(( sz * 100 / max ))% full)")
  if [ "$DO_MD5" -eq 1 ]; then
    # The device checks md5 ONLY when the .md5 is present, and the hash ships
    # inside the artefact it verifies - so this is integrity against a corrupt
    # card, never authenticity. Ship it anyway: corruption is the failure we can
    # actually catch, and it is free.
    ( cd "$STAGE" && md5sum "$name" > "$name.md5" )
    MEMBERS+=("$name.md5")
  fi
}

[ -n "$UIMAGE"    ] && add_image "uImage"     "$UIMAGE"    "$SZ_KERNEL" "KERNEL"
[ -n "$ROOT_SQSH" ] && add_image "root.sqsh4" "$ROOT_SQSH" "$SZ_A"      "A"
[ -n "$USR_SQSH"  ] && add_image "usr.sqsh4"  "$USR_SQSH"  "$SZ_B"      "B"

if [ -n "$SPECIAL" ]; then
  [ -f "$SPECIAL" ] || die "--special not found: $SPECIAL"
  install -m 755 "$SPECIAL" "$STAGE/special.sh"
  MEMBERS+=("special.sh")
fi

[ "${#MEMBERS[@]}" -gt 1 ] || die "this tarball would contain only fw_version.
  It would pass the gate, flash nothing, run nothing, and reboot - forever.
  Pass --special and/or a partition image."

# Deterministic tar: sorted members, fixed owner, mtime from the fw_version
# string's own build, so the same inputs give the same bytes. A build artefact
# that changes when nothing changed cannot be diffed against the last one.
tar --sort=name --owner=0 --group=0 --numeric-owner \
    --mtime="@0" -cf "$OUT" -C "$STAGE" $(printf '%s\n' "${MEMBERS[@]}" | sort)

echo "Built: $OUT  ($(stat -c%s "$OUT") bytes)"
echo "  md5: $(md5sum "$OUT" | cut -d' ' -f1)"
echo
echo "Members:"
printf '  %s\n' $(printf '%s\n' "${MEMBERS[@]}" | sort)
echo
echo "What this does on the camera:"
echo "  1. update.sh finds it, extracts to /tmp, reads fw_version -> $FW_VERSION"
echo "  2. TF gate: '$FW_VERSION' != installed -> proceeds"
echo "  3. update_ispconfig() DELETES /etc/jffs2/isp*.conf   <-- always, unguarded"
if [ -n "$SPECIAL" ]; then
  echo "  4. special.sh runs as root, BEFORE any flash write"
fi
if [ "${#FLASHES[@]}" -eq 0 ]; then
  echo "  5. NO PARTITION IS FLASHED - nothing is erased"
  echo "  6. reboot -f"
  echo
  echo "  >> This is a ZERO-WRITE tarball. Its failure mode is a reboot loop,"
  echo "     because fw_version lives on slot B and cannot change without"
  echo "     flashing it, '#rm -rf /mnt/update' is commented out, and"
  echo "     'reboot -f' is unconditional. RECOVERY IS PULLING THE CARD."
  if [ -n "$SPECIAL" ]; then
    echo "     A self-disarming special.sh avoids the loop; verify yours does."
  fi
else
  echo "  5. FLASHES, in this order, after the watchdog is killed:"
  printf '     %s\n' "${FLASHES[@]}"
  echo "  6. reboot -f"
  echo
  warn "THIS TARBALL WRITES FLASH. The update is in-place, non-atomic, with no"
  warn "A/B slots and no rollback, and the watchdog is killed first. Safe to let"
  warn "finish, fatal to interrupt. Do not arm this without a serial console on"
  warn "the target unit - see docs/firmware-update.md."
fi
echo
echo "Never in this tarball: usr.jffs2 (slot C = /etc/jffs2 = the whole hack,"
echo "both passwords and the WiFi config). This tool cannot produce one."
