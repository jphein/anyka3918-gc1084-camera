#! /bin/sh
#
# libre_anyka_app launcher with per-boot IR-cut node detection.
#
# THIS FILE IS OURS, not upstream's. Upstream's original is kept alongside as
# run_libre_anyka_app.sh.upstream for reference.
#
# WHY THIS EXISTS
# ---------------
# libre_anyka_app hard-codes the sysfs path it uses to move the IR-cut filter.
# Two vendor kernel builds disagree about that path:
#
#   2023 build (chensheng)   /sys/user-gpio/ircut_a         <- unprefixed
#   2022 build (zhoujiahui)  /sys/user-gpio/gpio-ircut_a    <- prefixed
#
# The stock binary writes the PREFIXED name, so on a 2023 camera it gets ENOENT
# on every day/night transition and automatic IR-cut switching has never worked.
# A patched binary writes the unprefixed name - and is then wrong on a 2022
# camera, for the same reason in reverse.
#
# So the card carries BOTH and picks one here, every boot, by testing which node
# actually exists. Consequences worth knowing:
#
#   * ONE CARD WORKS IN ANY OF THESE CAMERAS. Swapping a card between units is a
#     supported operation - it re-detects and is correct in the new one.
#   * Nothing is written at boot. Nothing to corrupt if power is cut mid-boot.
#   * No state, no first-boot marker, nothing that can go stale.
#
# We test the NODE NAME rather than parsing /proc/version for a build string,
# because the node name is the fact the binary actually depends on. A third
# vendor build using either convention is then handled for free, and we are not
# betting on a username in a version string.
#
# Detection deliberately happens AFTER the insmod block below: the /sys/user-gpio
# nodes are not guaranteed to exist before the camera modules load.

# shellcheck disable=SC2154  # image_width, extra_args etc come from the
# sourced gergesettings.txt below, exactly as upstream's original did.

APPDIR=/mnt/anyka_hack/libre_anyka_app
BIN_UNPREFIXED="$APPDIR/libre_anyka_app.node-ircut_a"       # patched
BIN_PREFIXED="$APPDIR/libre_anyka_app.node-gpio-ircut_a"    # stock/upstream

# import settings
. /etc/jffs2/gergesettings.txt

# load kernel modules for camera (must precede detection)
insmod $sensor_kern_module
insmod /usr/modules/akcamera.ko
insmod /usr/modules/ak_info_dump.ko

# --- pick the binary that matches THIS camera's sysfs naming
if [ -e /sys/user-gpio/ircut_a ]; then
  BIN="$BIN_UNPREFIXED"
  echo "ircut: node is /sys/user-gpio/ircut_a (unprefixed) -> using patched binary"
elif [ -e /sys/user-gpio/gpio-ircut_a ]; then
  BIN="$BIN_PREFIXED"
  echo "ircut: node is /sys/user-gpio/gpio-ircut_a (prefixed) -> using stock binary"
else
  echo "ircut: ERROR - NEITHER /sys/user-gpio/ircut_a NOR gpio-ircut_a exists."
  echo "ircut: this camera does not match either known firmware build."
  echo "ircut: falling back to the stock binary; automatic day/night IR-cut"
  echo "ircut: switching will probably not work. Investigate before trusting it."
  BIN="$BIN_PREFIXED"
fi

# --- fall back rather than fail to start video
if [ ! -f "$BIN" ]; then
  echo "ircut: WARNING - $BIN missing, falling back to stock"
  BIN="$BIN_PREFIXED"
fi
if [ ! -f "$BIN" ]; then
  echo "ircut: FATAL - no libre_anyka_app binary on the card at $APPDIR"
  exit 1
fi

echo "starting libre anyka app: $BIN"
export LD_LIBRARY_PATH="$APPDIR/lib"

# exec so the watchdog's `top | grep libre_anyka_app` still matches - every
# candidate filename contains that substring, which is why renaming is safe.
exec "$BIN" -w $image_width -h $image_height -m $md_record_sec $extra_args
