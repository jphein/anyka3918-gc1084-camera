# Anyka_ak3918_hacking_journey

My attempt at reverse engineering and making use of a Chinese junk camera

# Summary
- Original firmware dump
- UART header gives debug info, and backup console if wifi fails
- Created some scripts that kill the main app and handle wifi connection instead of it
- I got a permanent exploit (ftp, telnet, ssh, password protected)
- The camera can now operate in isolation from the internet
- Able to modify the file-system safely (truely permanent)

### Working features
- RTSP stream (720p on http://IP:554/vs0)
- BMP snapshot (up to 720p) on port 3000
- JPEG snapshot
- H264 video recording (no mp4 yet)
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

# Permanent Hack
This part is optional.
The SD hack should launch telnet. Connect with `telnet IP` (user: root, no password)

- `[root@anyka /mnt]$ cat /dev/mtdblock4 > /mnt/mtdblock4.bin`
- Compare your rootfs `mtdblock4.bin` on the SD card with the one in this repo (`diff file1 file2`), if it is the same you can just use the prepared `newroot.sqsh4` and skip to updating.
- `unsquashfs mtdblock4.bin` (if not installed `sudo apt install squashfs-tools`) this unpacks to `squashfs-root` folder
- Modify `/etc/init.d/rc.local` to not launch `/usr/sbin/service.sh` and `/usr/sbin/camera.sh`, instead add a line `/etc/jffs2/gergehack.sh`
- `mksquashfs squashfs-root newroot.sqsh4 -b 131072 -comp xz -Xdict-size 100%` and copy that newly packed `newroot.sqsh4` to your SD card
- Install the modified rootfs with `[root@anyka /mnt]$ updater local A=/mnt/newroot.sqsh4`

more detailed process log [here](http://gitea.raspiweb.com/Gerge/Anyka_ak3918_hacking_journey/src/branch/main/newroot/updater.txt)

After the rootfs is modified, power off the camera and take out the SD card. `Factory` folder can be deleted, the new place for `gergesettings.txt` is in `anyka_hack`. Adjust the settings `rootfs_modified=1`. The settings will be applied using the [update](https://gitea.raspiweb.com/Gerge/Anyka_ak3918_hacking_journey/src/branch/main/exploit_scripts) of the script from `anyka_hack` folder.

Enjoy a fully private camera and enable the apps you want.

**The rest of this repository was written during development and may not be up to date according to the latest user-friendly hack solution.**

# Info Links

These are a the most important links here (this is where 99% of the info and resources come from):

https://github.com/helloworld-spec/qiwen/tree/main/anycloud39ev300 (explanation in chinese, good reference)

https://github.com/ricardojlrufino/anyka_v380ipcam_experiments/tree/master (ak_snapshot original)

https://github.com/MuhammedKalkan/Anyka-Camera-Firmware (Muhammed's RTSP app + library, and more discussions)

https://github.com/e27-camera-hack/E27-Camera-Hack/discussions/1 (discussion where most of this was worked on)

## Cool info:

https://github.com/JayGoldberg/anyka-cams

blogs/articles with cool info:

https://ricardojlrufino.wordpress.com/2022/02/14/hack-ipcam-anyka-teardown-and-root-access/

https://ricardojlrufino.wordpress.com/2022/02/15/hack-ipcam-anyka-booting-rootfs-from-sdcard/
...(more pages)

https://lucasteske.dev/2019/06/reverse-engineering-cheap-chinese-vrcam-protocol/

https://github.com/c0decave/yoosee-ipc/tree/main

https://boschko.ca/hardware_hacking_yo_male_fertility/ (weird, but ok)

Discussion:

https://github.com/e27-camera-hack/E27-Camera-Hack/discussions/1 (discussion where most of this was worked on)

https://github.com/alienatedsec/yi-hack-v5/discussions/236

https://github.com/EliasKotlyar/Xiaomi-Dafang-Hacks/issues/1672

## Toolchain

https://github.com/ricardojlrufino/arm-anykav200-crosstool

https://github.com/Lamobo/Lamobo-D1/tree/master (waaayyy too outdated)

## Source

https://github.com/burlizzi/anyka/tree/master
or https://github.com/jingwenyi/SmartCamera/tree/master (seems to be the same at a glance)

https://github.com/grangerecords/anyka/tree/master

https://github.com/mucephi/anyka_ak3918_kernel

https://github.com/Nemobi/Anyka/tree/main

https://github.com/burlizzi/qiwen/tree/main

slightly newer SOC version (not very useful for me):

https://github.com/helloworld-spec/qiwen/tree/main/anycloud39ev300 (explanation in chinese, good reference)

https://github.com/Nemobi/ak3918ev300v18

## Apps and mods

https://github.com/ThatUsernameAlreadyExist/anyka-v4l2rtspserver
and https://github.com/ThatUsernameAlreadyExist/anyka-software (very recent and promising)

(v4lrtspserver, live555, lighttpd)

https://github.com/ricardojlrufino/anyka_v380ipcam_experiments/tree/master (ak_snapshot original)

https://github.com/Lamobo/Lamobo-D1/tree/master

https://github.com/kuhnchris/IOT-ANYKA-PTZdaemon

https://blog.caller.xyz/v380-ipcam-firmware-patching/

https://github.com/MuhammedKalkan/Anyka-Camera-Firmware (RTSP)

## Other resources

https://www.linux4sam.org/bin/view/Linux4SAM/UsingIsi?skin=print.myskin

https://blog.51cto.com/chenguang/2379530

# Step Zero, Flash backup
(never start hacking until you have a safe recovery plan in case of a brick)

After opening the camera box, I got to work. Without even powering the camera on, just straight away opened it and removed the flash chip. [pictures of the insides](https://gitea.raspiweb.com/Gerge/Anyka_ak3918_hacking_journey/src/branch/main/Images)

Using an arduino Uno and a home made flash chip holder (fabricated from plastic card and some pin headers) I cloned the flash to an image file. Follow this guide: https://kaanlabs.com/bios-flashing-with-an-arduino-uno/

NOTE: the Arduino Uno is 5V logic, so a resistor array is needed as a voltage divider

The dump of the camera may be available in the future (should not contain personal info as it was made before first power on, but it still has a unique ID for the cloud). When I have completely made the camera independent of the chinese cloud servers, then the dump will be public. (questions: <admin@raspiweb.com>)

# Step One, UART
Soldered a pin header to the RX0 TX0 GND points next to the wifi chip. For UART converter I am using and ESP8266 (wemos D1 mini) arduino compatible board (CH340 serial chip). It is just a matter of bridging the reset pin to GND and connecting up the UART bus (`RX -> RXD, TX -> TXD, GND -> GND`) Note GND must be correct, for RT and TX just swap the wires and see what happens, there is no harm.

NOTE: the esp8266 is 3.3v logic so direct connection is fine

For software to connect anything works:
- Arduino IDE serial monitor baud: 115200 (line ending "carriage return")
- `minicom -b 115200 -D /dev/ttyUSB0` (you can exit with ctrl-A then q)
- `stty 115200 -F /dev/ttyUSB0 raw -echo` and `cat /dev/ttyUSB0` (not interactive) BONUS: it is colourful, this is my preffered way to view log

This potentially gives access to U-Boot, but in my case boot delay is zero, so could not get in. This port provides essential information about the boot process and helps with debugging when errors are reported here. Also, when the boot process is complete and messages calm down, it can be used as a backup console (if for example wifi fails, or got locked out for some reason).

# First power on
Not knowing much about the camera (have not analysed the flash dump yet), just set up the camera as usual with the broken english translated instructions. Now looking back at it, this is not necessary as FTP access should still work in AP mode and from then onward the wifi password (`/etc/jffs2/anyka_cfg.ini`) and exploit scripts can be inserted.

# Getting In
Based on the general info online there are 3 ways in
1) through UART
2) through open telnet port
3) through open FTP port `ftp ftp://root:@192.168.10.191`


By default the ports on the camera are:
```
$> nmap -p 1-10000 192.168.10.191
Starting Nmap 7.80 ( https://nmap.org ) at 2023-07-18 13:00 CEST
Nmap scan report for 192.168.10.191
Host is up (0.024s latency).
Not shown: 9996 closed ports
PORT     STATE SERVICE
21/tcp   open  ftp
6789/tcp open  ibm-db2-admin
6790/tcp open  hnmp

Nmap done: 1 IP address (1 host up) scanned in 5.03 seconds
```

-The UART output with the app running is cluttered with messages (usable if anyka_ipc is not running)
-Telnet port is not open

In my case FTP port was the convenient way in. Laid with red carpet, doors wide open, no password. It just happens that the rw `/etc/jffs2/` folder has `time_zone.sh` which is a prime target for code execution.
The time_zone.sh script is overwritten each time the app finds the server and syncs time. So some simple bash scripting to create a daemon that repairs the exploit when removed solves that. Additionally, first install of the exploit scripts needs to set execute permission for the new .sh files (this is done by the default `time_zone.sh` provided).

# Permanent back door & WiFi setup
It is possible to set up the wifi credentials without ever downloading and registering for the sketchy apps that these cameras come with. When the camera is not able to connect on first setup it will enter access point (AP) mode. You can connect to this AP wifi network and get FTP access.

1) The camera will start making sounds and wait for a QR code from the app
2) Instead of getting the app just connect to the AP, open ftp terminal from the scripts folder `ftp ftp://root:@192.168.10.1`
3) `cd /etc/jffs2` and then see files with `ls` there should be a file `anyka_cfg.ini`
4) `mget anyka_cfg.ini` to pull the file to your computer
5) fill in your wifi credentials

