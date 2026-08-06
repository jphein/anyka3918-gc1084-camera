#!/usr/bin/env bash
# Enumerate the camera fleet: which units exist, what card each is running,
# which are behind, and which cannot answer.
#
#   tools/fleet-status.sh [--hosts FILE] [--expect HASH] [--via CMD] [host ...]
#
# Host list, first match wins:
#   1. hosts on the command line   2. --hosts FILE
#   3. $ANYKA_HOSTS (a file path)  4. tools/hosts.local  (gitignored)
#
# Each host line is "<ip-or-name> [label]"; blanks and # comments skipped.
#
# THIS REPO IS PUBLIC. No host list, IP, SSID or credential is baked in here and
# none should ever be. tools/hosts.local is gitignored so that stays true, and
# --via keeps authentication in your ssh config rather than in this file.
#
# Exit: 0 all current · 1 something behind/unverifiable · 2 something unreachable
#
# ⚠️ UNTESTED AGAINST HARDWARE as of 2026-08-06. Every status below was exercised
#    against fixtures; no camera has run this. docs/identity.md records that the
#    identity work it consumes is likewise verified only under busybox ash in a
#    harness. First real run should be watched, not trusted.
set -uo pipefail   # NOT -e: one dead camera must not abort the sweep

# ---------------------------------------------------------------------------
# Why this script is shaped the way it is. Every point is measured, not
# stylistic, and each says WHY — so a later reader can tell an improvement from
# a regression. Several look like bugs until you know the reason.
#
#  1. NEVER open a bare TCP socket to port 3000. A connect/close without a valid
#     HTTP request KILLS the snapshot server until the camera restarts it. No
#     port scans, no TCP reachability checks. (README.md)
#
#  2. READ OVER A SHELL, NEVER THE WEB UI. The camera holds exactly ONE web
#     session token in /tmp/token.txt, so minting one silently invalidates every
#     other session — that flipped an HA switch off in production
#     (docs/home-assistant.md). telnet and dropbear never touch that file.
#
#     ⚠️ A `ctl?command=identity` verb is NOT the equivalent shortcut it looks
#     like, and this is the trap worth naming: `ctl` *validates* the token, it
#     does not mint one, so an enumerator would have to log in first — which is
#     exactly the minting that breaks HA. `status` and `sounds` only LOOK
#     token-free. Do not "simplify" this into an HTTP call.
#     (docs/identity.md, "Reading identity costs no token")
#
#  3. GO EASY. 400 MHz single-core ARM926, ~36 MB RAM, already doing H.264
#     encode, RTSP, snapshots and CGI. ONE remote command per camera, serial,
#     short timeout. Not cron — run it before a maintenance round, after a card
#     write, and after any flash.
#
#  4. SILENCE IS NEVER "UP TO DATE". A card predating the markers reports
#     nothing; that is UNKNOWN, and UNKNOWN is not CURRENT. Two fixes in this
#     project were nearly lost living only on a live card and were caught by
#     luck. A status column that defaults to CURRENT manufactures exactly that
#     false confidence, at fleet scale.
#
#  5. DO NOT ORDER VENDOR FIRMWARE VERSIONS. The device's own OTA gate
#     (update.sh:277) is `[ "$tar_ver" \> "$dev_ver" ]` — a LEXICOGRAPHIC string
#     compare — and it inverts at the version this fleet runs. Measured in sh,
#     dash and busybox sh against the installed 6.0.24.10_202401091113:
#
#         6.0.24.9  \> 6.0.24.10  -> TRUE   (a downgrade reads as newer)
#         6.0.24.10 \> 6.0.9.1    -> FALSE  (.24 reads as older than .9)
#
#     So "newer" is not decidable here. We print fw verbatim and flag DIVERGENCE
#     across the fleet: actionable, needs no ordering, cannot be wrong. Ordering
#     only means something once a declared target firmware exists, and there is
#     none — do not invent one to make a column sort.
#
#  6. COMPARE card_hash, NEVER card_build. card_build is a realm-sigil NAME:
#     cosmetic, and two names sort any way at all. docs/identity.md says this
#     outright.
#
#  7. UNREACHABLE IS DELIBERATELY COARSE. DO NOT SPLIT IT. Telling "powered off"
#     from "up but silent" needs a SECOND probe of a host that just failed to
#     answer, and per notes 1 and 3 the cheap probes are the ones that break
#     things. Honestly vague beats precisely harmful.
#
#  8. FOUR SEPARATE WAYS A BUILD CAN BE UNTRUSTWORTHY, none of them "behind".
#     Each is its own status because each needs a different action:
#       card_dirty=true  uncommitted tree; the hash does NOT describe the card
#       card_hash="dev"  git could not identify the checkout at write time
#       card_stock=true  a --stock card: NONE of this project's fixes are on it
#       no build marker  written before build stamping, or by an older writer
#
#  9. A UNIT MARKER IN /etc/jffs2 IS LIVE ON A FUSE. That path is mtd6 = updater
#     slot C, and a C= flash is a whole-partition erase. /data (mtd7) is not
#     written by update.sh — though `updater local D=` WOULD reach it, so any
#     update tooling we write must treat D= as forbidden (name-unit.sh carries
#     the same warning next to the thing it protects).
#
# 10. A MISSING NAME IS NOT ALWAYS A LOST NAME. Naming is DERIVED from the MAC
#     and is idempotent: a wiped /data re-derives the SAME name on next boot, so
#     for unit_source="mac" a wipe costs a boot, not an identity. The exception
#     is unit_source="override" (--unit-name), which is not derivable and IS
#     genuinely lost if wiped. Those are the units whose names the catalog must
#     actually back up, so they are called out separately rather than lumped in.
# ---------------------------------------------------------------------------

