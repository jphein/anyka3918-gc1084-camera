#!/usr/bin/env bash
# Exercise the ON-CAMERA naming flow on a workstation, against a fake tree.
#
#   tools/identity/selftest.sh
#
# The camera gets ONE chance to name itself and the result is write-once in
# flash, so "it looked right in review" is not good enough. This builds a fake
# /etc/jffs2 + /data + /sys/class/net + card, runs name-unit.sh under busybox
# ash (the camera's actual shell, not bash), and asserts on the outcome.
#
# It cannot test what only the device has - jffs2 behaviour, the real free-space
# figure, whether wlan0 has appeared by the time the hook runs. Those are called
# out in docs/identity.md as unverified-on-hardware. Everything that is pure
# shell logic is tested here.
set -uo pipefail

DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
SH="sh"; command -v busybox >/dev/null 2>&1 && SH="busybox ash"
pass=0; fail=0
ok()  { printf 'ok   %s\n' "$*"; pass=$((pass+1)); }
bad() { printf 'FAIL %s\n' "$*"; fail=$((fail+1)); }

mkroot() { # $1 = mac ("" for none)
  root="$(mktemp -d)"
  mkdir -p "$root/etc/jffs2" "$root/data" "$root/mnt/anyka_hack/identity" "$root/sys/class/net/lo"
  echo "00:00:00:00:00:00" > "$root/sys/class/net/lo/address"
  if [ -n "$1" ]; then
    mkdir -p "$root/sys/class/net/wlan0"; echo "$1" > "$root/sys/class/net/wlan0/address"
  fi
  for f in sigil-name.sh name-unit.sh whoami.sh fleet.adjectives fleet.nouns; do
    cp "$DIR/$f" "$root/mnt/anyka_hack/identity/$f"
  done
  chmod 755 "$root/mnt/anyka_hack/identity"/*.sh
  printf '%s' "$root"
}
run()  { IDENTITY_TEST_ROOT="$1" IDENTITY_WAIT_MAX="${WAIT:-0}" IDENTITY_WAIT_STEP=1 \
           $SH "$1/mnt/anyka_hack/identity/name-unit.sh" 2>&1; }
name() { sed -n 's/.*"name": *"\([^"]*\)".*/\1/p' "$1" 2>/dev/null | head -1; }

echo "== running under: $SH =="

# --- 1. a camera out of the bag names itself
r="$(mkroot 3c:6a:9d:4f:2a:91)"; out="$(run "$r")"
got="$(name "$r/data/unit.json")"
want="$("$DIR/sigil-name.sh" --realm fleet --mac 3c:6a:9d:4f:2a:91)"
[ "$got" = "$want" ] && ok "self-names from wlan0 MAC -> $got" \
                     || bad "self-naming: got '$got' want '$want' ($out)"
python3 -m json.tool "$r/data/unit.json" >/dev/null 2>&1 \
  && ok "unit.json is valid JSON" || bad "unit.json is not valid JSON"
sz=$(wc -c < "$r/data/unit.json")
[ "$sz" -lt 512 ] && ok "unit.json is ${sz} bytes (small enough even for the mtd6 fallback)" \
                  || bad "unit.json is ${sz} bytes - too big for a 64 KB partition at 88% full"
grep -q '"store": "/data"' "$r/data/unit.json" \
  && ok "lands in /data (mtd7), which the stock updater does not write" \
  || bad "did not land in /data - a firmware update would erase this marker"

# --- 2. write-once: a second run must not rename, even with a different MAC
echo "aa:bb:cc:dd:ee:ff" > "$r/sys/class/net/wlan0/address"
out="$(run "$r")"; got2="$(name "$r/data/unit.json")"
[ "$got2" = "$got" ] && ok "write-once: MAC changed, name did not" \
                     || bad "RENAMED on second run: '$got' -> '$got2'"
case "$out" in *"already named"*) ok "second run says why it did nothing" ;;
               *) bad "second run was silent about skipping: $out" ;; esac
rm -rf "$r"

# --- 3. no MAC -> writes NOTHING, and says so
r="$(mkroot "")"; out="$(WAIT=2 run "$r")"
[ ! -f "$r/data/unit.json" ] && [ ! -f "$r/etc/jffs2/unit.json" ] \
  && ok "no MAC -> no marker written (unnamed beats wrongly named)" \
  || bad "wrote a marker with no MAC available"
case "$out" in *"NOT naming"*) ok "no-MAC case is logged loudly" ;;
               *) bad "no-MAC case was silent: $out" ;; esac
rm -rf "$r"

# --- 4. an all-zero wlan0 is ignored, and a real second interface is found
r="$(mkroot 00:00:00:00:00:00)"
mkdir -p "$r/sys/class/net/eth0"; echo "3c:6a:9d:00:10:04" > "$r/sys/class/net/eth0/address"
run "$r" >/dev/null
got="$(name "$r/data/unit.json")"
want="$("$DIR/sigil-name.sh" --realm fleet --mac 3c:6a:9d:00:10:04)"
[ "$got" = "$want" ] && ok "all-zero MAC skipped, real interface used" \
                     || bad "zero-MAC fallback: got '$got' want '$want'"
