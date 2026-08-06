#!/bin/sh
#

if [[ -f /etc/jffs2/www/index.html ]]; then
    source /etc/jffs2/www/cgi-bin/header
else
    source /mnt/anyka_hack/web_interface/www/cgi-bin/header
fi
if [[ -f /tmp/token.txt ]] && [[ "$token" == "$(readline 1 /tmp/token.txt)" ]]; then

content=""
if [[ "$undo" == "$file" ]]; then
  mv /mnt/video_encode/delete.bak /mnt/video_encode/$file.h264
  mv /mnt/anyka_hack/web_interface/www/video/delete.bak /mnt/anyka_hack/web_interface/www/video/$file.mp4
  content="$file.mp4 has been restored.<br><br>"
  content="$content<button onclick=\"window.location.href='events?token=$token'\"> OK </button>"
else
  mv /mnt/video_encode/$file.h264 /mnt/video_encode/delete.bak
  mv /mnt/anyka_hack/web_interface/www/video/$file.mp4 /mnt/anyka_hack/web_interface/www/video/delete.bak
  content="$file.mp4 has been deleted.<br><br>"
  content="$content<button onclick=\"window.location.href='del_video.sh?token=$token&file=$file&undo=$file'\">Undo</button>"
  content="$content         <button onclick=\"window.location.href='events?token=$token'\"> OK </button>"
fi

cat <<EOT
<!DOCTYPE html>
<html>
<head>
<title>Camera - WebUI</title>
<link rel="icon" href="data:image/png;base64,iVBORw0KGgoAAAANSUhEUgAAAAEAAAABCAIAAACQd1PeAAAADElEQVQI12P4//8/AAX+Av7czFnnAAAAAElFTkSuQmCC">
<meta name="viewport" content="width=device-width, initial-scale=1">
<link rel="stylesheet" href="/styles.css">
</head>
<body>
<div class="topnav">
  <a href="/cgi-bin/webui?token=$token">Home</a>
  <a href="/cgi-bin/settings?token=$token">Settings</a>
  <a href="/cgi-bin/system?token=$token">System</a>
  <a class="active" href="/cgi-bin/events?token=$token">Events</a>
  <a href="/cgi-bin/login">Exit</a>
</div>

<section>

<div class="card">
<h2>$file.mp4</h2>
$content
<br>
</div>
</section>

</body>
</html>
EOT
else
    if [[ -f /etc/jffs2/www/index.html ]]; then
        source /etc/jffs2/www/cgi-bin/footer
    else
        source /mnt/anyka_hack/web_interface/www/cgi-bin/footer
    fi
fi