REPO="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
TIMEOUT=8
HOSTS_FILE=""
EXPECT_HASH=""
VIA=""
declare -a CLI_HOSTS=()

while [ $# -gt 0 ]; do
  case "$1" in
    --hosts)   HOSTS_FILE="${2:-}"; shift 2 ;;
    --expect)  EXPECT_HASH="${2:-}"; shift 2 ;;
    --via)     VIA="${2:-}"; shift 2 ;;
    --timeout) TIMEOUT="${2:-}"; shift 2 ;;
    -h|--help) sed -n '2,22p' "$0"; exit 0 ;;
    -*) echo "unknown option: $1" >&2; exit 22 ;;
    *)  CLI_HOSTS+=("$1"); shift ;;
  esac
done

# The desired build lives in git, not in a catalog (note 6).
[ -n "$EXPECT_HASH" ] || EXPECT_HASH="$(git -C "$REPO" rev-parse --short HEAD 2>/dev/null || true)"

declare -a HOSTS=()
if [ "${#CLI_HOSTS[@]}" -gt 0 ]; then
  HOSTS=("${CLI_HOSTS[@]}")
else
  [ -n "$HOSTS_FILE" ] || HOSTS_FILE="${ANYKA_HOSTS:-$REPO/tools/hosts.local}"
  if [ ! -r "$HOSTS_FILE" ]; then
    cat >&2 <<EOF
no host list. This repo ships without one on purpose — it is public.

Give hosts on the command line, or create $REPO/tools/hosts.local (gitignored):

    # <ip-or-hostname>  <label>
    192.168.1.20        front-door

or point \$ANYKA_HOSTS at a file elsewhere.
EOF
    exit 22
  fi
  while read -r h _; do
    case "$h" in ''|'#'*) continue ;; esac
    HOSTS+=("$h")
  done < "$HOSTS_FILE"
fi

# --- transport -------------------------------------------------------------
# NO CREDENTIALS IN THIS FILE. --via is a command template so authentication
# lives in your ssh config, keys or agent — never in a public repo.
#   --via 'ssh -o BatchMode=yes root@%h %s'
: "${VIA:=ssh -o BatchMode=yes -o StrictHostKeyChecking=accept-new -o ConnectTimeout=$TIMEOUT root@%h %s}"