rm -rf "$r"

# --- 5. --unit-name override wins, verbatim
r="$(mkroot 3c:6a:9d:4f:2a:91)"
printf 'Front Door\n' > "$r/mnt/anyka_hack/identity/unit-name.override"
run "$r" >/dev/null
[ "$(name "$r/data/unit.json")" = "Front Door" ] \
  && ok "override is used verbatim" || bad "override ignored: $(name "$r/data/unit.json")"
grep -q '"source": "override"' "$r/data/unit.json" \
  && ok "override is recorded as the source" || bad "override not recorded in source field"
grep -q '"mac": "3c:6a:9d:4f:2a:91"' "$r/data/unit.json" \
  && ok "override still records the MAC" || bad "override lost the MAC"
rm -rf "$r"

# --- 6. whoami.sh reads both markers, and is honest when one is missing
r="$(mkroot 3c:6a:9d:4f:2a:91)"; run "$r" >/dev/null
out="$(IDENTITY_TEST_ROOT="$r" $SH "$r/mnt/anyka_hack/identity/whoami.sh" 2>&1)"
case "$out" in *"Arcane Quartz"*) ok "whoami.sh reports the unit name" ;;
               *) bad "whoami.sh did not report the name: $out" ;; esac
case "$out" in *"UNKNOWN"*) ok "whoami.sh says the build is unknown when build.json is absent" ;;
               *) bad "whoami.sh invented a build: $out" ;; esac
cat > "$r/mnt/anyka_hack/build.json" <<'EOF'
{
  "kind": "build",
  "version": "Bellowed Foundry · 4c299ee",
  "hash": "4c299ee",
  "branch": "main",
  "dirty": false,
  "built": "2026-08-06T00:00:00Z",
  "writer_host": "katana"
}
EOF
out="$(IDENTITY_TEST_ROOT="$r" $SH "$r/mnt/anyka_hack/identity/whoami.sh" 2>&1)"
case "$out" in *"Bellowed Foundry"*) ok "whoami.sh reports the build version" ;;
               *) bad "whoami.sh did not report the build: $out" ;; esac
rm -rf "$r"

# --- 7. a marker left in the LEGACY store is honoured, never duplicated.
#        Getting this wrong would rename a camera the day /data became primary.
r="$(mkroot 3c:6a:9d:4f:2a:91)"
mkdir -p "$r/etc/jffs2"
printf '{\n  "name": "Ashen Vigil · 010203"\n}\n' > "$r/etc/jffs2/unit.json"
out="$(run "$r")"
[ ! -f "$r/data/unit.json" ] \
  && ok "legacy marker honoured - no second marker written in /data" \
  || bad "wrote a duplicate marker while a legacy one existed"
case "$out" in *"Ashen Vigil"*) ok "legacy marker's name is reported back" ;;
               *) bad "legacy name not reported: $out" ;; esac
case "$out" in *"firmware update erases"*) ok "legacy store is flagged as update-erasable" ;;
               *) bad "legacy store was not flagged as risky: $out" ;; esac
rm -rf "$r"

# --- 8. no /data at all -> falls back to mtd6, loudly, and still names
r="$(mkroot 3c:6a:9d:4f:2a:91)"; rmdir "$r/data"
out="$(run "$r")"
[ -f "$r/etc/jffs2/unit.json" ] \
  && ok "no /data -> still names the camera, in the fallback store" \
  || bad "no /data -> camera left unnamed: $out"
case "$out" in *WARNING*) ok "the fallback is warned about, not silent" ;;
               *) bad "fell back to mtd6 silently: $out" ;; esac
grep -q '"store": "/etc/jffs2"' "$r/etc/jffs2/unit.json" \
  && ok "marker records which store it landed in" || bad "store field wrong in fallback"
rm -rf "$r"

# --- 9. the fleet-wide property: a bag of consecutive MACs gets distinct names.
#        This is the whole reason for the golden-ratio spread; if it ever
#        regresses, every camera in a batch quietly becomes the same name.
for stride in 1 2 4 8; do
  n=$(for i in $(seq 0 19); do
        printf '3c6a9d%06x\n' $((0x001000 + i*stride))
      done | while read -r m; do "$DIR/sigil-name.sh" --realm fleet --mac "$m" --field short; done \
      | sort -u | wc -l)
  [ "$n" -eq 20 ] && ok "20 cameras at MAC stride $stride -> 20 distinct names" \
                  || bad "20 cameras at MAC stride $stride -> only $n distinct names"
done

echo
echo "$pass passed, $fail failed"
[ "$fail" -eq 0 ] || exit 1
