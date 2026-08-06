# Anyka_ak3918_hacking_journey

My attempt at reverse engineering and making use of a Chinese junk camera

# Summary
This is a simplified README with the latest features, to see the hacking process and more development details go to the [old readme version](https://gitea.raspiweb.com/Gerge/Anyka_ak3918_hacking_journey/src/branch/main/hack_process).

### Working features
- RTSP stream (720p on http://IP:554/vs0)
- BMP snapshot (up to 720p) on port 3000
- JPEG snapshot
- H264 video recording (no mp4 yet, but ffmpeg converts it)
- Audio playback
- Audio recording to mp3
- PTZ movement
- IR shutter
- combined web interface with ptz and IR on port 80
- Motion detection

The camera can now be connected to a video recorder or monitor software such as MotionEye.

# Quick Start SD card hack

This hack runs only when the SD card is inserted leaving the camera unmodified. It is beginner friendly, and requires zero coding/terminal skills. See more [here](https://gitea.raspiweb.com/Gerge/Anyka_ak3918_hacking_journey/src/branch/main/SD_card_contents/Factory)

It is unlikely that this can cause any harm to your camera as the system remains original, but no matter how small the risk it is never zero (unless you have the exact same camera). Try any of these hacks at your own risk.

The SD card hack is a safe way to test compatability with the camera and to see if all features are working.

# Permanent Hack
This part is optional. Make sure everything works with the SD card hack first before you do this.
The SD hack should launch telnet. Connect with `telnet IP` (user: root, no password)

- `[root@anyka /mnt]$ cat /dev/mtdblock4 > /mnt/mtdblock4.bin`
- Compare your rootfs `mtdblock4.bin` on the SD card with the one in this repo (`diff file1 file2`), if it is the same you can just use the prepared `newroot.sqsh4` and skip to updating.
- `unsquashfs mtdblock4.bin` (if not installed `sudo apt install squashfs-tools`) this unpacks to `squashfs-root` folder
- Modify `/etc/init.d/rc.local` to not launch `/usr/sbin/service.sh` and `/usr/sbin/camera.sh`, instead add a line `/etc/jffs2/gergehack.sh`
- `mksquashfs squashfs-root newroot.sqsh4 -b 131072 -comp xz -Xdict-size 100%` and copy that newly packed `newroot.sqsh4` to your SD card
- Install the modified rootfs with `[root@anyka /mnt]$ updater local A=/mnt/newroot.sqsh4`

more detailed process log [here](http://gitea.raspiweb.com/Gerge/Anyka_ak3918_hacking_journey/src/branch/main/newroot/updater.txt)

After the rootfs is modified, power off the camera and take out the SD card. Adjust the settings `rootfs_modified=1`. The settings will be applied using the [update](https://gitea.raspiweb.com/Gerge/Anyka_ak3918_hacking_journey/src/branch/main/SD_card_contents/anyka_hack) of the script from `anyka_hack` folder.

Enjoy a fully private camera.

# Info Links

These are a the most important links here (this is where 99% of the info and resources come from):

https://github.com/helloworld-spec/qiwen/tree/main/anycloud39ev300 (explanation in chinese, good reference)

https://github.com/ricardojlrufino/anyka_v380ipcam_experiments/tree/master (ak_snapshot original)

https://github.com/kuhnchris/IOT-ANYKA-PTZdaemon (ptz daemon original)

https://github.com/MuhammedKalkan/Anyka-Camera-Firmware (Muhammed's RTSP app + library, and more discussions)

https://github.com/e27-camera-hack/E27-Camera-Hack/discussions/1 (discussion where most of this was worked on)


# APPS and Available Functions
This is not a complete list. This is only the best feature list. The [old readme version](https://gitea.raspiweb.com/Gerge/Anyka_ak3918_hacking_journey/src/branch/main/hack_process) was too long, but it has everything not listed here.

### Web Interface

I created a combined web interface using the features from `ptz_daemon`, `libre_anyka_app`, and `busybox httpd`. The webpage is based on [another Chinese camera hack for Goke processors](https://github.com/dc35956/gk7102-hack).

![web_interface](https://gitea.raspiweb.com/Gerge/Anyka_ak3918_hacking_journey/raw/branch/main/Images/web_interface.png)

With the most recent update of webui the interface is a lot nicer and has all settings and features of the camera available without needing to edit config files manually.

![web_interface](https://gitea.raspiweb.com/Gerge/Anyka_ak3918_hacking_journey/raw/branch/main/Images/web_interface_settings.png)

**Note: the WebUI has a login process using md5 password hash and a token, but this is not secure by any means. Do not expose to the internet!**


### Libre Anyka App

This is an app in development aimed to combine most features of the camera and make it small enough to run from flash without the SD card.

Currently contains features:
- JPEG snapshot
- RTSP stream
- Motion detection trigger
- H264 `.str` file recording to SD card (ffmpeg converts this to mp4 in webUI)

Does not have:
- sound (only RTSP stream has sound)

More info about the [app](https://gitea.raspiweb.com/Gerge/Anyka_ak3918_hacking_journey/src/branch/main/SD_card_contents/anyka_hack/libre_anyka_app) and [source](https://gitea.raspiweb.com/Gerge/Anyka_ak3918_hacking_journey/src/branch/main/cross-compile/libre_anyka_app).

**Note: the RTSP stream and snapshots are not protected by password. Do not expose to the internet!**


### SSH
[Dropbear](https://gitea.raspiweb.com/Gerge/Anyka_ak3918_hacking_journey/src/branch/main/SD_card_contents/anyka_hack/dropbear) can give ssh access if telnet is not your preference.


### Play Sound
**Extracted from camera.**

More info about the [app](https://gitea.raspiweb.com/Gerge/Anyka_ak3918_hacking_journey/src/branch/main/SD_card_contents/anyka_hack/ak_adec_demo)


### Record Sound
**mp3 recording works.**

More info about the [app](https://gitea.raspiweb.com/Gerge/Anyka_ak3918_hacking_journey/src/branch/main/SD_card_contents/anyka_hack/aenc_demo) and [source](https://gitea.raspiweb.com/Gerge/Anyka_ak3918_hacking_journey/src/branch/main/cross-compile/aenc_demo).

# Permanent system hack level 2
Make sure everything works with the SD card hack first before you do this.

The permanent hack listed above simply disables the original anyka_ipc and runs the contents of the SD card instead. What if you wish to run the camera without and SD card?

It is possible to fit the essential applications into the system flash, but the `root` and `usr` partitions need significant modification to free up space.

### Root FS modification
in camera `/dev/mtdblock4`

In the root filesystem replace `/bin/busybox` with the one in `web_interface` on the SD card. This will add `httpd` functionality for the webUI (and some other features).
The rootfs must fit within 1MiB (compressed size on flash), so because busybox is now larger I moved `/lib/libstdc++.so.6.0.19` and `/lib/libstdc++.so.6.0.19-gdb.py` to `/usr/lib/` and created symlinks to it instead. After compressing into squashfs again, the [`busyroot.sqsh4`](http://gitea.raspiweb.com/Gerge/Anyka_ak3918_hacking_journey/src/branch/main/newroot) can be installed, but because the `libstdc++` library is still missing some apps will crash.

**TLDR**
- copy [`busyroot.sqsh4`](http://gitea.raspiweb.com/Gerge/Anyka_ak3918_hacking_journey/src/branch/main/newroot) to SD card
- install it with `updater local A=/mnt/busyroot.sqsh4`
- reboot

### User FS modification
in camera `/dev/mtdblock5`

Remove the old `anyka_ipc` and `cloudAPI` from `/usr/bin`, delete all libraries in `/usr/lib` (replace with app libs from SD and the `libstdc++` files moved from rootfs).
From `/usr/modules` delete `atbm603x_wifi_usb.ko`, `g_file_storage.ko`, `g_mass_storage.ko`, `ssv6x5x-sw.bin`, `ssv6x5x.ko`, `udc.ko` and `usbburn.ko`. Optionally the camera sensor modules except the installed sensor can also be deleted (I left them in to keep compatability with other cameras). The `/usr/share/audio_file` can also be removed, `/usr/local/` can be cleared out, finally in `/usr/sbin` keep only the simlinks, `default.script`, `station_connect.sh`, `wifi_driver.sh`, `wifi_manage.sh`, `wifi_run.sh` and `wifi_station.sh`.

Copy `libre_anyka_app` and `ptz_daemon_dyn` to `/usr/bin`.

Finally the [busyusr.sqsh4] partition is now ready to install. After this cleaning, the size is less than half of the original 4.5MiB meaning there is a lot more space to add things later.

**TLDR**
- make sure your camera is compatible (Realtek 8188 wifi, and gc1034, gc1054, gc1084, h62 or h63 sensor)
- copy [`busyusr.sqsh4`](http://gitea.raspiweb.com/Gerge/Anyka_ak3918_hacking_journey/src/branch/main/newroot) to SD card
- install it with `updater local B=/mnt/busyusr.sqsh4`
- reboot

### Setup without SD
After the root and usr partitions are modified with the desired apps, the following steps are needed to get it working:

copy the webpage www folder to `/etc/jffs2/www` for httpd to serve from flash

The latest `gergehack.sh` is already capable of running fully local files, so update if needed and check sensor module settings.

This gives the following functions without SD card running on the camera:
- webUI on port 80
- usual ftp, telnet functions, and ntp time sync
- RTSP stream and snapshots for UI with libre_anyka_app
- ptz movement
