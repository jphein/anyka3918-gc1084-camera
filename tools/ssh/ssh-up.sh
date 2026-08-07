#! /bin/sh
#
# ssh-up.sh - bring up key-only SSH on every boot. Installed on the SD card at
# /mnt/anyka_hack/dropbear/ and invoked from Factory/config.sh.
#
# WHY THIS EXISTS AT ALL, since dropbear already shipped on every card:
#
#   The hack has carried dropbearmulti AND a host key since 2024, and NOTHING
#   HAS EVER STARTED IT - gergehack.sh has no dropbear invocation of any kind.
#   Port 22 was closed on both of JP's cameras. So this is not "turning on a
#   feature that was off"; it is the first time the daemon has ever run here.
#
#   And the key that shipped could not have been used anyway. MEASURED
#   2026-08-06: the file at /mnt/anyka_hack/dropbear/dropbear_ecdsa_host_key,
#   md5 d643a89f07f51cb32412d66fd34ef34b, is byte-identical to the one served
#   over plain HTTP from the upstream public repo. THE PRIVATE HOST KEY IS
#   PUBLISHED. Anyone can impersonate any camera running this hack and no
#   client will warn, because the key verifies. That inverts the single thing
#   SSH adds over telnet against someone already on the VLAN.
#
#   So the card ships a FRESHLY GENERATED per-camera key (see write-sd-card.sh),
#   and this script installs it. Never reuse the upstream key. Never let
#   dropbear's -R generate one either - see the entropy note below.
#
# THE DAEMON IS DROPBEAR v2016.74 AND THAT DICTATES THE KEY TYPE.
# Measured from the binary: it offers ssh-dss, ssh-rsa and ecdsa-sha2-nistp256/
# 384/521. There is NO ssh-ed25519. Confirmed on the device with a control - an
# ed25519 key placed IN authorized_keys was refused while an ECDSA key in the
# same file on the same server succeeded, which rules out "not authorized" as
# the explanation. curve25519-sha256@libssh.org IS in the binary; that is key
# EXCHANGE, not a key type, and reading it as ed25519 support is the easy
# mistake. RSA is no help either: 2016.74 signs ssh-rsa with SHA-1, which
# OpenSSH 8.8+ refuses by default at both ends.
#
#   >>> KEYS FOR THIS CAMERA MUST BE ECDSA. Both the host key and JP's. <<<

set -u

CARD=/mnt/anyka_hack/dropbear
BIN=$CARD/dropbearmulti
KEYDIR=/data/dropbear
HOSTKEY=$KEYDIR/dropbear_ecdsa_host_key
HOME_DIR=/data/root
AK=$HOME_DIR/.ssh/authorized_keys
LOG=/tmp/ssh-up.log

log() { echo "ssh-up: $*"; echo "ssh-up: $*" >> $LOG 2>/dev/null; }

# --- 1. why /data and not /etc/jffs2, and not the card.
#
# Root's home is "/" and / is squashfs (ro), so ~/.ssh/authorized_keys - the
# only path dropbear will read, it has no option to relocate it - is unwritable
# as shipped. The three writable candidates are not equivalent:
#
#   /etc/jffs2  64 KB at 88% full, and it is mtd6 = slot "C" of the stock
#               updater. A firmware update carrying usr.jffs2 erases the whole
#               partition. Wrong place for a credential.
#   /mnt        the card. Lost on a card swap, and vfat cannot store the 0600
#               that dropbear insists on.
#   /data       mtd7, jffs2 rw, ~500 KB free. Survives card swaps AND firmware
#               updates. <- this one.
#
# We need about 2 KB of it.
[ -f "$BIN" ] || { log "no dropbearmulti on the card - SSH not started"; exit 1; }

mkdir -p "$KEYDIR" "$HOME_DIR/.ssh" 2>/dev/null

