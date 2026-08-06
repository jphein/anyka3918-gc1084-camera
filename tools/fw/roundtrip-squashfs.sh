#!/usr/bin/env bash
# Round-trip a squashfs partition dump through our own build pipeline and prove
# the result before anything is flashed.
#
#   tools/fw/roundtrip-squashfs.sh --dump mtdblock5.bin [--slot B] [--out usr.sqsh4]
#   tools/fw/roundtrip-squashfs.sh --dump mtdblock5.bin --add-file PATH:DEST
#
# READS A FILE. WRITES A FILE. Touches no device.
#
# WHY: the point of a first flash is to test the PIPELINE, not the payload. So
# the payload should be the thing already on the device. If our rebuild of the
# camera's own /usr boots, the pipeline works; if it doesn't, we learn that from
# a partition whose contents we did not change.
#
# ⚠️ THE CLAIM THIS TOOL MAKES IS NOT "BYTE-IDENTICAL TO THE VENDOR IMAGE".
#
# I proposed that phrasing and it was wrong. The vendor built their image with a
# different (older) mksquashfs, so inode ordering, padding and compression
# details will differ from ours no matter how careful we are. Demanding byte
# equality would fail for a reason that does not matter, and - worse - would
# tempt someone to tweak flags until it passed, which proves nothing about the
# filesystem.
#
# The two properties that DO matter, and that this asserts:
#
#   1. CONTENT EQUIVALENCE. Unpack the dump, rebuild, unpack the rebuild, and
#      assert the two trees are identical - every file, mode, symlink target and
#      size. This is what "we did not change /usr" actually means.
#
#   2. DETERMINISM. Build twice from the same tree and assert identical bytes.
#      Without this, "the image I tested" and "the image I flashed" are two
#      different artefacts that merely came from the same command.
#
# Byte-identity to the vendor dump is reported when it happens, as a bonus
# signal. It is never required, and it is never the reason to proceed.
set -euo pipefail

die()  { printf 'error: %s\n' "$*" >&2; exit 1; }
ok()   { printf 'ok   %s\n' "$*"; }
bad()  { printf 'FAIL %s\n' "$*"; FAILED=1; }
FAILED=0

# Slot sizes from /proc/mtd on the live camera.
SZ_A=1048576          # 0x100000  mtd4 A -> /
SZ_B=3100672          # 0x2f5000  mtd5 B -> /usr

# The parameters upstream used for a rootfs this kernel actually mounted.
# Family-level evidence (upstream's board is a different build), so treat a
# successful mount on OUR camera as the thing that promotes it to measured.
MKSQ_ARGS=(-b 131072 -comp xz -Xdict-size 100% -no-progress -noappend)

DUMP=""; SLOT="B"; OUT=""; ADD=()
while [ $# -gt 0 ]; do
  case "$1" in
    --dump)     DUMP="${2:-}"; shift 2 ;;
    --slot)     SLOT="${2:-}"; shift 2 ;;
    --out)      OUT="${2:-}"; shift 2 ;;
    --add-file) ADD+=("${2:-}"); shift 2 ;;
    *) die "unknown option: $1" ;;
  esac
done

[ -n "$DUMP" ] || die "--dump is required (a copy of /dev/mtdblock5, taken read-only on the camera)"
[ -f "$DUMP" ] || die "dump not found: $DUMP"
command -v unsquashfs >/dev/null || die "unsquashfs not found (apt install squashfs-tools)"
command -v mksquashfs >/dev/null || die "mksquashfs not found (apt install squashfs-tools)"

case "$SLOT" in
  A) MAX="$SZ_A"; DEFAULT_OUT="root.sqsh4" ;;
  B) MAX="$SZ_B"; DEFAULT_OUT="usr.sqsh4" ;;
  C|D) die "slot $SLOT is forbidden. C is /etc/jffs2 (the whole hack, both passwords,
  the WiFi config). D is /data (unit identity, fleet-wide). Neither is a squashfs
  and neither is ever a target." ;;
  *) die "unknown slot: $SLOT" ;;
