# Place in /etc/jffs2/
These are the files that go in `/etc/jffs2/`

# Settings

The `gergesettings.txt` file has new entries to control all parts of the camera. There are comments to explain what each option does.

You can simply place an updated copy of `gergesettings.txt` on the SD card in `anyka_hacks` folder and the camera will copy that file. This applies any new settings on the next start of the camera.

# Wifi
It will also set the new wifi credentials for you if they are different. There will be a copy of the newly created `anyka_cfg` and a backup of the old one with your old credentials copied to the SD card.

Even if you turn off wifi, or set incorrect credentials you can simply correct the settings with the SD card and the camera will connect to LAN on the next boot.

**Some special characters don't work in wifi ssid names and passwords** alpha-numerical strings as well as `.` `_` and `-` are tested and working.
This is not a limitation of the hack, but rather the camera wifi scripts.

# Script version updates
`gergehack.sh` changes a lot during testing, so it is also updated from the `anyka_hacks` folder of the SD if you place a modified version there.