# whoami.sh --json is the documented enumerator contract: 14 keys, every one
# always present, null when unknown (docs/identity.md). The raw fallback exists
# because a card from the bag predating the identity toolkit has no whoami.sh —
# and an old card is precisely the case an inventory exists to find, so it must
# not be reported as unreachable.
REMOTE_CMD='W=/mnt/anyka_hack/identity/whoami.sh; if [ -f "$W" ]; then sh "$W" --json; else echo @@RAW@@; cat /data/unit.json 2>/dev/null; echo @@SEP@@; cat /etc/jffs2/unit.json 2>/dev/null; echo @@SEP@@; cat /mnt/anyka_hack/build.json 2>/dev/null; echo @@SEP@@; cat /usr/fw_version 2>/dev/null; fi'

read_host() {
  local host="$1" cmd
  cmd="${VIA//%h/$host}"
  cmd="${cmd//%s/$(printf '%q' "$REMOTE_CMD")}"
  timeout "$TIMEOUT" bash -c "$cmd" 2>/dev/null
}

RAW="$(mktemp)"; trap 'rm -f "$RAW"' EXIT
for host in "${HOSTS[@]}"; do
  printf '@@HOST@@%s\n' "$host" >> "$RAW"
  read_host "$host" >> "$RAW" || true
  printf '\n@@END@@\n' >> "$RAW"
done

# --- render ----------------------------------------------------------------
# Parsing happens HERE, on the workstation, with a real JSON parser — never with
# sed. card_dirty and card_stock are UNQUOTED booleans; a regex that treats them
# as strings gets them silently wrong, which is the one failure mode this tool
# exists to prevent.
EXPECT_HASH="$EXPECT_HASH" python3 - "$RAW" <<'PY'
import json, os, sys

expect = os.environ.get("EXPECT_HASH", "")
rows, fws, overrides, worst = [], [], [], 0

def jload(s):
    s = s.strip()
    if not s:
        return None
    try:
        return json.loads(s)
    except Exception:
        return {"__malformed__": True}

def from_raw(body):
    """Older card with no whoami.sh — assemble the same 14-key shape by hand."""
    parts = body.split("@@SEP@@")
    while len(parts) < 4:
        parts.append("")
    unit, legacy, build = jload(parts[0]), jload(parts[1]), jload(parts[2])
    u = unit or legacy or {}
    b = build or {}
    if u.get("__malformed__"):
        u = {}
    if b.get("__malformed__"):
        b = {}
    return {
        "unit_name": u.get("name"), "unit_mac": u.get("mac"),
        "unit_source": u.get("source"),
        # observed, not self-reported: we know which file actually answered
        "unit_store": "/data" if unit else ("/etc/jffs2" if legacy else None),
        "card_build": b.get("version"), "card_hash": b.get("hash"),
        "card_dirty": b.get("dirty"), "card_stock": b.get("stock"),
        "fw_version": parts[3].strip() or None, "read_at": None,
        "__degraded__": True,
    }

