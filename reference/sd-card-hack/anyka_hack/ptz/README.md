### Movement with PTZ Daemon
*NOTE: `ptz_daemon` needs `cmd_server` to run*

1) open one telnet and run it `./ptz_daemon` (or use gergehack to auto-start it on boot)
2) open second telnet and home the camera axes `echo "init" > /tmp/ptz.daemon`
3) move to whatever position you want `echo "t2p 190 95" > /tmp/ptz.daemon` 190 degree horizontal, 40 vertical (0 is top)
4) quit the daemon if you want with `echo "q" > /tmp/ptz.daemon`, but it can just always run in the background

More instructions to use are on the [original page](https://github.com/kuhnchris/IOT-ANYKA-PTZdaemon)

New features added:
- relative motion 10 degrees (up, down, left, right)

The ptz daemon can now combine relative and absolute motion commands

```
echo "t2p 300 50">/tmp/ptz.daemon
echo "up">/tmp/ptz.daemon
echo "left">/tmp/ptz.daemon
```
This moves the camera to position (300,50) then up 10 degrees to (300,40) then left to (290,40)
