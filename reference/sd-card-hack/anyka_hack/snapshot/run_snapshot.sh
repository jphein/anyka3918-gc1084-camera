#! /bin/sh

#load kernel modules for camera
insmod /usr/modules/sensor_h63.ko
insmod /usr/modules/akcamera.ko
insmod /usr/modules/ak_info_dump.ko

echo 'restarting snapshot service...'
export LD_LIBRARY_PATH=/mnt/anyka_hack/snapshot/lib
/mnt/anyka_hack/snapshot/ak_snapshot -w 320 -h 180
