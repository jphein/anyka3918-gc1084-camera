# Pinned sigil word tables

`fleet.adjectives`, `fleet.nouns`, `forge.adjectives`, `forge.nouns` are a
**verbatim snapshot** of [realm-sigil](https://github.com/jphein/realm-sigil)'s
*generated* tables.

| | |
|---|---|
| Taken | 2026-08-06 |
| From | `realm-sigil` HEAD `ac368fd`; corpus last changed by `7cd4e46` *"converge all four bindings"* (2026-07-29) |
| Source file | `go/realms.go` (the generated table, **not** `words/realms.json`) |
| Sizes | `fleet` 32 × 32 · `forge` 14 × 14 |

## Why a snapshot at all

The camera has no network at the moment it names itself, no package manager, and
no Go/Python/JS runtime. The words have to be on the card. That is the boring
reason.

The load-bearing reason is that **the word count is the modulus**. Indices are
`% len`, so adding or removing a single word renames every camera in the bag.
A device identity that churns when an unrelated repo gains a word is not an
identity. [smol](https://github.com/jphein/smol) pins for the same reason, and
[sigil issue #4](https://github.com/jphein/realm-sigil/issues/4) tracks the
underlying corpus-drift problem.

## What was measured when this snapshot was taken

Unlike smol's situation, the four bindings had already converged — so this pin
is to a *known-good, agreed* state rather than to one of several disagreeing
ones. Verified on 2026-08-06 against the checkout named above:

```
corpus parity (go / python / js / words.json)
  fleet    4-way identical: True   (32 adj x 32 nouns)
  forge    4-way identical: True   (14 adj x 14 nouns)

fleet is size-locked at 32 x 32                     : True
fleet INTERSECT forge, either position              : EMPTY
fleet INTERSECT reserved.json                       : EMPTY
fleet nouns distinct truncated to 4/5/6/8 chars     : True
```

Re-run all of that with `./verify-pin.sh`.

## Why these two realms

From lexicon's design document
`~/Projects/lexicon.realm.watch/docs/superpowers/design/node-identity-namespace.md`
(Nebula, 2026-07-28), which is the authority on this split:

| Namespace | Names | Realm |
|---|---|---|
| **Identity** | a node — *which board is this?* | `fleet`, size-locked 32 × 32 |
| **Provenance** | a build — *which firmware is this?* | `forge` |

`fantasy` is deliberately **not** used. It is the vocabulary the `project`
recipe rolls from and the one other consumers are free to grow; node identity
was moved out of it into `fleet` precisely so device names stop churning. It
also still contains words that are project vocabulary elsewhere (`sigil`,
`crown`, `beacon`, `herald`, `oracle`), which is why `fleet` was curated against
`reserved.json` in the first place.

## Re-pinning is a fleet-wide rename

**Do not re-pin to silence `verify-pin.sh`.** If the counts changed upstream,
re-pinning renames every already-named camera in the bag — and because naming is
write-once, the cameras keep their *old* names while every new camera gets a name
from the new table. You would end up with two naming epochs and no way to tell
them apart except the `corpus` field in each marker.

If you do re-pin deliberately:

1. Bump the `corpus` string in `name-unit.sh` so old and new markers are
   distinguishable.
2. Say so in `docs/identity.md` with the date.
3. Accept that already-named cameras do not move. That is the write-once rule
   working, not a bug.

A word *swap* at an unchanged count only moves the name at that one index — the
design doc's "words are free, counts are not" corollary. Still a rename for
whichever camera sat on that index.
