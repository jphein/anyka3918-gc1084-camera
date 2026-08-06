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
#gergedaemon and time_zone are not needed for the SD exploit
/etc/jffs2/gergehack.sh
