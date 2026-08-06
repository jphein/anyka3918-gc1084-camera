#! /bin/sh
telnetd &
if ! [[ -f /etc/jffs2/gergehack.sh ]]; then
  #not installed yet, so copy it
  cp /mnt/anyka_hack/gergehack.sh /etc/jffs2/gergehack.sh
fi

if ! [[ -f /etc/jffs2/gergesettings.txt ]]; then
  #not installed yet, so copy it
  cp /mnt/anyka_hack/gergesettings.txt /etc/jffs2/gergesettings.txt
fi
#change root password
#!/bin/bash

USER="root"
NEW_PASSWORD="<REDACTED>"

# Use a here-document to send password input to the passwd command
(echo "$NEW_PASSWORD"; echo "$NEW_PASSWORD") | passwd $USER
#gergedaemon and time_zone are not needed for the SD exploit

#extract sensor.tgz into the sdcard if not there.
FILE="/mnt/isp_gc1084.conf"
if [ ! -e "$FILE"; then
  tar -xzf /etc/jffs2/sensor.tgz -C /mnt
  #make the symlink
  ln -s /mnt/isp_gc1084.conf /etc/jffs2/
fi

/etc/jffs2/gergehack.sh
