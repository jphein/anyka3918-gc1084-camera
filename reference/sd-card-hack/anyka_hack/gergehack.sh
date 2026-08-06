#! /bin/sh

#import settings
source /etc/jffs2/gergesettings.txt

cfgfile=/etc/jffs2/anyka_cfg.ini

readline() {
  linetoread=$1
  file=$2
  sed $linetoread'q;d' $file
}

input_wifi_creds() {
  echo 'adding new wifi credentials'
  i=1
  let linecountlimit=$(wc -l < $cfgfile)
  echo "$linecountlimit lines"
  newcredfile=/mnt/anyka_hack/anyka_cfg.ini
  echo -n "" > $newcredfile
  while [ $i -le $linecountlimit ]; do
    line=$(readline $i $cfgfile)
    if [[ "${line:0:4}" == "ssid" ]]; then
      echo "insert $wifi_ssid on line $i"
      echo "ssid = $wifi_ssid">> $newcredfile
    else
      if [[ "${line:0:8}" == "password" ]]; then
        echo "insert $wifi_password on line $i"
        echo "password = $wifi_password">> $newcredfile
      else
        echo "$line">> $newcredfile
      fi
    fi
    let i++
  done
  mv $cfgfile $newcredfile.old
  cp $newcredfile $cfgfile
}

if [[ $run_telnet == 0 ]]; then
  # telnet is started by rc.local or time_zone.sh
  killall telnetd
fi

# check duplicate process
if [[ -f /tmp/exploit.txt ]]; then
  echo 'gergehack is already running'
else
  echo "exploit">/tmp/exploit.txt
  if test -e /dev/mmcblk0p1 ;then
    mount -rw /dev/mmcblk0p1 /mnt
  elif test -e /dev/mmcblk0 ;then
    mount -rw /dev/mmcblk0 /mnt
  fi
  echo -e "  _________________________________\n |                                 |\n |       Gerge Hacked This         |\n |_________________________________|"
  #get new settings from SD card if available
  if [[ -f /mnt/anyka_hack/gergesettings.txt ]]; then
    myresult=$( diff /mnt/anyka_hack/gergesettings.txt /etc/jffs2/gergesettings.txt )
    if [[ ${#myresult} -gt 0 ]]; then
      echo 'install new gergesettings from SD...'
      cp /mnt/anyka_hack/gergesettings.txt /etc/jffs2/gergesettings.txt
      reboot
    fi
  fi
  if [[ -f /mnt/anyka_hack/gergehack.sh ]]; then
    myresult=$( diff /mnt/anyka_hack/gergehack.sh /etc/jffs2/gergehack.sh )
    if [[ ${#myresult} -gt 0 ]]; then
      echo 'install new gergehack from SD...'
      cp /mnt/anyka_hack/gergehack.sh /etc/jffs2/gergehack.sh
      reboot
    fi
  fi
  setssid=$(grep '^ssid' $cfgfile | sed 's/ //g') #get ssid line and remove spaces
  setpass=$(grep '^password' $cfgfile | sed 's/ //g') #get password line and remove spaces
  setssid=${setssid##*=} #keep the part after the =
  setpass=${setpass##*=} #keep the part after the =
  if ! [[ "$setssid" == "$wifi_ssid" ]]; then
    input_wifi_creds
  else
    if ! [[ "$setpass" == "$wifi_password" ]]; then
      input_wifi_creds
    fi
  fi
  echo '*************  start network service   *************'
  /usr/sbin/wifi_manage.sh start
  ntpd -n -N -p $time_source &
  export TZ=$time_zone
  if [[ $run_ftp == 0 ]]; then
    killall tcpsvd
  fi
  #load kernel modules for camera
  insmod $sensor_kern_module
  insmod /usr/modules/akcamera.ko
  insmod /usr/modules/ak_info_dump.ko
  if [[ $run_ptz_daemon == 1 ]]; then
    echo '*************        start ptz         *************'
    if [[ -f /usr/bin/ptz_daemon_dyn ]]; then #use installed version if available
      ptz_daemon_dyn &
    else
      /mnt/anyka_hack/ptz/run_ptz.sh &
    fi
    if [[ $ptz_init_on_boot == 1 ]]; then
      sleep 10
      echo "init_ptz" > /tmp/ptz.daemon
    fi
  fi
  if [[ $run_web_interface == 1 ]]; then
    echo '*************   start web interface    *************'
    if [[ -f /mnt/anyka_hack/web_interface/www/index.html ]]; then #use SD version if available
      /mnt/anyka_hack/web_interface/start_web_interface.sh &
    else
      busybox httpd -p 80 -h /etc/jffs2/www &
    fi
  fi
  if [[ $run_libre_anyka == 1 ]]; then
    echo '*************    start Libre Anyka     *************'
    if [[ -f /usr/bin/ptz_daemon_dyn ]]; then #use installed version if available
      SD_detect=$(mount | grep mmcblk0p1)
      if [[ ${#SD_detect} == 0 ]]; then
        md_record_sec=0 #disable recording if SD card is not mounted
      fi
      libre_anyka_app -w $image_width -h $image_height -m $md_record_sec $extra_args &
    else
      /mnt/anyka_hack/libre_anyka_app/run_libre_anyka_app.sh &
    fi
  fi
  if [[ $run_ipc == 0 ]] && [[ $rootfs_modified == 0 ]]; then
    while [ 1 ]; do
      sleep 30
    done
  fi
fi
