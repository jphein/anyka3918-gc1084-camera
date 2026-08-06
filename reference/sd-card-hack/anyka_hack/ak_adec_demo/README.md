# Play Sound
The camera has `/usr/bin/ak_adec_demo` which allows playing sound files over the built in speaker. There is one small issue, it is waaayyyy too loud (this is probably because volume control fails when running) and makes the plastic casing resonate horribly, so I recommend lowering the volume of the mp3 file, especially if you use the camera indoors.
```
[root@anyka /usr/bin]$ ./ak_adec_demo --help
usage: ./ak_adec_demo [sample rate] [channel num] [type] [audio file path]
eg.: ./ak_adec_demo 8000 2 mp3 /mnt/20161123-153020.mp3
support type: [mp3/amr/aac/g711a/g711u/pcm]
```
1) lower the volume of your chosen file `ffmpeg -i Tutturuu.mp3 -af "volume=0.3" Tutturuu_low.mp3` (I went as low as 0.1)
2) copy the sound file over (and the `ak_adec_demo` if you don't have it) with ftp or just put it on the SD card
3) play the sound `ak_adec_demo 41100 1 mp3 /etc/jffs2/Tutturuu_low.mp3`

Warning: small audio files and executables should fit in the jffs2, but I recommend using SD storage to be safe.