# --- 2. the host key: card -> /data, ONLY IF ABSENT.
#
# This asymmetry is deliberate and is the opposite of the project's usual
# "THE CARD WINS" rule, so it needs its reason stated or someone will "fix" it:
#
#   A host key is an IDENTITY, not a setting. If the card won, then rewriting a
#   camera's card - a routine act here, it is how every fix ships - would change
#   that camera's identity, and every client that had verified it would throw a
#   MITM warning. Worse, the warning would become routine, which trains the one
#   reflex that makes host-key verification worth having.
#
# So: a camera adopts a key once and keeps it. A camera out of the bag with a
# fresh card gets that card's key. Both are correct, and neither needs a
# registry.
# `cat >` rather than `cp`, here and for authorized_keys below. MEASURED on the
# camera 2026-08-06: the interactive shell carries `alias cp='cp -i'`, and with
# stdin not a tty that prompt reads EOF, SKIPS THE COPY, AND RETURNS 0 - a
# silent no-op wearing a success code. `cp -f` does NOT defeat it; the alias
# puts -i first and busybox lets it win.
#
# A script run as `sh script.sh` does NOT inherit the alias - also measured, and
# it is why gergehack.sh's card->flash copies are fine. So `cp` would work here.
# It is avoided anyway, because "works as long as nobody sources this file or
# pastes a line of it into a telnet session while debugging" is exactly the kind
# of precondition that holds until the day it doesn't. `cat >` has no
# interactive mode and no alias.
# -s (exists AND non-empty), not -f. Found the hard way 2026-08-06: a botched
# copy left a ZERO-BYTE host key, which -f happily accepts. The camera then
# skipped adoption, dropbear died on the empty key, and the only reason this was
# noticed is the listening-check at the bottom. An -f test here would have made
# a corrupt key permanent - it exists, so it is never replaced.
if [ ! -s "$HOSTKEY" ]; then
  rm -f "$HOSTKEY" 2>/dev/null
  if [ -s "$CARD/dropbear_ecdsa_host_key" ]; then
    cat "$CARD/dropbear_ecdsa_host_key" > "$HOSTKEY" 2>/dev/null
    chmod 600 "$HOSTKEY" 2>/dev/null
    log "adopted host key from the card (first boot for this camera)"
  else
    log "NO HOST KEY on card or in /data - SSH not started"
    exit 1
  fi
fi

# Refuse to serve the published key even if one reaches a camera somehow -
# from an old card, a restored backup, or a hand copy. Cheap, and the failure
# it prevents is silent.
if [ "$(md5sum "$HOSTKEY" | cut -d' ' -f1)" = "d643a89f07f51cb32412d66fd34ef34b" ]; then
  log "REFUSING TO START: this is the PUBLISHED upstream host key."
  log "  Its private half is downloadable from the upstream repo."
  exit 1
fi

# --- 3. authorized_keys: card -> /data, CARD WINS.
#
# Opposite direction to the host key above, and for the opposite reason: this
# one IS a setting. Rewriting the card is how a key is added or revoked, and a
# revocation that the camera could ignore would be worthless.
#
# Compared before copying rather than copied unconditionally: this is jffs2 and
# an unconditional write on every boot of every camera forever is real flash
# wear for something that changes about once a year.
if [ -f "$CARD/authorized_keys" ]; then
  if ! cmp -s "$CARD/authorized_keys" "$AK" 2>/dev/null; then
    cat "$CARD/authorized_keys" > "$AK" 2>/dev/null
    log "installed authorized_keys from the card"
  fi
fi
chmod 700 "$HOME_DIR/.ssh" 2>/dev/null
chmod 600 "$AK" 2>/dev/null

if [ ! -s "$AK" ]; then
  log "authorized_keys is missing or empty - SSH would accept nobody. Not started."
  exit 1
fi

# --- 4. point root's home at a writable place. One 140-byte write, ever.
#
# /etc/passwd is a symlink to jffs2/passwd, 140 bytes, 5 lines. Dropbear reads
# the home directory from getpwnam and offers no override, so this is the only
# seam.
#
# The jffs2-wear objection is already moot: Factory/config.sh runs `passwd` on
# EVERY boot to set the root password, which rewrites /etc/jffs2/shadow every
# boot. One conditional 140-byte write is not a new class of risk.
#
# Guarded and validated because getting it wrong costs root login entirely, on
# a camera whose only other recovery is pulling the card. The staged file must
# still have the same line count and a well-formed root line before it is
# installed, and the original is kept.
if ! grep -q "^root:[^:]*:0:0:[^:]*:$HOME_DIR:" /etc/passwd 2>/dev/null; then
  OLD=$(wc -l < /etc/jffs2/passwd 2>/dev/null)
  [ -f /data/passwd.orig ] || cat /etc/jffs2/passwd > /data/passwd.orig 2>/dev/null
  sed "s|^root:\([^:]*\):0:0:\([^:]*\):/:|root:\1:0:0:\2:$HOME_DIR:|" \
    /etc/jffs2/passwd > /tmp/passwd.new 2>/dev/null
  NEW=$(wc -l < /tmp/passwd.new 2>/dev/null)
  if [ "$OLD" = "$NEW" ] && grep -q "^root:[^:]*:0:0:[^:]*:$HOME_DIR:/bin/sh$" /tmp/passwd.new; then
    cat /tmp/passwd.new > /etc/jffs2/passwd
    log "root home -> $HOME_DIR (original kept at /data/passwd.orig)"
  else
    log "REFUSED to rewrite passwd - staged file failed validation. SSH not started."
    rm -f /tmp/passwd.new
    exit 1
  fi
  rm -f /tmp/passwd.new