The file should have something like this (somewhere close to the top) NOTE: some special characters don't work in SSID and passowrd

```
[wireless]
ssid                    = MyWifi
mode                    = Infra
security                = 3
password                = mywifipassword
running                 = softap
```

6) `mput time_zone.sh`, `mput gergesettings.txt`, `mput gergehack.sh`, and `mput gergedaemeon.sh` (also `mput anyka_cfg.ini` if you need to set up wifi)
4) `quit`

reboot the camera, then telnet will be open every time. Connect with: `telnet 192.168.10.191` (root, no password)

# Closing the main app
The main app connects to external Chinese servers and is garbage in general, worst of all the camera refuses to work if it is blocked from accessing the internet. With the goal of using RTSP instead, there is no need for it to run at all. The exploit scripts take care of that, stopping the daemon's watchdog process allows killing the anyka_ipc app.

At this point we pretty much have a plain Linux base running with most of the crap removed. The exploit script also launches the necessary network connection scripts which was previously done by the app. The camera is much safer and can finally operate on an isolated VLAN without internet access (as all IOT devices should be).

# Security
To have a secure login password instead of the default blank we can modify the shadow and passwd files in `/etc/jffs2/`. These files are simlinked to `/etc/` meaning any changes can be written in `jffs2` will apply system-wide without needing to modify the root filesystem.

