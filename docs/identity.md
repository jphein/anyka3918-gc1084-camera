# Identity and version — what is this camera, and what is it running?

JP has a bag of these. Until now every card was the same card and every camera
was the same camera: no per-unit name, no way to ask a running device which
build it is on, and a DHCP reservation as the only thing telling two of them
apart. This is the fix for [backlog](backlog.md) gap 1.

**The one-line answer**, over telnet or dropbear:

```
# /mnt/anyka_hack/identity/whoami.sh
unit:
  name   Arcane Quartz · 4f2a91
  mac    3c:6a:9d:4f:2a:91
  named  2026-08-06T19:31:02Z   (source: mac, store: /data/unit.json)
build:
  version  Molten Smelter · df16c66
  hash     df16c66  branch main  dirty false
  built    2026-08-06T19:22:18Z
  writer   katana
clock:
  now      2026-08-06T20:04:55Z  (1970 = NTP never synced)
```

---

> **Fleet scope.** JP has two Anykas and twelve **EYEPLUS icam365s**. Almost
> everything else in this repo is Anyka-only — the card writer, the updater
> work, the GPIO map. **This scheme is the part that travels**: a unit names
> itself from its own MAC, write-once, with no registry, which is a property of
> the *approach* rather than of this SoC.
>
> What does **not** travel is the transport. `whoami.sh` reads two files over
> telnet because that is what this firmware offers. An EYEPLUS unit needs its
> own read path emitting the same 14 keys. **Keep the key contract; expect to
> rewrite the reader.**

## Two markers, because there are two different facts

| | **Unit** | **Build** |
|---|---|---|
| Answers | *which camera is this?* | *which card is it running?* |
| Lives in | `/data/unit.json` (camera flash, `mtd7`) | `/anyka_hack/build.json` (the SD card) |
| Written by | `name-unit.sh`, once, at first boot | `tools/write-sd-card.sh`, at card-write time |
| Realm | `fleet` | `forge` |
| On a card swap | **stays with the camera** | **follows the card** |

That split is the whole point. Move a card from camera A to camera B and B keeps
its own name while the build version travels with the card — so "which cameras
are behind?" is a question you can answer by walking the fleet, instead of a
spreadsheet nobody updated.

### Why `/data` and not `/etc/jffs2`

Both survive a card swap, so that is not what decides it. The **updater** is.

`/etc/jffs2` is `mtd6`, which is slot **`C`** of the stock `/usr/sbin/update.sh`.
A firmware update carrying `usr.jffs2` overwrites that whole partition. `/data`
is `mtd7`, slot `D`, which `update.sh` never writes. See
[`reference/usr-sbin/README.md`](../reference/usr-sbin/README.md), which resolved
the slot→mtd mapping out of `/proc/mtd` and the updater binary.

**State that narrowly.** The only claim proved is: **`update.sh` never invokes
`D=`** — a property of the *script*, verified across all five of its update
functions. It is **not** a property of the partition, and "survives firmware
updates" as a general statement is false.

Two caveats, both respected:

- `D` is **reachable**. `updater` holds no partition table and no name
  whitelist — it builds `/sys/kernel/partition_table/<NAME>/mtd_index` from
  whatever string it is handed, and the live table exposes `D → 7`. So
  `updater local D=<file>` *would* flash `/data`. The usage text listing only
  `KERNEL`/`A`/`B`/`C` is documentation, not enforcement.

  > ⚠️ **Any update tooling we write must treat `D=` as forbidden.** Invoking it
  > erases this marker on every camera it touches. Backlog gap 3 now points at
  > building exactly that tooling, so the constraint is also written in
  > `name-unit.sh`, next to the thing it protects.

- `update_factory_data.sh` does `rm -rf /data/audio_file/*` before untarring an
  audio package, with no integrity check. So the marker sits at the top of
  `/data`, never inside `audio_file/`, and never uses one of the four `wifi_*`
  names that script also writes there.

### Why this marker matters more than inventory convenience

`updater` performs exactly two checks on a local image: it opens, and it fits.
No squashfs magic, no header consistency, no md5 on the local path. A truncated
image is erased in and written verbatim, and the device **reports success and
reboots**, then fails later at first read of the missing region.

