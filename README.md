# ak3918-gc1084-camera RTSP integration for Home Assistant with go2rtc
## 
* Brand: Teruhal
* Model: TC20
* FCC ID: 2BEXJ-TC20
* MPU: AK3918EN080 V200 CDSJ09J23
* WiFi: ZT9101UV20
* Camera sensor: GC1084
* APP: [Yi IOT](https://play.google.com/store/apps/details?id=com.yunyi.smartcamera&pcampaignid=web_share)

## What's working?
* WiFi
* Video
* Sound
* PTZ - Pan and Tilt (Oly from the webui. Haven't figured this out from Home Assistant yet)

I got my camera from temu: https://share.temu.com/A5qeTOEZVbA Price is in the $3 to $8 range. 
![image](https://github.com/user-attachments/assets/c23b2242-16df-46c6-87fc-d2d16095efb9)

I took apart using the 3 screws on the main body. 
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
#extract sensor.tgz into the sdcard if not there.
FILE="/mnt/isp_gc1084.conf"
if [ ! -e "$FILE"; then
  tar -xzf /etc/jffs2/sensor.tgz -C /mnt
  #make the symlink
  ln -s /mnt/isp_gc1084.conf /etc/jffs2/
fi
```

Actually, I already found it decompressed in /tmp
I can just make a symlink from there.
```
ln -s /tmp/sensor_ko_and_isp_conf/isp_gc1084.conf /etc/jffs2/
```

## What is working
Camera works from both main freed and sub feed. pretty good quality, but pretty slow high latency at 5-15fps. PTZ works well, and so does the microphone. 
PTZ? = 
Pan Tilt Zoom - basically the camera controls.

## Lights and IR
I can't get the lights or the IR lights to work yet.
I tried:
```
echo "1" > /sys/user-gpio/WHITE_LED
echo "1" > /sys/user-gpio/IR_LED
```
the IR LEDs are automaticly controlled by a photoresistor? 

## Sound from the builtin speaker in the camera
I haven't yet figured out how to use the speaker.
https://gitea.raspiweb.com/Gerge/Anyka_ak3918_hacking_journey/src/branch/main/SD_card_contents/anyka_hack/ak_adec_demo

## IR shutter/filter operation (the thing that makes the CLICK sound)
This is different from the IR LEDs, the LEDs are automaticly controlled by a photoresistor
When this is on it makes everything pink. It was stuck on for me the next day for some reason. 
To turn off
```
echo "1" > /sys/user-gpio/ircut_b
echo "1" > /sys/user-gpio/ircut_b
```
## PTZ from Home assistant
I will probably use the telnet integration, or maybe the webui endpoints if I can figure out the token, and auth. 
After that I'll use the [webrtc custom card](https://github.com/AlexxIT/WebRTC?tab=readme-ov-file#custom-card) ptz controls:
```
##Custom
##configuration.yaml

script:
  camera_ptz:
    sequence:
      - service: rest_command.camera_ptz_start
        data:
          param: "{{ direction }}"
      - service: rest_command.camera_ptz_stop
        data:
          param: "{{ direction }}"
##card

type: 'custom:webrtc-camera'
entity: ...
ptz:
  service: script.camera_ptz
  data_left:
    direction: directionleft
  data_right:
    direction: directionright
  data_up:
    direction: directionup
  data_down:
    direction: directiondown
```
From: https://github.com/AlexxIT/WebRTC/wiki/PTZ-Config-Examples

## Home assistant with the webrtc custom card works well for video and audio
What works
* Fullscreen
* Picture in Picture
* Digital Zoom with scroll wheel
* Download a snapshot
* One way audio
  
