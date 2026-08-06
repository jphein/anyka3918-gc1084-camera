#! /bin/sh

start_app() {
  echo 'restarting libre anyka app...'
  export LD_LIBRARY_PATH=/mnt/anyka_hack/libre_anyka_app/lib
  /mnt/anyka_hack/libre_anyka_app/libre_anyka_app -w $image_width -h $image_height -m $md_record_sec $extra_args
}
#import settings
source /etc/jffs2/gergesettings.txt

#load kernel modules for camera
insmod $sensor_kern_module
insmod /usr/modules/akcamera.ko
insmod /usr/modules/ak_info_dump.ko

start_app