1) `mkpasswd --method=md5` (if you need, install with `sudo apt install whois`)
2) specify the password you want
3) copy the hash given into shadow file `root:<myhash>:`
4) make sure `passwd` file has `root:x:` so that the password is actually used (if the x is missing then the password is ignored)
5) TEST login from a different terminal before you log out!

# APPS and Available Functions
All the functions listed here can be enabled in gergesettings.txt and will be launched at boot.

### SSH
[Dropbear](https://gitea.raspiweb.com/Gerge/Anyka_ak3918_hacking_journey/src/branch/main/SD_card_contents/anyka_hack/dropbear) can give ssh access if telnet is not your preference.

### Snapshot

More info about the [app](https://gitea.raspiweb.com/Gerge/Anyka_ak3918_hacking_journey/src/branch/main/SD_card_contents/anyka_hack/snapshot) and [source](https://gitea.raspiweb.com/Gerge/Anyka_ak3918_hacking_journey/src/branch/main/cross-compile/anyka_v380ipcam_experiments/apps/ak_snapshot).

![ak_snapshot](https://gitea.raspiweb.com/Gerge/Anyka_ak3918_hacking_journey/raw/branch/main/Images/ak_snapshot.png)

**JPEG hardware encoded snapshot**

More info about the [app](https://gitea.raspiweb.com/Gerge/Anyka_ak3918_hacking_journey/src/branch/main/SD_card_contents/anyka_hack/jpeg_snapshot) and [source](https://gitea.raspiweb.com/Gerge/Anyka_ak3918_hacking_journey/src/branch/main/cross-compile/jpeg_snapshot).

### Local Video Recording
*work in progress*

The `venc-demo` shows the H264 encoder working.

### RTSP Video Stream
Many thanks to [MuhammedKalkan](https://github.com/MuhammedKalkan/Anyka-Camera-Firmware). This is now working with 720p video and automatic IR.

More info about the [app](https://gitea.raspiweb.com/Gerge/Anyka_ak3918_hacking_journey/src/branch/main/SD_card_contents/anyka_hack/rtsp) and [source](https://gitea.raspiweb.com/Gerge/Anyka_ak3918_hacking_journey/src/branch/main/cross-compile/rtsp).

### Play Sound
**Extracted from camera.**

More info about the [app](https://gitea.raspiweb.com/Gerge/Anyka_ak3918_hacking_journey/src/branch/main/SD_card_contents/anyka_hack/ak_adec_demo)

### Record Sound
**mp3 recording works.**

More info about the [app](https://gitea.raspiweb.com/Gerge/Anyka_ak3918_hacking_journey/src/branch/main/SD_card_contents/anyka_hack/aenc_demo) and [source](https://gitea.raspiweb.com/Gerge/Anyka_ak3918_hacking_journey/src/branch/main/cross-compile/aenc_demo).

**Raw PCM audio without encoding**

More info about the [app](https://gitea.raspiweb.com/Gerge/Anyka_ak3918_hacking_journey/src/branch/main/SD_card_contents/anyka_hack/ai_demo) and [source](https://gitea.raspiweb.com/Gerge/Anyka_ak3918_hacking_journey/src/branch/main/cross-compile/ai_demo).

### Motion detection

More info about the [app](https://gitea.raspiweb.com/Gerge/Anyka_ak3918_hacking_journey/src/branch/main/SD_card_contents/anyka_hack/md_demo) and [source](https://gitea.raspiweb.com/Gerge/Anyka_ak3918_hacking_journey/src/branch/main/cross-compile/md_demo).

### Movement with PTZ Daemon
**Fully functional motion and IR.**

More info about the [app](https://gitea.raspiweb.com/Gerge/Anyka_ak3918_hacking_journey/src/branch/main/SD_card_contents/anyka_hack/ptz) and [source](https://gitea.raspiweb.com/Gerge/Anyka_ak3918_hacking_journey/src/branch/main/cross-compile/IOT-ANYKA-PTZdaemon).

### IR filter
The infra-red filter can be turned on/off in two ways. Using the `ak_drv_ir_demo` as described [here](http://gitea.raspiweb.com/Gerge/Anyka_ak3918_hacking_journey/src/branch/main/IR_shutter.txt), or using the `ptz_daemon` with command `irinit` then `irsetircut 0` or `irsetircut 1` (use with echo as above). Both of these require that the `cmd_serverd` is running, so make sure to set `run_cmd_server=1` in `gergesettings.txt`. For some reason the IR feature is not even mentioned in the original ptz repo documentation, I found it by reading the source.

### Web Interface

I created a combined web interface using the features from `ptz_daemon`, `ak_snapshot`, and `busybox httpd`. The webpage is based on [another Chinese camera hack for Goke processors](https://github.com/dc35956/gk7102-hack).

![web_interface](https://gitea.raspiweb.com/Gerge/Anyka_ak3918_hacking_journey/raw/branch/main/Images/web_interface.png)

### Libre Anyka App

This is an app in development aimed to combine the features from the above components and make it small enough to run from flash without the SD card.

Currently contains features:
- JPEG snapshot
- RTSP stream
- Motion detection trigger
- H264 `.str` file recording to SD card
- Web interface coming soon...

More info about the [app](https://gitea.raspiweb.com/Gerge/Anyka_ak3918_hacking_journey/src/branch/main/SD_card_contents/anyka_hack/libre_anyka_app) and [source](https://gitea.raspiweb.com/Gerge/Anyka_ak3918_hacking_journey/src/branch/main/cross-compile/libre_anyka_app).

# How to compile for AK3918?

More info on compiling [here](https://gitea.raspiweb.com/Gerge/Anyka_ak3918_hacking_journey/src/branch/main/cross-compile)

There is also a dirty way described [here](https://gitea.raspiweb.com/Gerge/Anyka_ak3918_hacking_journey/src/branch/main/cross-compile/IOT-ANYKA-PTZdaemon), but this barely works and is not recommended.

# Modify file-system
The camera runs on squashfs, so it will be read-only. However, we can create a new squashfs filesystem with modified files and overwrite the current one with `updater`.

This process works for rootfs (`mtdblock4`) and usrfs (`mtdblock5`). `mtdblock6` is jffs2, which you can edit anyway.

1) `[root@anyka /mnt]$ cat /dev/mtdblock4 > /mnt/mtdblock4.bin`

compare your rootfs `mtdblock4.bin` with the one in this repo (diff file1 file2), if it is the same you can just use the prepared `newroot.sqsh4` and skip to step 4.

2) `unsquashfs mtdblock4.bin` (if not installed `sudo apt install squashfs-tools`)

modify `/etc/init.d/rc.local` to not launch `/usr/sbin/service.sh` and `/usr/sbin/camera.sh`

3) `mksquashfs squashfs-root newroot.sqsh4 -b 131072 -comp xz -Xdict-size 100%`
4) `[root@anyka /mnt]$ updater local A=/mnt/newroot.sqsh4`

more detailed process [here](http://gitea.raspiweb.com/Gerge/Anyka_ak3918_hacking_journey/src/branch/main/newroot/updater.txt)

# How to move files to and from the camera (for beginners)

There are two ways to move files between the computer and camera.

1) using the SD card
2) over FTP

Using the SD card to transfer files has many drawbacks.
- Every time you remove the SD card the camera needs to be powered off (to make sure the SD card is not corrupted and that apps are not using it)
- Constantly move the card between the camera and computer every time you make a change (lot of effort for small files, not ideal for testing)
- Only one device has access to the files at a time

The easy way I recommend is using FTP.
- You can share files with multiple computers at the same time (I use a separate computer for cross-compiling)
- You can open the ftp share in a folder using Nautilus or Dolphin and edit files on the camera.
- You can send or grab files quickly from terminal
- Files/apps can be updated quickly (compile, stop the app on camera, replace app, start new version of app) while other apps are still using the SD card

# How to use vi (for beginners)
`vi` is a lightweight vim text editor that is part of busybox on the camera. (this avoids having to copy files over FTP or SD card every time you want to edit)
1) open the file `vi myfile.txt`
2) navigate with arrow keys and press `I` for insert edit mode
3) edit the file as you like
4) press `esc` to exit insert mode
5) type `:wq` to write changes and quit, `:q` to quit, `:q!` quit discarding changes

# Little warning (for beginners)

`killall busybox`... causes a reboot. If you are dumb like I am and put that into startup scripts, then it will reboot forever. The way to fix it (without reflashing the stock flash dump) is connect UART and spam ctrl+C when linux loads, this will exit the startup script and the file can be fixed over UART console with `vi`.

# Boot Process Map
The boot process looks something like this:
(with modified rootfs `camera.sh`, `service.sh` and `anyka_ipc.sh` can be left out)
```
  ________________________
 |                        |
 |         U-Boot         | (interrupt delay is 0, can't get in)
 |________________________|
              |
              V
  ________________________
 |                        |
 |         Kernel         | (Kernel command line: console=ttySAK0,115200n8 root=/dev/mtdblock4
 |________________________| rootfstype=squashfs init=/sbin/init mem=64M memsize=64M)
              |
              V
  ________________________
 |          init          |
 |     /etc/init.d/rcS    | (mounts filesystem, sets hostname)
 |________________________|
              |
              V
  ________________________
 |                        |
 |  /etc/init.d/rc.local  | (mount squashfs, mount jffs2, ftp server, ramdisk)
 |________________________|
              |
              V
  ________________________
 |                        |
 |  /usr/sbin/camera.sh   | (load modules)
 |________________________|
              |
              V
  ________________________
 |                        |
 |  /usr/sbin/service.sh  | (cmd_serverd, check sd card for factory tests and debug modes)
 |________________________| [NOTE: this check of the SD card is also a potential code execution entry point]
              |
              V
  _____________________________
 |                             |
 |/usr/sbin/anyka_ipc.sh start | (this process loads /etc/jffs2/time_zone.sh before calling the /bin/anyka_ipc app)
 |_____________________________| (anyka_ipc gets terminated along with the watchdog)
                |
                V
  _____________________________
 |                             |
 |   /etc/jffs2/time_zone.sh   | (with the expoit lines present: launch telnet, call gergehack.sh)
 |_____________________________|
                |
                V
  _____________________________
 |                             | [kill the watchdog and anyka_ipc]
 |   /etc/jffs2/gergehack.sh   | (launch gergedaemeon.sh, launch wifi_manage.sh, launch snapshot_daemon.sh)
 |_____________________________|
                |__________________________________________________________________________
                V                                      |                                   |
  ____________________________________                 |                                   |
 |                                    |                |                                   |
 | /mnt/anyka_hack/snapshot_daemon.sh |                |                                   |
 |____________________________________|                V                                   |
     (restart snapshot if crashed)        ____________________________                     |
                   |                     |                            |                    |
                   |                     | /etc/jffs2/gergedaemeon.sh |                    |
                   |                     |____________________________|                    V
                   V                         (fix exploit if needed)       ________________________________
  ______________________________________                                  |                                |
 |                                      |                                 | /usr/sbin/wifi_manage.sh start |
 | /mnt/anyka_hack/snapshot/ak_snapshot |                                 |________________________________|
 |______________________________________|                       (takes care of wifi connection and network setup)
             (port 3000)
```
