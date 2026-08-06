#! /bin/sh

#load kernel modules for camera
insmod /usr/modules/sensor_h63.ko
insmod /usr/modules/akcamera.ko
insmod /usr/modules/ak_info_dump.ko

export LD_LIBRARY_PATH=/mnt/anyka_hack/ai_demo/lib
/mnt/anyka_hack/ai_demo/ai_demo