So the flashing process never tells the truth and the failure is *delayed*. That
makes this marker the only post-flash verification available — the sole way to
establish whether a flash actually took. It needs to be readable early and to
survive a partially-bad flash, not just a good one.

`/etc/jffs2` remains a last-resort fallback if `/data` is somehow absent. It is
warned about loudly and the marker records which store it landed in.

### A legacy mtd6 marker is migrated, not just reported

If a marker is found at `/etc/jffs2/unit.json`, the next boot **copies it to
`/data` and removes the mtd6 copy**. The state is reachable going forward, not
only historically — the no-`/data` fallback above can create one.

Migration earns its place on the case that **cannot self-heal**. A MAC-derived
name erased by a slot-`C` update re-derives identically, so for those this is
only tidying. An `--unit-name` override is *not* derivable: erase it and the
name JP chose is gone for good, with no error anywhere.

Three properties worth knowing:

- **The name is copied verbatim and never recomputed.** A migration that
  re-derived would silently rename any unit carrying an override — the precise
  failure it exists to prevent. Only the `store` field is rewritten.
- **The mtd6 copy is removed only after the `/data` copy is in place.** A power
  cut leaves one marker or two, never zero.
- **With no `/data` at all, the legacy marker is left intact** and warned about,
  rather than destroyed with nowhere to put it.

### The property that makes a wipe survivable

The name is **derived from the MAC**, so it is idempotent. If a marker is ever
lost — an update, a reflash, a wiped partition — the next boot re-derives the
**same name from the same MAC**. A wipe costs a boot, not an identity.

That does **not** hold for `--unit-name`. An override is not derivable, so a
wiped override is genuinely gone unless the card still carries it. That
asymmetry is the real cost of overriding, and it is why self-naming is the
default rather than a fallback.

---

## How a camera names itself

At first boot, `/Factory/config.sh` launches `name-unit.sh` in the background.
It waits for the MAC (up to five minutes — the interface only appears once
`gergehack.sh` has run `wifi_manage.sh`), then:

```
mac   = /sys/class/net/wlan0/address        e.g. 3c:6a:9d:4f:2a:91
low24 = last 6 hex digits                        0x4f2a91      (the OUI is
                                                  identical across the bag, so
                                                  it carries no information)
seed  = (low24 × 2654435761) mod 2^32            the golden-ratio spread
name  = fleet.adjectives[seed % 32]
        + fleet.nouns[(seed >> 8) % 32]
        + " · " + low24                          "Arcane Quartz · 4f2a91"
```

> ⚠️ **`3c:6a:9d:4f:2a:91` is illustrative** — it was never read from a device. It is not this
> camera's address, and its OUI belongs to an unrelated vendor, so **do not read anything into the
> prefix** when debugging your own unit.

**Write-once.** If a marker already exists, the script exits without touching
it. Re-writing a card, changing a build, or swapping a card never renames a
camera.

**If no MAC appears, nothing is written.** A camera you have to look up in the
lease table is annoying; a camera named from a fabricated seed is a camera whose
name means nothing, permanently. The next boot tries again.

### Why the golden-ratio spread is not optional

Seeding straight from the MAC looks fine — 24 bits is plenty of entropy — and it
is wrong. MACs in a bag come from one vendor block and are **consecutive**, often
with a stride. Measured, distinct `Adjective Noun` pairs over K units:

| scenario | K | raw MAC | spread | md5 |
|---|---|---|---|---|
| sequential batch | 50 | 32 | **50** | 46 |
| sequential batch | 256 | 32 | **256** | 224 |
| sequential, stride 4 | 50 | **8** | **50** | 50 |
| sequential, stride 4 | 256 | 32 | 162 | 220 |
| random MACs | 256 | 229 | 229 | 235 |

> ⚠️ **Those raw figures are from a single base — `0x001000`, which is
> 256-aligned — and alignment is the best case for the argument.** Median over
> 2000 random bases: **16** (not 8) for stride-4/K=50, and **64** (not 32) for
> sequential/K=256. A reader reproducing at a different base will get different
> raw numbers; that is the base, not a disagreement.
>
> The conclusion is untouched, and the spread's figures are *stronger* than one
> base suggests: across all 2000 bases the spread's **minimum** was 50/50 and
> 256/256 respectively — it never once did worse.

