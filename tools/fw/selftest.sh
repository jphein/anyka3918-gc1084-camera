#!/usr/bin/env bash
# Prove the firmware tooling without a camera and without writing flash.
#
#   tools/fw/selftest.sh
#
# Builds a synthetic squashfs that stands in for a partition dump, round-trips
# it, and checks the tarball builder's rails. The rails are the point: this
# firmware's updater checks only that an image opens and fits, then reports
# success and reboots, so every guard worth having lives on this side.
#
# special.sh is exercised under busybox ash against a fake tree - it runs as
# root on the camera, before any flash write, and gets one chance.
set -uo pipefail

DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
SH="sh"; command -v busybox >/dev/null 2>&1 && SH="busybox ash"
pass=0; fail=0
ok()  { printf 'ok   %s\n' "$*"; pass=$((pass+1)); }
bad() { printf 'FAIL %s\n' "$*"; fail=$((fail+1)); }

command -v mksquashfs >/dev/null || { echo "SKIP: squashfs-tools not installed"; exit 0; }
W="$(mktemp -d)"; trap 'rm -rf "$W"' EXIT

echo "== round-trip, against a synthetic partition dump =="
mkdir -p "$W/src/bin" "$W/src/share" "$W/src/lib"
printf 'binary\n' > "$W/src/bin/prog";  chmod 755 "$W/src/bin/prog"
printf 'config\n' > "$W/src/share/x.conf"; chmod 644 "$W/src/share/x.conf"
printf '6.0.24.10_202401091113\n' > "$W/src/fw_version"
ln -s /bin/prog "$W/src/bin/alias"
mksquashfs "$W/src" "$W/fs.sqsh4" -b 131072 -comp xz -Xdict-size 100% -no-progress >/dev/null 2>&1
# a real dump is the whole partition: filesystem plus erase padding
cp "$W/fs.sqsh4" "$W/dump.bin"
truncate -s 3100672 "$W/dump.bin"

out="$("$DIR/roundtrip-squashfs.sh" --dump "$W/dump.bin" --slot B --out "$W/usr.sqsh4" 2>&1)"
rc=$?
[ $rc -eq 0 ] && ok "round-trip passes on a padded partition dump" \
              || bad "round-trip failed on a valid dump: $out"
case "$out" in *DETERMINISTIC*) ok "determinism is asserted, not assumed" ;;
               *) bad "no determinism check ran: $out" ;; esac
case "$out" in *"fits slot B"*) ok "size is checked against the real slot size" ;;
               *) bad "no size check: $out" ;; esac
case "$out" in *"modes, types, sizes and symlink targets all preserved"*)
                 ok "metadata equivalence checked (a /usr that lost +x mounts and boots to nothing)" ;;
               *) bad "no metadata check: $out" ;; esac
[ -f "$W/usr.sqsh4" ] && ok "writes an image only when every check passed" \
                      || bad "no image produced"

# The exec bit is the one that would silently ruin a rebuild, so prove the
# check can actually fail rather than trusting that it would.
mkdir -p "$W/broken"; cp -a "$W/src/." "$W/broken/"; chmod 644 "$W/broken/bin/prog"
mksquashfs "$W/broken" "$W/broken.sqsh4" -b 131072 -comp xz -Xdict-size 100% -no-progress >/dev/null 2>&1
o1="$(unsquashfs -d "$W/u1" "$W/fs.sqsh4" >/dev/null 2>&1; cd "$W/u1" && find . -printf '%m %p\n' | sort | md5sum)"
o2="$(unsquashfs -d "$W/u2" "$W/broken.sqsh4" >/dev/null 2>&1; cd "$W/u2" && find . -printf '%m %p\n' | sort | md5sum)"
[ "$o1" != "$o2" ] && ok "the metadata fingerprint distinguishes a lost exec bit" \
                   || bad "metadata fingerprint cannot see a mode change - the check is blind"

echo
echo "== tarball rails =="
FW=6.0.24.11_209901010000
run() { "$DIR/build-update-tar.sh" "$@" 2>&1; }

out="$(run --out "$W/t1.tar" --fw-version "$FW" --special "$DIR/special.sh")"
[ -f "$W/t1.tar" ] && ok "builds a zero-write tarball (fw_version + special.sh)" \
                   || bad "could not build the special.sh-only tarball: $out"
case "$out" in *"NO PARTITION IS FLASHED"*) ok "says plainly that it erases nothing" ;;
               *) bad "did not state the zero-write property: $out" ;; esac
case "$out" in *"RECOVERY IS PULLING THE CARD"*) ok "states the reboot-loop recovery up front" ;;
               *) bad "reboot-loop recovery not stated: $out" ;; esac
tar -tf "$W/t1.tar" | sort | tr '\n' ' ' | grep -q "fw_version special.sh" \
  && ok "tarball contains exactly fw_version + special.sh" \
  || bad "unexpected members: $(tar -tf "$W/t1.tar" | tr '\n' ' ')"
