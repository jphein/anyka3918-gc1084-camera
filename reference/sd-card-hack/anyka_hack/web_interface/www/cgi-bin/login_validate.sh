#!/bin/sh
#
readline() {
  linetoread=$1
  file=$2
  sed $linetoread'q;d' $file
}

echo "Content-type: text/html"
echo ""
creds=`echo "$QUERY_STRING" | awk '{split($0,array,"&")} END{print array[1]}' | awk '{split($0,array,"=")} END{print array[2]}'`
if [[ "$(echo $(readline 2 /etc/jffs2/webui.hash)$creds | md5sum )" == "$(readline 1 /etc/jffs2/webui.hash)" ]]; then
random="$(dd if=/dev/urandom bs=100 count=1)"
token=`echo $random$RANDOM | sed 's/[^0-9a-zA-Z]*//g'`;
cat <<EOT
<html>
    <head>
        <meta http-equiv="refresh" content="0; url=/cgi-bin/webui?token=$token" />
    </head>
    <body>
        <a href="/cgi-bin/webui">WebUI</a>
    </body>
</html>
EOT
echo "$token">/tmp/token.txt

else
    if [[ -f /etc/jffs2/www/index.html ]]; then
        source /etc/jffs2/www/cgi-bin/footer
    else
        source /mnt/anyka_hack/web_interface/www/cgi-bin/footer
    fi
fi
