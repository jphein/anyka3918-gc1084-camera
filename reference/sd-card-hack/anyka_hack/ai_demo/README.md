# Raw PCM Audio
The `ai_demo` app runs without arguments and records a 10s `.pcm` raw audio file to `/mnt/` with the date as filename.

After getting the file from the camera (over FTP or SD) `ffplay -f s16le -ar 8k -ac 1 19700101-023156.pcm` will play the file.