m=$(tar -tvf "$W/t1.tar" | grep special.sh | cut -c1-10)
case "$m" in -rwxr-xr-x) ok "special.sh keeps its exec bit through tar ($m)" ;;
             *) bad "special.sh mode is $m - update.sh runs it as \$DIR1/special.sh" ;; esac

# determinism: a build artefact that changes when nothing changed cannot be diffed
run --out "$W/t2.tar" --fw-version "$FW" --special "$DIR/special.sh" >/dev/null
cmp -s "$W/t1.tar" "$W/t2.tar" && ok "tarball build is deterministic" \
                               || bad "two identical invocations produced different tarballs"

# RAIL: an equal fw_version is a silent no-op on the device
if run --out "$W/t3.tar" --fw-version 6.0.24.10_202401091113 --special "$DIR/special.sh" >/dev/null 2>&1; then
  bad "accepted a fw_version equal to the installed one - a silent no-op on the camera"
else
  ok "refuses a fw_version equal to the installed one (indistinguishable from 'not found')"
fi

# RAIL: fw_version alone would reboot-loop forever with nothing to show for it
if run --out "$W/t4.tar" --fw-version "$FW" >/dev/null 2>&1; then
  bad "built a tarball containing only fw_version - flashes nothing, runs nothing, reboots forever"
else
  ok "refuses a tarball that would only reboot-loop"
fi

# RAIL: usr.jffs2 must be unreachable - not gated, ABSENT
grep -q -- "--usr-jffs2\|usr\.jffs2\"" "$DIR/build-update-tar.sh" \
  && bad "build-update-tar.sh has a path to producing usr.jffs2" \
  || ok "no flag, path or escape can put usr.jffs2 in a tarball (slot C is the whole hack)"
if run --out "$W/t5.tar" --fw-version "$FW" --usr-jffs2 /etc/hostname >/dev/null 2>&1; then
  bad "--usr-jffs2 was accepted"
else
  ok "--usr-jffs2 is not a recognised option"
fi

# RAIL: oversized images are caught here, not on a booting camera
head -c 4000000 /dev/zero > "$W/toobig.sqsh4"
if run --out "$W/t6.tar" --fw-version "$FW" --usr-sqsh4 "$W/toobig.sqsh4" >/dev/null 2>&1; then
  bad "accepted a 4 MB image for a 3.02 MB slot"
else
  ok "refuses an image larger than its slot (before a card is ever written)"
fi

# and a real image is accepted, so the size rail cannot be passing by refusing everything
out="$(run --out "$W/t7.tar" --fw-version "$FW" --usr-sqsh4 "$W/usr.sqsh4" --special "$DIR/special.sh")"
[ -f "$W/t7.tar" ] && ok "accepts a correctly-sized usr.sqsh4" || bad "rejected a valid image: $out"
case "$out" in *"THIS TARBALL WRITES FLASH"*) ok "warns loudly once a partition image is included" ;;
               *) bad "no flash warning on a tarball that flashes: $out" ;; esac
tar -tf "$W/t7.tar" | grep -q "usr.sqsh4.md5" && ok "ships an md5 alongside each image" \
                                              || bad "no md5 member"

echo
echo "== special.sh, under $SH =="
R="$W/root"; mkdir -p "$R/mnt/update" "$R/etc/jffs2" "$R/data" "$R/tmp" "$R/usr"
printf 'isp config\n' > "$R/mnt/isp_gc1084.conf"
printf 'isp config h63\n' > "$R/mnt/isp_h63.conf"
printf 'tarball\n' > "$R/mnt/update/update.tar"
printf '6.0.24.10_202401091113\n' > "$R/usr/fw_version"
printf '6.0.24.11_209901010000\n' > "$R/tmp/fw_version"
# update_ispconfig has already deleted the symlinks by the time special.sh runs
out="$(FW_TEST_ROOT="$R" $SH "$DIR/special.sh" 2>&1)"
ls "$R/etc/jffs2/" | grep -q "isp_gc1084.conf" \
  && ok "special.sh restores the isp symlink update_ispconfig deleted" \
  || bad "isp symlink not restored: $out"
ls "$R/etc/jffs2/" | grep -q "isp_h63.conf" \
  && ok "restores EVERY isp_*.conf on the card, not a hardcoded gc1084 (the bag is not one sensor)" \
  || bad "only handled one sensor: $(ls "$R/etc/jffs2/")"
[ ! -e "$R/mnt/update/update.tar" ] \
  && ok "self-disarms - removes the tarball so the camera does not reboot-loop" \
  || bad "did not disarm: the camera would reboot-loop until the card is pulled"
[ -f "$R/data/fw-update.log" ] && ok "leaves evidence in /data (mtd7, never flashed by update.sh)" \
                               || bad "no evidence written"
# it must be safe to run twice: power can be cut between the repair and the disarm
out2="$(FW_TEST_ROOT="$R" $SH "$DIR/special.sh" 2>&1)"
[ $? -eq 0 ] && ok "second run is harmless (power can be cut before the disarm)" \
             || bad "not idempotent: $out2"

echo
echo "$pass passed, $fail failed"
[ "$fail" -eq 0 ] || exit 1
