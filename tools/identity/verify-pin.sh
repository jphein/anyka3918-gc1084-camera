#!/usr/bin/env bash
# Verify the pinned sigil word tables and the POSIX-sh implementation.
#
#   tools/identity/verify-pin.sh [/path/to/realm-sigil]
#
# Run this on a WORKSTATION, never on the camera. It is not part of writing a
# card - the writer must not depend on python3 or on realm-sigil being checked
# out. This is the human-run check that the pin is still honest.
#
# Four things are checked, in order of how badly they would bite:
#
#   1. INDEX MATH - the 32-bit-safe congruence in sigil-name.sh is EXHAUSTIVELY
#      equal to the full (low24 * 2654435761) mod 2^32 over all 16,777,216
#      inputs. This is the claim that would be most embarrassing to get wrong
#      and it is cheap to prove, so it is proved rather than argued.
#   2. SHELL PARITY - sigil-name.sh agrees with the reference on a sample, under
#      bash AND under busybox ash if busybox is installed.
#   3. CORPUS PIN - the vendored tables still match realm-sigil's generated
#      tables, and forge names match realm-sigil's own GenerateName.
#   4. INVARIANTS from lexicon's node-identity design doc: fleet is size-locked
#      at 32 x 32, fleet and forge share no word in either position.
#
# A drifted corpus is NOT automatically a failure to fix by re-pinning: changing
# a count renames every camera in the bag. Read PINNED.md before touching it.
set -euo pipefail

DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
SIGIL="${1:-$HOME/Projects/realm-sigil}"
fail=0
note() { printf '  %s\n' "$*"; }
ok()   { printf 'ok   %s\n' "$*"; }
bad()  { printf 'FAIL %s\n' "$*"; fail=1; }

echo "== 1. index math (exhaustive over the 24-bit MAC tail) =="
if python3 - <<'PY'
G = 2654435761
for low in range(1 << 24):
    full = (low * G) & 0xFFFFFFFF
    cheap = ((low % 8192) * (G % 8192)) % 8192
    if (full % 32, (full >> 8) % 32) != (cheap % 32, (cheap >> 8) % 32):
        raise SystemExit(f"MISMATCH at low={low:#08x}")
PY
then ok "((low%8192)*6577)%8192 reproduces bits 0-4 and 8-12 of (low*G) mod 2^32, all 16777216 inputs"
else bad "the 32-bit-safe congruence is NOT equal to the full multiply"
fi

echo
echo "== 2. shell parity (bash, and busybox ash if present) =="
SHELLS=(bash)
command -v busybox >/dev/null 2>&1 && SHELLS+=("busybox ash")
for sh in "${SHELLS[@]}"; do
  mismatch=0
  # edge cases first, then a spread of consecutive and strided MACs - the
  # patterns a real bag of cameras actually produces.
  for mac in 000000000000 ffffffffffff 3c6a9d000000 3c6a9dffffff \
             3c6a9d001000 3c6a9d001001 3c6a9d001004 3c6a9d001008 \
             3c6a9d1fff00 3c6a9d002000 3c6a9d7f3e2a 001122334455; do
    got="$($sh "$DIR/sigil-name.sh" --realm fleet --mac "$mac")"
    want="$(python3 - "$mac" "$DIR" <<'PY'
import sys
mac, d = sys.argv[1], sys.argv[2]
A = open(f"{d}/fleet.adjectives").read().split()
N = open(f"{d}/fleet.nouns").read().split()
low = int(mac[-6:], 16)
seed = (low * 2654435761) & 0xFFFFFFFF
print(f"{A[seed % len(A)]} {N[(seed >> 8) % len(N)]} · {mac[-6:]}")
PY
)"
    [ "$got" = "$want" ] || { bad "$sh fleet $mac: got '$got' want '$want'"; mismatch=1; }
  done
  for h in 4c299ee 0000000 fffffff abcdef1 0000001; do
    got="$($sh "$DIR/sigil-name.sh" --realm forge --hash "$h")"
    want="$(python3 - "$h" "$DIR" <<'PY'
