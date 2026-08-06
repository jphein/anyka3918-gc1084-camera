#!/bin/sh
# Runs ON THE CAMERA, as root, from inside an update.tar.
#
# WHERE THIS SITS IN update.sh - the whole reason it is worth having:
#
#   350  update_ispconfig          <- rm -rf /etc/jffs2/isp*.conf   (unguarded)
#   353  update_audio
#   355  $DIR1/special.sh          <- HERE
#   359  update_kernel     ]
#   360  update_jffs2      ]  every flash write happens AFTER this script
#   361  update_squash     ]
#   362  update_rootfs_squash ]
#
# So a tarball of fw_version + this file and NO partition images proves the
# entire pipeline - discovery, extraction, version gate, root execution - while
# erasing nothing at all. That is not risk mitigated, it is risk absent.
#
# It does three things, in this order, and the order is deliberate:
#   1. leave evidence it ran, before anything that could fail
#   2. repair the sensor-config symlink update_ispconfig just deleted
#   3. disarm itself so the camera does not reboot-loop
#
# EVERYTHING HERE MUST BE SAFE TO RUN TWICE. If the camera loses power between
# step 2 and step 3, this runs again on the next boot.
set -u

# FW_TEST_ROOT exists so selftest.sh can exercise this against a fake tree. It is
# empty on the camera and nothing in the update environment sets it. A script
# that runs as root, once, before a flash, and that nobody can run anywhere else
# is a script nobody tests - and the earlier alternative (sed-rewriting paths in
# the harness) silently double-prefixed one and produced a passing-looking run
# with no log. Explicit beats clever here.
R="${FW_TEST_ROOT:-}"

LOG="$R/data/fw-update.log"
say() { echo "special.sh: $*"; echo "$(date -u +%Y-%m-%dT%H:%M:%SZ 2>/dev/null) $*" >> "$LOG" 2>/dev/null; }

# --- 0. THE CARD IS NOT MOUNTED. This is the detail that turns a one-shot into
#        a loop nobody expected.
#
# update.sh line 344 runs `umount /mnt/ -l` before reaching us - it copies the
# images to /tmp first precisely so a card yank mid-flash cannot truncate one.
# Good for them, but it means /mnt/update/update.tar is out of reach unless we
# put it back. Without this, step 3 silently does nothing and the camera
# reboot-loops until someone pulls the card.
CARD=""
if [ ! -e "$R/mnt/update/update.tar" ]; then
  for dev in /dev/mmcblk0p1 /dev/mmcblk0; do
    [ -e "$dev" ] || continue
    if [ -n "$R" ] || mount -t vfat "$dev" /mnt 2>/dev/null || mount "$dev" /mnt 2>/dev/null; then
      CARD="$dev"; break
    fi
  done
fi

mkdir -p "$R/data" 2>/dev/null
say "ran from update.tar; card remount: ${CARD:-not needed or FAILED}"
say "fw_version in tarball: $(cat "$R/tmp/fw_version" 2>/dev/null)"
say "fw_version on device:  $(cat "$R/usr/fw_version" 2>/dev/null)"

# --- 1. evidence, written first and to /data (mtd7), which the stock updater
#        never targets. If nothing else survives, this line does.
say "unit: $(sed -n 's/.*\"name\": *\"\([^\"]*\)\".*/\1/p' "$R/data/unit.json" 2>/dev/null | head -1)"

# --- 2. repair what update_ispconfig destroyed.
#
# update_ispconfig() is `rm -rf /etc/jffs2/isp*.conf` with NO condition - it
# runs on every update, including this one, which flashes nothing. On this
# camera that symlink is what points the ISP at its sensor config, so without
# it there is no video.
#
# Factory/config.sh does NOT put it back. It guards on the wrong file:
#
#     FILE="/mnt/isp_gc1084.conf"
#     if [ ! -e "$FILE" ]; then ... ln -s ... ; fi
#
# It tests the TARGET on the card, which still exists, so the condition is false
# and the symlink is never recreated. The card is fine; the link is gone.
#
# Rebuilt from whatever the card actually carries rather than a hardcoded
# gc1084, so this is correct on an H63 board too - the bag is not all one
# sensor, and a hardcoded name would be silently wrong on the others.
n=0
for f in "$R"/mnt/isp_*.conf; do
  [ -e "$f" ] || continue
  ln -sf "$f" "$R/etc/jffs2/" 2>/dev/null && n=$((n + 1))
done
if [ "$n" -gt 0 ]; then
  say "restored $n isp*.conf symlink(s) that update_ispconfig deleted"
else
  say "WARNING no /mnt/isp_*.conf found - VIDEO WILL NOT COME UP after reboot."
  say "WARNING fix by hand: ln -s /mnt/isp_<sensor>.conf /etc/jffs2/"
fi

# --- 3. disarm, so this is a ONE-SHOT.
#
# Three measured facts compose into an endless loop otherwise:
#   * /usr/fw_version lives on slot B, so a tarball that flashes nothing cannot
#     change dev_ver;
#   * `#rm -rf /mnt/update` (line 332) is commented out, so the tarball stays;
#   * `reboot -f` (line 371) is unconditional.
# The TF gate is `tar_ver != dev_ver`, so it fires again every boot, forever.
#
# That loop is RECOVERABLE BY PULLING THE CARD, which is the best failure mode
# available on this hardware and the reason the TF path is where we experiment.
# But recoverable is not the same as acceptable on a camera on a pole.
if [ -e "$R/mnt/update/update.tar" ]; then
  rm -f "$R/mnt/update/update.tar" 2>/dev/null
  sync
  if [ -e "$R/mnt/update/update.tar" ]; then
    say "WARNING could not remove /mnt/update/update.tar - THIS CAMERA WILL"
    say "WARNING REBOOT-LOOP until the card is pulled."
  else
    say "disarmed: removed /mnt/update/update.tar (this was a one-shot)"
  fi
else
  say "WARNING /mnt/update/update.tar not reachable - cannot disarm."
  say "WARNING If this tarball flashes no partition, EXPECT A REBOOT LOOP."
  say "WARNING Recovery: power off and pull the SD card."
fi

sync
[ -n "$CARD" ] && [ -z "$R" ] && umount /mnt 2>/dev/null
say "done"
exit 0