for b in open(sys.argv[1]).read().split("@@END@@"):
    if "@@HOST@@" not in b:
        continue
    # Split AFTER the host marker, not on the block's first newline: blocks
    # after the first carry a leading newline from the previous @@END@@.
    rest = b.split("@@HOST@@", 1)[1]
    host, _, body = rest.partition("\n")
    host = host.strip()

    if body.lstrip().startswith("@@RAW@@"):
        d = from_raw(body.split("@@RAW@@", 1)[1])
    else:
        d = jload(body)
        if d is not None and d.get("__malformed__"):
            d = None

    if not d or not any(d.get(k) for k in
                        ("unit_name", "card_hash", "fw_version", "unit_store")):
        rows.append((host, "?", "-", "-", "UNREACHABLE"))
        worst = max(worst, 2)
        continue

    notes = []

    # --- unit identity (notes 9, 10) ---
    name = d.get("unit_name") or "?"
    src = d.get("unit_source")
    if not d.get("unit_name"):
        # A derived name is reconstructible from the MAC; only an override is lost.
        notes.append("UNNAMED-RECOVERABLE" if d.get("unit_mac") else "UNNAMED")
    if (d.get("unit_store") or "").startswith("/etc/jffs2"):
        notes.append("MARKER-ON-MTD6")
    if src == "override":
        overrides.append((host, name))

    # --- card build (note 8) ---
    ch = d.get("card_hash") or "-"
    if not d.get("card_hash") and not d.get("card_build"):
        status = "NO-BUILD-MARKER"
    elif d.get("card_stock") is True:
        status = "STOCK-NO-FIXES"
    elif d.get("card_dirty") is True:
        status = "DIRTY-UNVERIFIABLE"
    elif ch == "dev":
        status = "NO-COMMIT-UNVERIFIABLE"
    elif not expect:
        status = "UNKNOWN-NO-EXPECTED"
    elif ch.startswith(expect) or expect.startswith(ch):
        status = "CURRENT"
    else:
        status = "BEHIND-CARD"

    # 1970 means NTP never synced, so every timestamp this camera reports is
    # meaningless. Surface it rather than silently trusting card_built.
    if (d.get("read_at") or "").startswith("1970"):
        notes.append("CLOCK-UNSET")
    if d.get("__degraded__"):
        notes.append("NO-WHOAMI")

    if status != "CURRENT" or notes:
        worst = max(worst, 1)
    if notes:
        status = status + " / " + " ".join(notes)

    if d.get("fw_version"):
        fws.append(d["fw_version"])
    rows.append((host, name, ch, d.get("fw_version") or "-", status))

hdr = ("HOST", "UNIT", "CARD-HASH", "FW_VERSION", "STATUS")
w = [max([len(hdr[i])] + [len(str(r[i])) for r in rows]) for i in range(5)]
def line(r):
    return "  ".join(str(r[i]).ljust(w[i]) for i in range(4)) + "  " + str(r[4])
print(line(hdr))
print(line(tuple("-" * len(h) for h in hdr)))
for r in rows:
    print(line(r))

print()
print("expected card hash: " + (expect or "UNKNOWN — pass --expect, or run from a git checkout"))
if not expect:
    print("  Without it nothing can be called current, so nothing is.")

if fws:
    uniq = sorted(set(fws))
    if len(uniq) > 1:
        print("\n⚠️  vendor firmware DIVERGES across the fleet (%d distinct):" % len(uniq))
        for v in uniq:
            print("      " + v)
        print("    Not ordered on purpose — which is 'newer' is not decidable here (note 5).")
        worst = max(worst, 1)
    else:
        print("vendor firmware: uniform (%s)" % uniq[0])

if any("MARKER-ON-MTD6" in r[4] for r in rows):
    print("\n⚠️  A unit marker sits in /etc/jffs2 (mtd6 = updater slot C). A firmware")
    print("    update ERASES that whole partition. Migrate it to /data.")

if overrides:
    print("\n⚠️  These units are named by --unit-name OVERRIDE, not derived from their")
    print("    MAC. A derived name re-appears by itself after a wipe; an override does")
    print("    NOT. Back these names up in the catalog — they are the only ones that")
    print("    cannot be reconstructed from the hardware:")
    for h, n in overrides:
        print("      %s  %s" % (h, n))

print("""
Clearing a row is not free, and these are not the same job:
  BEHIND-CARD          write a new card, swap it. Recoverable — pull the card.
                       Cost is the walk, not the write: batch the trips.
  DIRTY / NO-COMMIT    not behind — UNIDENTIFIABLE. Rewrite from a clean commit
                       so the card can say what it is.
  STOCK-NO-FIXES       none of this project's fixes are on that card.
  vendor fw            a real flash: in-place, non-atomic, no rollback, watchdog
                       killed. NEVER ship usr.jffs2 to a hacked camera — slot C
                       is /etc/jffs2, holding telnet, gergehack, the root
                       password AND the WiFi credentials. That does not update a
                       camera, it strands it.
  Nothing reports whether a flash SUCCEEDED except re-running this: `updater`
  checks only that an image opens and fits, then reports success and reboots,
  and a short image dies later at first read of the missing region.""")

sys.exit(worst)
PY