import sys
h, d = sys.argv[1], sys.argv[2]
A = open(f"{d}/forge.adjectives").read().split()
N = open(f"{d}/forge.nouns").read().split()
seed = int(h, 16)
print(f"{A[seed % len(A)]} {N[(seed >> 8) % len(N)]} · {h}")
PY
)"
    [ "$got" = "$want" ] || { bad "$sh forge $h: got '$got' want '$want'"; mismatch=1; }
  done
  [ "$mismatch" -eq 0 ] && ok "$sh matches the reference on every sampled MAC and hash"
done

echo
echo "== 3. corpus pin vs realm-sigil =="
if [ -d "$SIGIL/go" ]; then
  python3 - "$SIGIL" "$DIR" <<'PY' && ok "pinned tables are byte-identical to realm-sigil's generated tables" || bad "PINNED TABLES HAVE DRIFTED - read PINNED.md before re-pinning"
import re, sys
sigil, d = sys.argv[1], sys.argv[2]
s = open(f"{sigil}/go/realms.go").read()
GO = {n: (re.findall(r'"([^"]+)"', a), re.findall(r'"([^"]+)"', x)) for n, a, x in re.findall(
    r'"(\w+)":\s*\{\s*Adjectives:\s*\[\]string\{(.*?)\},\s*Nouns:\s*\[\]string\{(.*?)\},', s, re.S)}
bad = False
for realm in ("fleet", "forge"):
    for kind, idx in (("adjectives", 0), ("nouns", 1)):
        pinned = open(f"{d}/{realm}.{kind}").read().split("\n")[:-1]
        if pinned != GO[realm][idx]:
            print(f"  drift in {realm}.{kind}: pinned {len(pinned)} vs sigil {len(GO[realm][idx])}")
            bad = True
raise SystemExit(1 if bad else 0)
PY
  # sigil's own binding is the arbiter for the build-name path, which uses no
  # deviation from its contract - so it must agree exactly.
  if [ -f "$SIGIL/python/realm_sigil/__init__.py" ]; then
    got="$("$DIR/sigil-name.sh" --realm forge --hash 4c299ee)"
    want="$(PYTHONPATH="$SIGIL/python" python3 -c \
      'import realm_sigil; print(realm_sigil.generate_name("4c299ee","forge"))' 2>/dev/null || true)"
    if [ -z "$want" ]; then note "(realm-sigil python binding not importable - skipped; see sigil issue #7)"
    elif [ "$got" = "$want" ]; then ok "forge build name matches realm-sigil's own generate_name"
    else bad "forge name disagrees with realm-sigil: '$got' vs '$want'"
    fi
  fi
else
  note "(no realm-sigil checkout at $SIGIL - corpus pin not cross-checked)"
fi

echo
echo "== 4. node-identity invariants =="
na=$(wc -l < "$DIR/fleet.adjectives"); nn=$(wc -l < "$DIR/fleet.nouns")
if [ "$na" -eq 32 ] && [ "$nn" -eq 32 ]; then
  ok "fleet is size-locked at 32 x 32 (changing either count renames every camera)"
else
  bad "fleet is ${na} x ${nn}, not 32 x 32 - the size lock is broken"
fi
overlap="$(cat "$DIR"/fleet.adjectives "$DIR"/fleet.nouns | tr 'A-Z' 'a-z' | sort -u > /tmp/.sigil_fleet.$$
           cat "$DIR"/forge.adjectives "$DIR"/forge.nouns | tr 'A-Z' 'a-z' | sort -u > /tmp/.sigil_forge.$$
           comm -12 /tmp/.sigil_fleet.$$ /tmp/.sigil_forge.$$; rm -f /tmp/.sigil_fleet.$$ /tmp/.sigil_forge.$$)"
if [ -z "$overlap" ]; then
  ok "fleet and forge share no word in either position (identity never reads as provenance)"
else
  bad "fleet and forge share: $(echo $overlap)"
fi
trunc="$(for k in 4 5 6 8; do
           n=$(cut -c1-$k "$DIR/fleet.nouns" | tr 'A-Z' 'a-z' | sort -u | wc -l)
           [ "$n" -eq 32 ] || echo "$k"
         done)"
if [ -z "$trunc" ]; then
  ok "fleet nouns stay distinct truncated to 4, 5, 6 and 8 characters"
else
  bad "fleet nouns collide when truncated to: $(echo $trunc) characters"
fi

echo
[ "$fail" -eq 0 ] && echo "ALL CHECKS PASSED" || { echo "SOMETHING FAILED - see above"; exit 1; }
