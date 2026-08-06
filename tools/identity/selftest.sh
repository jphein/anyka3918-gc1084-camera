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


# --- 6b. --json is the enumerator's contract. Every key ALWAYS present, null
#         when unknown, and fw_version read LIVE rather than from a marker.
mkdir -p "$r/usr"; printf '6.0.24.10_202401091113\n' > "$r/usr/fw_version"
j="$(IDENTITY_TEST_ROOT="$r" $SH "$r/mnt/anyka_hack/identity/whoami.sh" --json 2>&1)"
printf '%s' "$j" | python3 -m json.tool >/dev/null 2>&1 \
  && ok "--json emits valid JSON" || bad "--json is not valid JSON: $j"
missing="$(printf '%s' "$j" | python3 -c '
import json,sys
want = ["unit_name","unit_short","unit_mac","unit_source","unit_store","unit_named",
        "card_build","card_hash","card_branch","card_dirty","card_built","card_stock",
        "fw_version","read_at"]
d = json.load(sys.stdin)
print(" ".join([k for k in want if k not in d] + [k for k in d if k not in want]))' 2>&1)"
[ -z "$missing" ] && ok "--json carries exactly the 14 agreed keys" \
                  || bad "--json key mismatch: $missing"
printf '%s' "$j" | grep -q '"fw_version": "6.0.24.10_202401091113"' \
  && ok "--json reads fw_version LIVE from /usr/fw_version" \
  || bad "--json did not pick up the live fw_version"
printf '%s' "$j" | grep -q '"card_dirty": false' \
  && ok "--json emits card_dirty as a bare boolean, not a string" \
  || bad "card_dirty is not a bare boolean: $j"
printf '%s' "$j" | grep -qi '"version":' \
  && bad "--json contains a bare 'version' key - ambiguous across three concepts" \
  || ok "--json has no bare 'version' key (three version facts stay distinct)"

# unknowns must be null, never absent - the enumerator must not have to tell
# "this camera has no card marker" from "I forgot to emit the key".
rm -f "$r/mnt/anyka_hack/build.json" "$r/usr/fw_version"
j2="$(IDENTITY_TEST_ROOT="$r" $SH "$r/mnt/anyka_hack/identity/whoami.sh" --json 2>&1)"
printf '%s' "$j2" | python3 -c '
import json,sys
d = json.load(sys.stdin)
assert d["card_build"] is None and d["card_dirty"] is None and d["fw_version"] is None, d
assert d["unit_name"], d
' 2>/dev/null && ok "--json nulls unknown fields instead of dropping them" \
             || bad "--json dropped keys when the build marker was absent: $j2"

# UNIDENTIFIABLE is not the same as BEHIND, and needs a different fix. "dev"
# is a sentinel that reads like a value, so it must be called out, not printed.
cat > "$r/mnt/anyka_hack/build.json" <<'EOF'
{
  "version": "unknown", "hash": "dev", "branch": "unknown",
  "dirty": true, "stock": true, "built": "2026-08-06T00:00:00Z"
}
EOF
out="$(IDENTITY_TEST_ROOT="$r" $SH "$r/mnt/anyka_hack/identity/whoami.sh" 2>&1)"
case "$out" in *"SENTINEL, not a version"*) ok "whoami.sh calls out hash=dev as unidentifiable" ;;
               *) bad "whoami.sh printed hash=dev without comment: $out" ;; esac
case "$out" in *"dirty=true"*) ok "whoami.sh calls out a dirty build" ;;
               *) bad "whoami.sh did not flag dirty=true: $out" ;; esac
case "$out" in *"NONE of the"*) ok "whoami.sh calls out a --stock card" ;;
               *) bad "whoami.sh did not flag stock=true: $out" ;; esac
rm -rf "$r"

# --- 7. a LEGACY marker is MIGRATED to /data, verbatim, never re-derived.
#        Re-deriving would silently rename any camera carrying an override -
#        the exact failure migration exists to prevent. The name below is
#        deliberately NOT the one this MAC derives to, so a re-derivation
#        cannot pass this test by coincidence.
r="$(mkroot 3c:6a:9d:4f:2a:91)"
mkdir -p "$r/etc/jffs2"
printf '{\n  "name": "Front Door",\n  "source": "override",\n  "store": "/etc/jffs2"\n}\n' \
  > "$r/etc/jffs2/unit.json"
out="$(run "$r")"
[ "$(name "$r/data/unit.json")" = "Front Door" ] \
  && ok "legacy marker migrated to /data with the name copied VERBATIM" \
  || bad "migration lost or changed the name: got '$(name "$r/data/unit.json")'"
[ ! -f "$r/etc/jffs2/unit.json" ] \
  && ok "the mtd6 copy is removed after the /data copy is in place" \
  || bad "left a second marker on mtd6 - two sources of truth"
grep -q '"store": "/data"' "$r/data/unit.json" \
  && ok "migration rewrites the store field" || bad "store field still says /etc/jffs2"
grep -q '"source": "override"' "$r/data/unit.json" \
  && ok "migration preserves source=override (the case that cannot self-heal)" \
  || bad "migration dropped the source field"
case "$out" in *MIGRATED*) ok "migration is logged" ;;
               *) bad "migration was silent: $out" ;; esac
# and it must be idempotent - a second boot must not re-migrate or rename
out2="$(run "$r")"
[ "$(name "$r/data/unit.json")" = "Front Door" ] \
  && ok "second boot after migration leaves the name alone" \
  || bad "renamed after migration: $(name "$r/data/unit.json")"
rm -rf "$r"

# --- 7b. no /data: a legacy marker stays put, and is warned about
r="$(mkroot 3c:6a:9d:4f:2a:91)"; rmdir "$r/data"
printf '{\n  "name": "Ashen Vigil · 010203"\n}\n' > "$r/etc/jffs2/unit.json"
out="$(run "$r")"
[ -f "$r/etc/jffs2/unit.json" ] \
  && ok "no /data -> legacy marker left intact rather than destroyed" \
  || bad "removed the only marker with nowhere to put it"
case "$out" in *"ERASES mtd6"*) ok "un-migratable legacy marker is warned about" ;;
               *) bad "silent about an un-migratable legacy marker: $out" ;; esac
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
