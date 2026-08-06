#!/bin/sh
# Deterministic sigil name generation - realm-sigil's algorithm, in POSIX sh.
#
#   sigil-name.sh --realm forge --hash a1b2c3d      -> "Tempered Crucible · a1b2c3d"
#   sigil-name.sh --realm fleet --mac 3c:6a:9d:4f:2a:91
#                                                   -> "Obsidian Aegis · 4f2a91"
#   sigil-name.sh --realm fleet --mac ... --field seed   -> the seed, in hex
#
# THE SAME FILE RUNS IN TWO PLACES, deliberately:
#   * on the workstation, called by tools/write-sd-card.sh to name a BUILD
#   * on the camera, called by name-unit.sh at first boot to name a UNIT
# One file means the two sides cannot drift. Everything here is POSIX sh with
# no bashisms and no external tools beyond sed, so it runs under busybox ash on
# a 400 MHz ARM926 exactly as it does under bash.
#
# Word tables are a PINNED SNAPSHOT of realm-sigil's generated tables. See
# PINNED.md for the commit and why pinning is mandatory rather than tidy.
# Verify the pin with ./verify-pin.sh.
set -eu

DIR="$(dirname "$0")"

REALM=""; HASH=""; MAC=""; FIELD="name"
while [ $# -gt 0 ]; do
  case "$1" in
    --realm) REALM="${2:-}"; shift 2 ;;
    --hash)  HASH="${2:-}";  shift 2 ;;
    --mac)   MAC="${2:-}";   shift 2 ;;
    --field) FIELD="${2:-}"; shift 2 ;;
    *) echo "sigil-name.sh: unknown option: $1" >&2; exit 2 ;;
  esac
done

[ -n "$REALM" ] || { echo "sigil-name.sh: --realm is required" >&2; exit 2; }
ADJ_FILE="$DIR/$REALM.adjectives"
NOUN_FILE="$DIR/$REALM.nouns"
[ -f "$ADJ_FILE" ] && [ -f "$NOUN_FILE" ] || {
  echo "sigil-name.sh: no pinned word tables for realm '$REALM' in $DIR" >&2; exit 2; }

NADJ=$(wc -l < "$ADJ_FILE"); NADJ=$((NADJ))
NNOUN=$(wc -l < "$NOUN_FILE"); NNOUN=$((NNOUN))
[ "$NADJ" -gt 0 ] && [ "$NNOUN" -gt 0 ] || {
  echo "sigil-name.sh: empty word table for realm '$REALM'" >&2; exit 2; }

