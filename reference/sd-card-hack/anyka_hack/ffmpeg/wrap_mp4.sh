#!/bin/sh

restart_app() {
  source /etc/jffs2/gergesettings.txt
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

stop_app() {
  appnum=$(top -n 1 | grep libre_anyka_app | grep -v 'grep')
  for i in $appnum; do
    kill $i
    break
  done
}

#while [ 1 ]; do
  stop_app
  h264files=$(ls /mnt/video_encode/*.str)

  mkdir -p /mnt/anyka_hack/web_interface/www/video

  for i in $h264files; do
    filename="${i//.str/}"
    filename="${filename##*/}"
    echo $filename
    if [[ ! -f /mnt/anyka_hack/web_interface/www/video/$filename.mp4 ]]; then
      cp /mnt/video_encode/$filename.str /mnt/video_encode/$filename.h264
      /mnt/anyka_hack/ffmpeg/ffmpeg -threads 1 -i "/mnt/video_encode/$filename.h264" -c:v copy -f mp4 "/mnt/anyka_hack/web_interface/www/video/$filename.mp4"
      if [[ -f "/mnt/anyka_hack/web_interface/www/video/$filename.mp4" ]]; then
        rm /mnt/video_encode/$filename.str
        #rm "/mnt/anyka_hack/web_interface/www/video/$filename.mp4"
      fi
    fi
  done
  #restart_app
  #sleep 300
#done