**Fifty cameras at stride 4 collapse onto 8–16 distinct names** with a raw seed.

The mechanism, stated correctly — and the wrong version of this sentence sat in
this file for a day, refuted by the table two lines above it:

> With a raw seed the noun index is bits 8–12, which are **constant across any
> aligned 256-wide MAC window**. So a bag whose MACs fall inside one window gets
> **at most 32 names** — one noun, 32 adjectives — however many cameras are in
> it.

That cap is **per window, not absolute**. Spread far enough apart and raw
seeding does recover: 8192 sequential MACs give all 1024 names, and 256 random
MACs give 229. The earlier text claimed the 32 was a global ceiling, which the
`random MACs | 256 | 229` row in this very table disproves. The cap is real and
the fleet argument survives — a bag *is* one window — but the quantifier was
wrong, and being wrong in a way the adjacent table refutes is worse than being
wrong quietly.

The spread also beats hashing on the case that actually occurs, and that is not
luck. `2654435761` is odd, so `gcd(G, 32) = 1` and `id ↦ (id·G) mod 32` is a
**bijection mod 32** — it needs only that the inputs are distinct mod 32, and
consecutive integers are. The proof is in lexicon's
`docs/superpowers/design/node-identity-namespace.md`; it was written for smol's
`u8` board ids and transfers to consecutive MAC tails unchanged.

### The 32-bit problem, and why the shell arithmetic is still exact

`low24 × 2654435761` reaches ~2^55, which busybox `ash` cannot represent on this
32-bit ARM. It does not have to. Only bits 0–4 and 8–12 of the product are ever
read, i.e. only `product mod 2^13`:

```
t = ((low24 mod 8192) × 6577) mod 8192          6577 = 2654435761 mod 8192
adj = A[t % 32] ;  noun = N[(t >> 8) % 32]      largest intermediate 53,872,207
```

Not an approximation. `tools/identity/verify-pin.sh` enumerates it against the
reference over all 16,777,216 inputs.

**It is exact only for table sizes that divide those bit fields**, and
`sigil-name.sh` now asserts the precondition rather than assuming it.
Truncating to 13 bits preserves `x % NADJ` only when `NADJ` divides 8192, and
`(x >> 8) % NNOUN` only when `NNOUN` divides 32. `fleet` is 32 × 32 and
satisfies both; `forge` is 14 × 14 and does not. Before the guard,
`sigil-name.sh --realm forge --mac ...` returned `Forged Crucible` where every
other sigil implementation gives `Anvilled Mold` — **a plausible wrong answer at
exit 0**. Unreachable in this repo (`--mac` is only ever paired with `fleet`),
but a naming tool that silently disagrees with its own reference is the failure
class this project has spent a day cataloguing, so it now refuses.

---

## Which realm, and why it matters

From lexicon's node-identity design document, which is the authority on this:

| Namespace | Names | Realm |
|---|---|---|
| **Identity** | a node — *which board is this?* | `fleet`, **size-locked 32 × 32** |
| **Provenance** | a build — *which firmware is this?* | `forge` |
| Roles, frames, features, tools | — | reserved, never a name |

`fantasy` is deliberately **not** used, even though it is sigil's default and the
obvious first choice. Node identity was moved out of it into a size-locked
`fleet` group precisely so device names stop churning when an unrelated consumer
adds a word, and `fantasy` still contains words that mean something else in this
family (`sigil`, `crown`, `beacon`, `herald`, `oracle`).

`fleet` and `forge` share no word in either position, so a name never reads as a
version at a glance. Verified by `verify-pin.sh`.

**The word tables are pinned.** Indices are `% len`, so the word *count* is the
modulus: one word added upstream renames every camera in the bag. See
[`tools/identity/PINNED.md`](../tools/identity/PINNED.md) for the pinned commit
and what re-pinning would cost.

### Two honest limits

**This is a strong spread, not a uniqueness proof.** The guarantee in the design
document is an exhaustive enumeration over a 256-id space; MACs are not that
space. `Adjective Noun` draws from 1024 combinations, so it *can* repeat. The
full `Arcane Quartz · 4f2a91` does not repeat while MACs are unique — and per the
design doc's invariant, **a bare noun is never an identifier**. Quote the whole
sigil, or the noun with its adjective.

