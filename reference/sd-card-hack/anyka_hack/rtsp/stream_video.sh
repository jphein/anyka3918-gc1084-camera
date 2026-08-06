#! /bin/sh

start_process()
{
  echo 'starting rtsp service...'
  export LD_LIBRARY_PATH=/mnt/anyka_hack/rtsp/lib
  /mnt/anyka_hack/rtsp/rtsp &
}

#load kernel modules for camera
insmod /usr/modules/sensor_h63.ko
insmod /usr/modules/akcamera.ko
insmod /usr/modules/ak_info_dump.ko

start_process
