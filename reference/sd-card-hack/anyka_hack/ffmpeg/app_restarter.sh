#!/bin/sh

source /etc/jffs2/gergesettings.txt

restart_app() {
  if [[ -f /usr/bin/ptz_daemon_dyn ]]; then #use installed version if available
    SD_detect=$(mount | grep mmcblk0p1)
    if [[ ${#SD_detect} == 0 ]]; then
      md_record_sec=0 #disable recording if SD card is not mounted
    fi
    libre_anyka_app -w $image_width -h $image_height -m $md_record_sec $extra_args &
  else
    /mnt/anyka_hack/libre_anyka_app/run_libre_anyka_app.sh &
  fi
}

check_app() {
  appnum=$(top -n 1 | grep libre_anyka_app | grep -v 'grep')
  ffmpegnum=$(top -n 1 | grep wrap_mp4.sh | grep -v 'grep')
  if [[ ${#appnum} == 0 ]] && [[ ${#ffmpegnum} == 0 ]]; then
    restart_app
  fi
}

if [[ $run_libre_anyka == 1 ]]; then
  while [ 1 ]; do
    check_app
    sleep 20
  done
fi
