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

Two caveats recorded there, both respected:

- `D` is **reachable** — `updater local D=<file>` resolves and there is no name
  whitelist. `/data` is *unwritten by the shipped scripts*, not unwritable.
- `update_factory_data.sh` does `rm -rf /data/audio_file/*`, so the marker sits
  at the top of `/data` and never inside `audio_file/`.

`/etc/jffs2` remains a last-resort fallback if `/data` is somehow absent. It is
warned about loudly and the marker records which store it landed in.

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

**Fifty cameras at stride 4 collapse onto eight names** with a raw seed, and a
raw seed caps at 32 distinct names however many cameras you own.

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
adj = A[t % 32] ;  noun = N[(t >> 8) % 32]      largest intermediate 53,878,207
```

Not an approximation. `tools/identity/verify-pin.sh` enumerates it against the
reference over all 16,777,216 inputs.

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
| On the camera, raw | `cat /data/unit.json /mnt/anyka_hack/build.json` |
| Holding the card | mount it and read `/anyka_hack/build.json` — **build only**; the unit name is in the camera, not on the card |
| Watching it boot | every line the naming hook prints is prefixed `identity:` |

**There is deliberately no HTTP endpoint.** `ctl` could carry an `identity` verb
and that is the obvious next step, but post-auth on this web UI already means
root by design, and a pre-auth endpoint on a camera with this project's history
is a cost with no matching need yet. When inventory (backlog gap 2) needs a
network read path, decide it then — with the auth question in front of you.

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