**The trailing token deviates from sigil's contract, on purpose.** sigil renders
`{adj} {noun} · {hash}` where the hash *is* the seed, so
`GenerateName(hash, realm)` round-trips. Here the trailing token is the MAC tail
while the seed is its spread, so `GenerateName("4f2a91", "fleet")` does **not**
reproduce this name. smol has the same deviation for the same reason.

The MAC tail was chosen over the spread value because it is the one token that
cross-references the DHCP lease table — the thing that used to be the *only* way
to tell these cameras apart. The marker also records `sigil_seed`, so the name
can be reproduced in Go, Python or JS by anyone who wants to check:
`GenerateName(sigil_seed, "fleet")` matches byte-for-byte.

---

## Marker formats

Plain JSON, one key per line. Valid JSON so a workstation can `json.tool` it;
one key per line so the camera can read it with `sed`, because there is no `jq`
on a 400 MHz ARM926.

`/data/unit.json` — 281 bytes:

```json
{
  "kind": "unit",
  "name": "Arcane Quartz · 4f2a91",
  "short": "Arcane Quartz",
  "realm": "fleet",
  "mac": "3c:6a:9d:4f:2a:91",
  "sigil_seed": "6cd",
  "source": "mac",
  "store": "/data",
  "named": "2026-08-06T19:31:02Z",
  "corpus": "realm-sigil 7cd4e46 fleet 32x32"
}
```

`/anyka_hack/build.json` — on the card, readable on a workstation by mounting it:

```json
{
  "kind": "build",
  "name": "anyka3918-gc1084-camera",
  "description": "AK3918 + GC1084 camera SD card",
  "version": "Molten Smelter · df16c66",
  "hash": "df16c66",
  "branch": "main",
  "dirty": false,
  "built": "2026-08-06T19:22:18Z",
  "realm": "forge",
  "repo": "https://github.com/jphein/anyka3918-gc1084-camera",
  "commit_url": "https://github.com/jphein/anyka3918-gc1084-camera/commit/df16c66",
  "stock": false,
  "backup": "anyka-yicam-sd-2026-08-05",
  "writer_host": "katana",
  "ssid_set": true,
  "time_source_set": false
}
```

Field names follow realm-sigil's version response where they apply. The
server-only fields (`started`, `uptime`, `pid`, `runtime`) are omitted — a card
is not a running process.

**`ssid_set` and `time_source_set` are booleans on purpose.** The SSID, the PSK
and the `time_source` address are *not* written here. This is the file that gets
pasted into tickets and chat; it must not become the second place the real SSID
and the real VLAN address live.

**A third version fact exists.** The vendor's own `fw_version` describes what is
in flash, and neither marker reports it. Backlog gap 2 warns that an inventory
with a single field called "version" will be wrong about two of the three.

---

## Reading it back

| Where you are | How |
|---|---|
| On the camera | `/mnt/anyka_hack/identity/whoami.sh` |
| Enumerating a fleet | `whoami.sh --json` over telnet/dropbear |
| On the camera, raw | `cat /data/unit.json /mnt/anyka_hack/build.json` |
| Holding the card | mount it and read `/anyka_hack/build.json` — **build only**; the unit name is in the camera, not on the card |
| Watching it boot | every line the naming hook prints is prefixed `identity:` |

### `--json` — the enumerator's contract

Fourteen keys, **every one always present**, `null` when unknown. A reader must
never have to tell "absent" from "unknown"; that distinction is where
inventories start guessing.

```
unit_name  unit_short  unit_mac  unit_source  unit_store  unit_named
card_build card_hash   card_branch card_dirty card_built  card_stock
fw_version
read_at
```

**Nothing is called bare `version`**, because three different facts answer to
that word:

| concept | key | source | changes when |
|---|---|---|---|
| vendor firmware | `fw_version` | `/usr/fw_version`, read **live** | slot `B` is actually flashed |
| our card build | `card_build` / `card_hash` | the card's `build.json` | a card is written or swapped |
| unit identity | `unit_name` | the camera's `unit.json` | never — it *is* the unit |