if [ -n "$MAC" ]; then
  # ---- UNIT IDENTITY: seed from the MAC, with the golden-ratio spread.
  #
  # NOT the raw MAC. MACs in one bag come from one vendor block and are
  # consecutive, often with a stride. With a raw seed the noun index is bits
  # 8-12, which are CONSTANT across any aligned 256-wide MAC window - so a bag
  # whose MACs fall in one such window gets at most 32 distinct names (one noun,
  # 32 adjectives) however many cameras are in it. Measured: 50 cameras at
  # stride 4 collapse onto 8-16 distinct names.
  #
  # (That cap is PER WINDOW, not absolute. Spread far enough apart and raw
  # seeding does recover - 8192 sequential MACs give all 1024 names. It is
  # useless for the case we actually have, which is a bag, not the whole space.)
  #
  # The spread is what smol uses and what lexicon's node-identity design doc
  # proves: 2654435761 is odd, so gcd(G,32)=1 and id -> (id*G) mod 32 is a
  # bijection - it needs only that the inputs are distinct mod 32, and
  # consecutive integers are.
  #
  # Only the low 24 bits are used. The top 24 are the vendor OUI, identical
  # across the whole bag, so they carry no information.
  TOKEN=$(printf '%s' "$MAC" | tr 'A-Z' 'a-z' | sed 's/[^0-9a-f]//g')
  case "$TOKEN" in
    ????????????) : ;;
    *) echo "sigil-name.sh: '$MAC' is not a 12-hex-digit MAC" >&2; exit 2 ;;
  esac
  TOKEN=$(printf '%s' "$TOKEN" | sed 's/^......//')       # low 24 bits, 6 hex digits
  LOW=$((0x$TOKEN))

  # (LOW * 2654435761) mod 2^32, computed exactly in 32-bit arithmetic.
  #
  # The full product reaches ~2^55, which busybox ash CANNOT represent on this
  # 32-bit ARM. It does not have to: only bits 0-4 and 8-12 of the product are
  # ever read, i.e. only (product mod 2^13). Congruence gives that exactly, and
  # 2654435761 mod 8192 = 6577, so the largest intermediate here is
  # 8191 * 6577 = 53,872,207 - comfortably inside 32 bits.
  #
  # This is not an approximation. verify-pin.sh enumerates it against the
  # reference implementation over the whole 24-bit input space.
  #
  # BUT IT IS EXACT ONLY FOR TABLE SIZES THAT DIVIDE THOSE BIT FIELDS, so the
  # precondition is asserted below rather than assumed. Truncating to 13 bits
  # preserves `x % NADJ` only when NADJ divides 8192, and `(x >> 8) % NNOUN`
  # only when NNOUN divides 32. `fleet` is 32 x 32 and satisfies both. `forge`
  # is 14 x 14 and does not - with --mac it would return a plausible name that
  # disagrees with every other sigil implementation, at exit 0. A silent wrong
  # answer from a naming tool is the failure class this whole project spent a
  # day cataloguing, so it refuses instead.
  if [ $(( 8192 % NADJ )) -ne 0 ] || [ $(( 32 % NNOUN )) -ne 0 ]; then
    echo "sigil-name.sh: --mac needs a realm whose adjective count divides 8192" >&2
    echo "  and whose noun count divides 32. Realm '$REALM' is ${NADJ}x${NNOUN}." >&2
    echo "  The 32-bit-safe truncation would silently return a name that" >&2
    echo "  disagrees with Go/Python/JS. Use --hash for this realm, or a" >&2
    echo "  power-of-two-sized realm (fleet is 32x32) for --mac." >&2
    exit 2
  fi
  SEED=$(( ((LOW % 8192) * 6577) % 8192 ))
else
  # ---- BUILD PROVENANCE: sigil used natively, seeded by the git short hash.
  [ -n "$HASH" ] || { echo "sigil-name.sh: --hash or --mac is required" >&2; exit 2; }
  TOKEN=$(printf '%s' "$HASH" | tr 'A-Z' 'a-z' | sed 's/[^0-9a-f]//g')
  if [ -z "$TOKEN" ]; then
    # realm-sigil's own convention for an unknown build.
    printf 'unknown %s\n' "$HASH"
    exit 0
  fi
  # realm-sigil's parseHex consumes the whole string; a git short hash is 7 hex
  # digits (28 bits) and fits. Longer input is truncated to 7 so a full 40-char
  # hash cannot overflow 32-bit arithmetic and silently produce a different name
  # from the one Go/Python/JS would give for the short hash.
  TOKEN=$(printf '%s' "$TOKEN" | cut -c1-7)
  SEED=$((0x$TOKEN))
fi

ADJ_I=$(( SEED % NADJ ))
NOUN_I=$(( (SEED / 256) % NNOUN ))
ADJ=$(sed -n "$((ADJ_I + 1))p" "$ADJ_FILE")
NOUN=$(sed -n "$((NOUN_I + 1))p" "$NOUN_FILE")

case "$FIELD" in
  name)  printf '%s %s \302\267 %s\n' "$ADJ" "$NOUN" "$TOKEN" ;;
  short) printf '%s %s\n' "$ADJ" "$NOUN" ;;
  token) printf '%s\n' "$TOKEN" ;;
  seed)  printf '%x\n' "$SEED" ;;
  *) echo "sigil-name.sh: unknown --field '$FIELD' (name|short|token|seed)" >&2; exit 2 ;;
esac