fi

# --- 5. start it. -s is the whole point.
#
#   -s  disable password logins.  This is what takes the root password off the
#       wire. Verify it by EFFECT after a change, never by reading the flag:
#         ssh -o PreferredAuthentications=password -o PubkeyAuthentication=no
#       must come back "Permission denied (publickey)".
#   -r  our key, explicitly. Without it dropbear looks in /etc/dropbear, which
#       does not exist here.
#
# NOT USED, deliberately:
#   -R  "create hostkeys as required". It would work and it would be wrong:
#       this camera reports ~180 bits of entropy_avail, which is a poor source
#       for a long-lived key. Keys are generated on the workstation.
#   -w  "disallow root logins" - root is the only account here.
#   -b  a banner would be published on port 22 to anyone who connects.
if [ -f /var/run/dropbear.pid ] && kill -0 "$(cat /var/run/dropbear.pid)" 2>/dev/null; then
  log "already running (pid $(cat /var/run/dropbear.pid))"
else
  setsid "$BIN" dropbear -s -r "$HOSTKEY" -p 22 -P /var/run/dropbear.pid \
    >> $LOG 2>&1 &
  sleep 3
fi

# --- 6. assert the EFFECT, and keep a way back in if it failed.
#
# "A hook that silently never runs is this project's signature failure", and a
# hook that silently fails AFTER telnet has been removed is the version of that
# which costs a site visit and a screwdriver. So the last thing this script does
# is check that something is actually listening on 22 - not that dropbear
# returned 0, which it does regardless.
#
# If it is not listening, telnetd is brought back. That is a deliberate
# trade-off and it is the arguable line in this file:
#
#   for  - the alternative recovery on a headless camera with no console is
#          physically pulling the card. SSH-or-telnet, never neither.
#   against - someone who can break SSH gets telnet back, so it is a downgrade
#          path. It needs local reach and a working root password to be worth
#          anything.
#
# Set SSH_NO_TELNET_FALLBACK=1 in gergesettings.txt to refuse the fallback and
# fail closed instead.
#
# 🔴 THE FALLBACK MUST BE DELAYED, AND THAT IS NOT A REFINEMENT - WITHOUT IT THE
# NET IS GUARANTEED TO FAIL IN EXACTLY THE CASE IT EXISTS FOR.
#
# This script runs BEFORE gergehack.sh (it has to - see the hook placement note
# in write-sd-card.sh). And gergehack.sh, near its top, does:
#
#     if [[ $run_telnet == 0 ]]; then killall telnetd; fi
#
# So on a camera where telnet has been turned off - the only camera where this
# fallback matters at all - an immediate `telnetd &` here is started seconds
# before gergehack kills it. The safety net would be removed by the very setting
# that makes it necessary, silently, and nobody would find out until a camera
# failed to come back and had to have its card pulled.
#
# So: wait past gergehack's killall, then RE-CHECK port 22 and only start telnetd
# if it is still down. Re-checking rather than acting on the earlier result also
# covers the case where dropbear was simply slow to bind - the earlier check is a
# fact about one moment, and a stale one by the time this subshell wakes.
FALLBACK_DELAY=120
if netstat -ltn 2>/dev/null | grep -q ':22 '; then
  log "listening on 22, key-only"
else
  log "FAILED to listen on 22"
  if [ "${SSH_NO_TELNET_FALLBACK:-0}" = "1" ]; then
    log "  telnet fallback disabled by setting - this camera is now unreachable"
    log "  except by pulling the card."
  else
    log "  arming the telnet fallback: re-check in ${FALLBACK_DELAY}s, after"
    log "  gergehack's killall, and start telnetd only if 22 is still down."
    (
      sleep "$FALLBACK_DELAY"
      if netstat -ltn 2>/dev/null | grep -q ':22 '; then
        log "fallback stood down - 22 came up after all"
      else
        log "fallback FIRING - starting telnetd so this camera stays reachable"
        telnetd
      fi
    ) &
  fi
fi