`fw_version` is read **live on every invocation and never cached into a
marker**. The markers are written once while the flash can change underneath
them, so a marker carrying a firmware version would report a stale one with
total confidence. `read_at` is stamped live for the same reason — a caller can
tell a fresh read from a cached one.

**`card_build` is cosmetic. Never compare it.** Two sigil names can sort any
way at all. Compare `card_hash` against git history.

**Two states that are *unidentifiable*, not *behind*** — a different problem
with a different fix (rewrite from a clean checkout). `whoami.sh` calls both out
rather than printing them as if they were values:

| state | means |
|---|---|
| `card_hash: "dev"` | git could not identify the checkout at write time. A **sentinel that reads like a value** — this card cannot say which commit produced it. |
| `card_dirty: true` | the tree had uncommitted changes, so the hash does not fully describe the card. |
| `card_stock: true` | written with `--stock`: none of the project fixes, and no identity toolkit. |

**Parse these with a real JSON parser, not a regex.** `dirty` and `stock` are
unquoted booleans; a pattern that treats them as strings gets them **silently**
wrong, which is exactly the failure an inventory exists to catch. That is why
the enumerator parses on the workstation rather than on the device, where no
JSON parser is available.

### Reading identity costs no token — and that is load-bearing

The camera holds **exactly one** web session token in `/tmp/token.txt`, so
minting a new one silently invalidates every other session. That is not
theoretical: `docs/home-assistant.md` records it flipping an HA switch off in
production. An enumerator that logged into every camera would reproduce that
fleet-wide, and the symptom — HA switches misbehaving — would point nowhere near
the sweep.

**telnet and dropbear never touch `/tmp/token.txt`**, so `whoami.sh --json` over
a shell is already token-free. It also never touches port 3000, where a bare TCP
connect kills the snapshot server.

**A `ctl?command=identity` verb would not be equivalent, and this is the trap
worth naming.** `ctl` *validates* `/tmp/token.txt`; it does not mint one. So an
enumerator would first have to log in to obtain a token — which is exactly the
minting that breaks HA. Routing identity through `ctl` would *create* the
problem it was meant to avoid. `status` and `sounds` are token-checked too; they
only look token-free.

**The unauthenticated-HTTP option, deliberately not taken.** A static copy of
the marker under `/mnt/anyka_hack/web_interface/www/` would be served by busybox
httpd with no CGI and no new code, and the incremental disclosure is close to
zero — the MAC is already ARP-visible on that VLAN and the git hash points at a
public repo. It is not implemented because it is a **policy** call about an
unauthenticated surface on a camera fleet, not a technical one, and this is a
project where defaulting into things has cost real time. It is four lines in the
writer plus a per-boot refresh if wanted.

---

## Using it

```bash
# a camera out of the bag: it names itself, nothing to configure
sudo tools/write-sd-card.sh /dev/sdX --ssid MyNetwork --time-source 192.0.2.1

# a camera JP wants to name himself (only applies if it has never been named)
sudo tools/write-sd-card.sh /dev/sdX --ssid MyNetwork --unit-name "Front Door"
```

`--unit-name` is optional by design. `--ssid` is required because a wrong SSID
strands a camera; a missing name strands nothing, because the camera names
itself.

## Checking the work

```bash
tools/identity/verify-pin.sh   # corpus pin, index math, cross-language parity
tools/identity/selftest.sh     # the on-camera flow, under busybox ash
```

`selftest.sh` runs `name-unit.sh` against a fake tree under **busybox ash — the
camera's actual shell, not bash** — because the camera gets exactly one chance to
name itself and the result is write-once.

### What is NOT verified on hardware

Everything above is repo-side. As of 2026-08-06 **no part of this has run on a
camera** — the device was owned by another agent throughout. Specifically
unverified:

- whether `wlan0` has appeared within the wait window on a real boot
- the real free-space figure on `/data`, and jffs2 behaviour under a power cut
  mid-write
- whether `df` and `date` exist in this busybox build (both are handled if
  absent; `awk` **is** confirmed present — the stock card's `login_validate.sh`
  and `settings_submit.sh` use it)
- FAT32 mode behaviour for `install -m` on the real card mount

First camera to take a card should have its boot console watched for
`identity:` lines.
