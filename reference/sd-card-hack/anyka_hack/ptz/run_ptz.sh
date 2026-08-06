#! /bin/sh

start_process()
{
  echo 'starting ptz daemon...'
  export LD_LIBRARY_PATH=/mnt/anyka_hack/ptz/lib
  /mnt/anyka_hack/ptz/ptz_daemon_dyn &
}

start_process
