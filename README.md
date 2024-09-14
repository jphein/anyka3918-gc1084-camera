# ak3918-gc1084-camera ESPhome integration for Home Assistant
Brand: Teruhal
Model: TC20
FCC ID: 2BEXJ-TC20

I got my camera from temu: https://share.temu.com/A5qeTOEZVbA
![image](https://github.com/user-attachments/assets/c23b2242-16df-46c6-87fc-d2d16095efb9)
Price is in the $3 to $8 range. 
I took apart using the 4 screws on the main body. 
The antennas on the outside are fake. It has a small printed circuit board antenna taped to the inside of the main compartment instead. 
The main chip is the anyka ak3918. The camera sensor chip is the gc1084.

Since my camera used the exact same micro controller chip, and wifi card. I was able to use this great project:
https://gitea.raspiweb.com/Gerge/Anyka_ak3918_hacking_journey/
I was able to telnet in after changing the root password.

Then since this I had a different camera sensor then the original camera the Gerge worked on, I had to make a few changes. Add to the bottome of the /Factory/config.sh file the following. Before the gergehack.sh script is run.
```
#gergedaemon and time_zone are not needed for the SD exploit
/etc/jffs2/gergehack.sh
```

To change the root password.
```
#change root password
#!/bin/bash

USER="root"
NEW_PASSWORD="newrootpassword"

# Use a here-document to send password input to the passwd command
(echo "$NEW_PASSWORD"; echo "$NEW_PASSWORD") | passwd $USER
```

To uncompress the module conf file, and make a symlink to it on the sd card since there is not enough room in the /etc/jffs2 partition. 
```
#extract sensor.tgz into the sdcard
tar -xzf /etc/jffs2/sensor.tgz -C /mnt

#make the symlink
ln -s /mnt/isp_gc1084.conf /etc/jffs2/
```