esac
OUT="${OUT:-$DEFAULT_OUT}"

WORK="$(mktemp -d)"
trap 'rm -rf "$WORK"' EXIT

echo "== 1. unpack the device's own image =="
# A raw mtd dump is the partition, not the filesystem: squashfs ends where its
# superblock says it does and the rest is erase padding. unsquashfs reads the
# superblock, so it is unbothered - but the trailing bytes are exactly why a
# naive `cmp dump rebuild` would fail even on a perfect rebuild.
unsquashfs -d "$WORK/orig" "$DUMP" >/dev/null 2>&1 \
  || die "unsquashfs could not read $DUMP.
  If this is a raw partition dump, that is still expected to work - squashfs is
  self-delimiting. Failure here means the dump is truncated or not a squashfs."
SQ_BYTES=$(unsquashfs -s "$DUMP" 2>/dev/null | sed -n 's/^Filesystem size \([0-9]*\) bytes.*/\1/p' | head -1)
ok "unpacked $(find "$WORK/orig" | wc -l) entries; filesystem is ${SQ_BYTES:-unknown} bytes of a $(stat -c%s "$DUMP")-byte dump"
unsquashfs -s "$DUMP" 2>/dev/null | sed -n '1,12p' | sed 's/^/     /'

echo
echo "== 2. optional additions =="
if [ "${#ADD[@]}" -eq 0 ]; then
  echo "     none - this is a pure round-trip, contents unchanged"
else
  for spec in "${ADD[@]}"; do
    src="${spec%%:*}"; dest="${spec#*:}"
    [ -f "$src" ] || die "--add-file source not found: $src"
    case "$dest" in /*) die "--add-file destination must be relative to the partition root: $dest" ;; esac
    mkdir -p "$WORK/orig/$(dirname "$dest")"
    cp "$src" "$WORK/orig/$dest"
    ok "added $dest ($(stat -c%s "$src") bytes)"
  done
fi

echo
echo "== 3. rebuild through our pipeline, twice =="
mksquashfs "$WORK/orig" "$WORK/build1.sqsh4" "${MKSQ_ARGS[@]}" >/dev/null
mksquashfs "$WORK/orig" "$WORK/build2.sqsh4" "${MKSQ_ARGS[@]}" >/dev/null
B1=$(md5sum "$WORK/build1.sqsh4" | cut -d' ' -f1)
B2=$(md5sum "$WORK/build2.sqsh4" | cut -d' ' -f1)
if [ "$B1" = "$B2" ]; then
  ok "DETERMINISTIC - two builds from the same tree are byte-identical ($B1)"
else
  bad "NOT deterministic: $B1 vs $B2.
  Without this, the image you tested and the image you flash are two different
  artefacts that merely came from the same command."
fi

SZ=$(stat -c%s "$WORK/build1.sqsh4")
if [ "$SZ" -le "$MAX" ]; then
  ok "fits slot $SLOT: $SZ of $MAX bytes ($(( SZ * 100 / MAX ))% full, $(( MAX - SZ )) spare)"
else
  bad "does NOT fit slot $SLOT: $SZ > $MAX. The device would reject this before
  erasing - the one safety property in that pipeline that works - but only after
  you had written a card and booted it."
fi

echo
echo "== 4. content equivalence - the property that actually matters =="
unsquashfs -d "$WORK/rebuilt" "$WORK/build1.sqsh4" >/dev/null 2>&1 \
  || bad "could not unpack our own rebuild"
if diff -r --no-dereference "$WORK/orig" "$WORK/rebuilt" >"$WORK/diff.txt" 2>&1; then
  ok "rebuild unpacks to a tree identical to the input (contents, symlinks)"
else
  bad "round-trip changed the tree:"; sed 's/^/     /' "$WORK/diff.txt" | head -20
fi
# diff -r does not compare modes, and a /usr full of binaries that lost their
# exec bit would mount perfectly and boot to nothing.
( cd "$WORK/orig"    && find . -printf '%m %y %s %p -> %l\n' | sort ) > "$WORK/m1"
( cd "$WORK/rebuilt" && find . -printf '%m %y %s %p -> %l\n' | sort ) > "$WORK/m2"
if diff -u "$WORK/m1" "$WORK/m2" > "$WORK/mdiff.txt" 2>&1; then
  ok "modes, types, sizes and symlink targets all preserved"
else
  bad "metadata changed in the round-trip:"; sed 's/^/     /' "$WORK/mdiff.txt" | head -20
fi

echo
echo "== 5. superblock equivalence - what the tree comparison CANNOT see =="
#
# Content equivalence proves the FILES match. It says nothing about how they are
# packed, and the vendor kernel mounts the packing, not the tree. A rebuild with
# the wrong block size or a compressor this kernel lacks unpacks to a perfect
# tree and fails to mount - so this is the check that covers the gap between
# "the same files" and "the same filesystem".
#
# Every field except the creation timestamp must match. The timestamp is the one
# thing that SHOULD differ; if it did not, we would be looking at the input.
sb() { unsquashfs -s "$1" 2>/dev/null | grep -v "^Creation or last append time" | tail -n +2; }
if diff -u <(sb "$DUMP") <(sb "$WORK/build1.sqsh4") > "$WORK/sb.txt" 2>&1; then
  ok "superblock matches the vendor's on every field but the timestamp"
  sb "$DUMP" | grep -E "^(Compression|Block size|Number of inodes|Number of fragments)" | sed 's/^/     /'
else
  bad "superblock differs from the vendor image - the tree may match while the
  filesystem does not. THIS IS THE ONE THAT STOPS IT MOUNTING:"
  sed 's/^/     /' "$WORK/sb.txt" | head -20
fi

echo
echo "== 6. byte-identity to the vendor image (BONUS - never required) =="
# Compare PAYLOAD TO PAYLOAD. An earlier version compared the vendor's payload
# against our WHOLE file, which is longer - mksquashfs pads its output up to a
# 4 KB boundary while a raw dump carries the partition's erase padding instead.
# That check would have reported "differs" on length alone even for a perfect
# rebuild: the right verdict for the wrong reason, which is the failure mode
# this whole tool exists to avoid.
if [ -n "$SQ_BYTES" ] \
   && cmp -s <(head -c "$SQ_BYTES" "$DUMP") <(head -c "$SQ_BYTES" "$WORK/build1.sqsh4"); then
  ok "our rebuild is byte-identical to the vendor's filesystem. Strong signal,"
  echo "     but not the reason to proceed - see the header."
else
  n=$(cmp -l <(head -c "$SQ_BYTES" "$DUMP") <(head -c "$SQ_BYTES" "$WORK/build1.sqsh4") 2>/dev/null | wc -l)
  echo "info the rebuild differs from the vendor bytes in $n of $SQ_BYTES payload"
  echo "     bytes. EXPECTED and fine: they built with a different mksquashfs, so"
  echo "     the xz encoder output differs throughout. Content and superblock"
  echo "     equivalence above are the claims. Do NOT tune flags to force this to"
  echo "     pass - a test that can be made green by fiddling is not a test, it is"
  echo "     a target."
fi

echo
if [ "$FAILED" -eq 0 ]; then
  cp "$WORK/build1.sqsh4" "$OUT"
  echo "ALL CHECKS PASSED -> $OUT  ($(stat -c%s "$OUT") bytes, md5 $B1)"
  echo
  echo "This image is NOT armed. It becomes a flash when it is passed to"
  echo "build-update-tar.sh --usr-sqsh4 and the result is put on a card."
  echo "Do not do that without a serial console on the target unit."
else
  echo "SOMETHING FAILED - no image written."
  exit 1
fi
