# Web UI and HTTP API

The hacked camera runs a small web UI on port 80. It is not documented upstream, so this page
is the reference: every endpoint, every parameter, and an honest account of its security.

Everything here was read out of the CGI sources in
[`reference/sd-card-hack/anyka_hack/web_interface/www/cgi-bin/`](../reference/sd-card-hack/anyka_hack/web_interface/www/cgi-bin/)
and then verified against a live camera on **2026-08-05**. All twelve deployed CGI files
md5-match the vendored copies, so the sources in this repo are authoritative.

> ⚠️ **Read [Security](#security-the-auth-is-cosmetic) before exposing port 80 anywhere.**
> The web UI has an unauthenticated remote root command execution bug. It is safe only on a
> segregated VLAN.

## How it is served

```
busybox httpd -p 80 -h /mnt/anyka_hack/web_interface/www
```

Started by `anyka_hack/web_interface/start_web_interface.sh`, which `gergehack.sh` launches when
`run_web_interface=1` in `gergesettings.txt`.

**The document root is on the SD card**, so on this camera the web UI dies with the card.
That is not inherent, though — `start_web_interface.sh` mirrors `cgi-bin/`, `styles.css` and
`index.html` into `/etc/jffs2/www/` when `rootfs_modified=1`, and every CGI script prefers the
flash copy when `/etc/jffs2/www/index.html` exists.

> ⚠️ Do not set `rootfs_modified=1` expecting a card-less web UI on this camera. `/etc/jffs2`
> is a 64 KB partition with **8.0 KB free**, and `cgi-bin/` is ~25 KB. The copy cannot fit, and
> the flag has other effects besides (see [sd-card.md](sd-card.md)). This camera runs
> `rootfs_modified=0` and has no `/etc/jffs2/www`.

`start_web_interface.sh` also launches `/mnt/anyka_hack/ffmpeg/app_restarter.sh` — the watchdog
that keeps `libre_anyka_app` running. It **is** vendored here, at
[`reference/sd-card-hack/anyka_hack/ffmpeg/`](../reference/sd-card-hack/anyka_hack/ffmpeg/);
only the 37 MB `ffmpeg` binary itself is excluded, so the Events page's "Run FFMPEG" button is
the sole casualty on a repo-built card. Its restart policy is documented in
[troubleshooting.md](troubleshooting.md#the-watchdog-only-catches-death-not-hangs).

## Getting in

The entry chain is:

```
http://<ip>/               ->  /cgi-bin/webui   (no token)
/cgi-bin/webui             ->  /cgi-bin/login   (token missing/invalid)
/cgi-bin/login             ->  password form
/cgi-bin/login_validate.sh ->  /cgi-bin/webui?token=<token>
```

> Both hops are **HTML `<meta http-equiv="refresh">`, not HTTP 3xx**. The responses are
> `200 OK`. `curl -L` will not follow them — parse the body or go straight to the CGI path.

### The password

`/cgi-bin/login` creates `/etc/jffs2/webui.hash` on first run if it does not exist:

```sh
salt=$RANDOM
echo $salt'webui' | md5sum >/etc/jffs2/webui.hash   # line 1: md5 of <salt><password>
echo $salt>>/etc/jffs2/webui.hash                   # line 2: the salt
```

So the **default password is `webui`**, and the login page prints that hint itself.

| | |
|---|---|
| File | `/etc/jffs2/webui.hash` (persists in flash across reboots and SD swaps) |
| Line 1 | `md5sum` of `<salt><password>` — stored in full `md5sum` output form, i.e. `<hash>  -` |
| Line 2 | the salt |

Change it from **Settings → WebUI Password**, which posts to `/cgi-bin/pwd_change`. The new
password must be **longer than 3 characters** and must match the confirmation field, otherwise
the page reports "Passwords too short or do not match!" and changes nothing.

Two things worth knowing about the hashing:

* **The initial salt is weak.** First-run creation uses bare `$RANDOM`, which is 0–32767 — about
  15 bits. `pwd_change` is much better, seeding from `dd if=/dev/urandom bs=30 count=1` plus
  `$RANDOM`. A `webui.hash` whose second line is 5 digits or fewer was created by `login` and
  still carries the weak salt. Changing the password once fixes it.
* **It is unsalted-fast MD5 either way.** No iteration, no key stretching.

> ⚠️ **Stick to letters and digits in the WebUI password.** `pwd_change` receives the password
> through `header`, which URL-**decodes** it, but `login_validate.sh` does **not** decode. A
> password containing anything a browser percent-encodes (space, `&`, `+`, `#`, `%`, most
> punctuation) will hash one way when set and another way when checked, and you will lock
> yourself out of the UI. Recovery is `rm /etc/jffs2/webui.hash` over telnet, which restores the
> `webui` default on the next visit to the login page.

### The token

`GET /cgi-bin/login_validate.sh?<anyparam>=<password>`

The parameter **name is irrelevant** — the script takes the first `&`-separated element and
keeps whatever follows the first `=`:

```sh
creds=`echo "$QUERY_STRING" | awk '{split($0,array,"&")} END{print array[1]}' \
                            | awk '{split($0,array,"=")} END{print array[2]}'`
```

The browser form uses `webuipassword=`, but `?x=webui` works identically.

On success it mints a token from 100 bytes of `/dev/urandom` plus `$RANDOM`, stripped to
alphanumerics (~21–25 characters in practice), redirects to `/cgi-bin/webui?token=<token>`, and
writes it to **`/tmp/token.txt`**. On failure it serves the login redirect.

| Property | Behaviour |
|---|---|
| Storage | `/tmp/token.txt`, mode `0644`, single line |
| Validation | `$token` must equal **line 1** of `/tmp/token.txt`. An arbitrary token is rejected — verified. |
| Concurrency | **One token at a time.** A new login overwrites the file and silently invalidates every other session. |
| Expiry | None. Valid until overwritten or the camera reboots. |
| Lifetime | `/tmp` is tmpfs, so the token is lost on reboot and the next login mints a new one. |

With root telnet you can skip the login entirely and just read the current token:

```sh
cat /tmp/token.txt
```

## Security: the auth is cosmetic

> ✅ **FIXED — but only on cards written since 2026-08-06, and only if you applied it.**
> [`reference/patches/cgi-bin-header.hardened`](../reference/patches/) closes this, and
> [`tools/write-sd-card.sh`](../tools/write-sd-card.sh) installs it. **Any camera running an
> older card is still fully exploitable.** The section below describes the hole as it exists
> unpatched — read it as the reason the fix matters, and as what to expect on an un-updated unit.
> Jump to [the fix](#the-fix).

> ⚠️⚠️ **Unauthenticated remote command execution as root.** Anything that can open a TCP
> connection to port 80 fully owns this camera. There is no exploit chain and no credential
> required — one GET is enough.

Every authenticated CGI script begins by sourcing `cgi-bin/header`, and `header` ends with:

```sh
for i in $QUERY_STRING; do
  eval $i
done
```

That is how the scripts get `$token`, `$command`, `$file` and friends as shell variables — and
it evaluates the query string as shell code **before the token check runs**. `header` is sourced
at the top of `webui`, `system`, `settings`, `settings_submit.sh`, `events`, `video`,
`del_video.sh` and `pwd_change`, so all eight are affected.

Verified live against 192.168.1.20 (read-only commands only):

```console
$ printf 'GET /cgi-bin/webui?a=1;id HTTP/1.0\r\nHost: x\r\n\r\n' | nc <ip> 80
HTTP/1.1 200 OK
uid=0(root) gid=0(root)
Content-type: text/html
```

`header` URL-decodes before the `eval`, and the surrounding `for i in $QUERY_STRING` splits on
whitespace, so a payload containing a decoded space gets chopped into separate `eval`s. `${IFS}`
sidesteps that:

```console
$ printf 'GET /cgi-bin/webui?a=1;echo${IFS}HELLO HTTP/1.0\r\nHost: x\r\n\r\n' | nc <ip> 80
HTTP/1.1 200 OK
HELLO
```

Which makes the token check pointless, because the token is readable without it:

```console
$ printf 'GET /cgi-bin/system?a=1;cat${IFS}/tmp/token.txt HTTP/1.0\r\nHost: x\r\n\r\n' | nc <ip> 80
HTTP/1.1 200 OK
xXxxXXX0xxXX0xXXxXXXX          <- the live session token
```

From there every "authenticated" endpoint is available, including `system?command=reboot`.

Injected output lands **before** the `Content-type` header, which is why it appears between the
status line and the headers rather than in the page body.

### The fix

The parser is replaced so that it accepts **lowercase identifier keys only** and assigns values
**by reference**, so a value's contents are never re-parsed as shell:

```sh
for i in $QUERY_STRING; do
  key="${i%%=*}"; val="${i#*=}"
  case "$key" in ''|*[!a-z0-9_]*) continue ;; [0-9]*) continue ;; esac
  case "$key" in path|env|ifs|query_string|http_*|remote_*|ld_*) continue ;; esac
  eval "$key=\$val"
done
```

It **cannot** be fixed by moving the token check earlier, because `$token` is produced *by* that
eval. The lowercase rule is derived from the device, not guessed: every legitimate parameter is
lowercase — all 17 `gergesettings.txt` keys and all five UI params — while every dangerous
shell/loader variable is uppercase by convention (`PATH`, `IFS`, `LD_*`, `ENV`, `BASH_ENV`,
`CDPATH`). Dynamic keys still work, which `settings_submit.sh` requires.

**Verified by demonstrating the hole and then its absence on the live camera** — an
unauthenticated `GET` created a root-owned `/tmp/rce_probe`; afterwards the identical payloads
(backtick, `$()`, embedded, and `?PATH=/tmp/evil&IFS=X`) left no file. Regression-checked: UI
login works, `settings_submit.sh` did not corrupt `gergesettings.txt`, and the HA path never
sourced `header` at all.

> **A harness pass was explicitly not accepted as evidence.** An earlier version of the fix passed
> one while still permitting `PATH`/`IFS`/`LD_PRELOAD` hijacking — those *are* valid identifiers,
> so checking identifier-ness alone is not enough. On this device the only acceptable proof is the
> exploit failing against the real target.

Provenance, md5s and a locale hardening note are in
[`reference/patches/README.md`](../reference/patches/README.md).

### Honest summary of the posture

| | |
|---|---|
| Transport | Plain HTTP. No TLS anywhere on the device. |
| Password | MD5, single round, weak first-run salt, default `webui` printed on the login page. |
| Token | Random and genuinely unguessable — but readable pre-auth, so it does not matter. |
| Session | No expiry, single-slot, plaintext in `/tmp`. |
| Worst case | Pre-auth root RCE from a single unauthenticated GET. |

**This is fine on a cloud-blocked, isolated camera VLAN with no untrusted clients on it. It is
not fine anywhere else.** Do not port-forward it, do not put it on a flat home LAN with guest
devices, and do not expose it to a VPN population you do not fully trust. If you cannot
segregate it, set `run_web_interface=0` and drive PTZ over telnet instead — see
[ptz.md](ptz.md).

The same reasoning applies to the other listeners; see [Other listening ports](#other-listening-ports).

## Endpoint reference

All endpoints are `GET`. All authenticated ones require `token=<t>` matching `/tmp/token.txt`,
and all of them redirect to `/cgi-bin/login` when it does not match.

| Endpoint | Auth | Parameters | Purpose |
|---|---|---|---|
| `/` | no | — | `index.html`, meta-refresh to `cgi-bin/webui` |
| `/cgi-bin/login` | no | — | Password form. Creates `webui.hash` on first run. |
| `/cgi-bin/login_validate.sh` | no | *first param's value* = password | Mints the token, writes `/tmp/token.txt` |
| `/cgi-bin/webui` | yes | `token`, `command` | Home page: live preview, PTZ pad, endpoint list |
| `/cgi-bin/settings` | yes | `token` | Settings forms |
| `/cgi-bin/settings_submit.sh` | yes | `token` + any `gergesettings.txt` key | Writes settings, prompts for reboot |
| `/cgi-bin/pwd_change` | yes | `token`, `webui_password`, `webui_conf_password` | Change WebUI password |
| `/cgi-bin/system` | yes | `token`, `command=reboot` | Reboot; shows date, IP, uptime, storage |
| `/cgi-bin/events` | yes | `token` | List recorded motion clips |
| `/cgi-bin/video` | yes | `token`, `file=<name>` or `scan=true` | Play a clip, or run ffmpeg to wrap new ones |
| `/cgi-bin/del_video.sh` | yes | `token`, `file=<name>`, `undo=<name>` | Delete / restore a clip |
| `/cgi-bin/ctl` | yes | `token`, `command=<cmd>` | **Not upstream — added by this project.** Fast, whitelisted control endpoint. [See below](#cgi-binctl--our-fast-control-endpoint). |

`header` and `footer` are sourced fragments, not endpoints.

### Camera control — `/cgi-bin/webui`

```
GET /cgi-bin/webui?token=<t>&command=<cmd>
```

Each command writes one line to the `/tmp/ptz.daemon` FIFO. That is the whole implementation —
the web UI is a thin shell over the PTZ daemon, so anything here can equally be done over
telnet, and the FIFO accepts commands the web UI never exposes (see [ptz.md](ptz.md)).

| `command=` | Written to `/tmp/ptz.daemon` | Effect |
|---|---|---|
| `ptzinit` | `init_ptz` | Home both axes. **Required before any move.** |
| `ptzu` | `up` | Tilt up 10° |
| `ptzd` | `down` | Tilt down 10° |
| `ptzl` | `left` | Pan left 10° |
| `ptzr` | `right` | Pan right 10° |
| `ptzlu` | `left_up` | Diagonal |
| `ptzru` | `right_up` | Diagonal |
| `ptzld` | `left_down` | Diagonal |
| `ptzrd` | `right_down` | Diagonal |
| `irinit` | `init_ir` | Initialise the IR-cut driver |
| `iron` | `set_ir_cut 1` | IR-cut filter on |
| `iroff` | `set_ir_cut 0` | IR-cut filter off |

Two details that matter if you are scripting this:

* **The command runs *after* the page is rendered.** The dispatch block sits below the
  `cat <<EOT` heredoc, so the preview image embedded in the response predates the movement.
  Poll port 3000 separately if you need an after-image.
* **`ptz_invert` does not change what these commands do.** It only swaps which arrow button
  emits which command, by flipping the `$left`/`$right`/`$up`/`$down` substitutions used to build
  the button names. `ptzl` is always `left` at the daemon. The API is not mode-dependent.

The three IR commands are reachable but have **no buttons in the UI** — `irinit`, `iron` and
`iroff` are dispatch-only. They are the intended way to drive the IR-cut filter; see
[ptz.md](ptz.md#ir-cut-filter).

The page also renders an endpoint card advertising `rtsp://<ip>:554/vs0` as Main and
`.../vs1` as Sub. Both are real — see [Media endpoints](#media-endpoints).

### `/cgi-bin/ctl` — our fast control endpoint

> **This file is not part of Gerge's project and you will not find it upstream.** It was written
> for this repo. Source: [`reference/sd-card-original/web_interface/ctl`](../reference/sd-card-original/web_interface/ctl).
> Install to `/mnt/anyka_hack/web_interface/www/cgi-bin/ctl`, mode `755`.

```
GET /cgi-bin/ctl?token=<t>&command=<cmd>[&file=<name>]
```

Returns `text/plain`. Responses are `OK`, the output of a query command, or one of
`ERR notoken` / `ERR auth` / `ERR cmd` / `ERR file` / `ERR nofile`.

It exists because **the stock `/cgi-bin/webui` takes 0.2–1.0 s per request.** Two reasons: every
request sources `header`, whose URL-decoder is a per-character shell loop spawning subshells —
brutal on a 400 MHz ARM926 — and then it renders the entire control page just to write one line
to a FIFO. `ctl` does neither. It parses three known parameters, dispatches on a whitelist, and
returns a few bytes.

| `command=` | Effect |
|---|---|
| `up` `down` `left` `right` | Relative move, 10° |
| `left_up` `right_up` `left_down` `right_down` | Relative diagonal |
| `init_ptz` | Home both axes |
| `init_ir` | Initialise the IR-cut driver. **Required before `ircut_on`/`off`, and nothing runs it at boot** — [detail](ptz.md#-init_ir-is-required-first--and-nothing-runs-it-at-boot) |
| `ircut_on` / `ircut_off` | `set_ir_cut 1` / `set_ir_cut 0` — ✅ **this works**, and is the path Home Assistant drives |
| `white_led_on` / `white_led_off` | Write `/sys/user-gpio/WHITE_LED` — **the write succeeds but no light appears**, see [ptz.md](ptz.md#-white-leds--the-vendor-firmware-disables-them-on-this-variant) |
| `ir_led_on` / `ir_led_off` | Write `/sys/user-gpio/IR_LED` — the write lands, but [illumination is unverified](ptz.md#lights--neither-ring-lights) |
| `status` | Returns `ircut_a=<v> white_led=<v> ir_led=<v>` — the reads are **real**, [see below](#the-status-command-works). ❔ But whether `ircut_a` still tracks the filter when the *daemon* moves it is [an open question](ptz.md#-retracted-ir-cut-control-through-the-daemon-is-broken) |
| `sounds` | Lists the playable clips in `/mnt/sounds/`, space-separated, extensions stripped |
| `play` + `file=<name>` | Plays `/mnt/sounds/<name>.mp3` out of the speaker — [see below](#sound-playback) |

Note it uses the **daemon command names directly** (`left`, `init_ptz`) rather than the stock
UI's abbreviations (`ptzl`, `ptzinit`), and it exposes LED, `status`, `sounds` and `play`
commands the stock UI has no way to reach.

**It does not source `header`, so it is not affected by the injection described above** — it
matches `token=*`, `command=*` and `file=*` with `case`, dispatches the command through a
whitelist, and never interpolates the command into a shell command. That makes `ctl` the right
thing to point automation at.

#### The `status` command works

`status` reads the three GPIO nodes and prints them, and those reads are **real** —
`user_gpio_show` returns `ak_gpio_getpin(pin)` and the value tracks what was written. You can
build a stateful control on top of it.

> This page briefly said the opposite. That was based on a claim about the kernel that
> [turned out to be false when measured](ptz.md#-readback-works-and-it-reads-the-physical-pad).
>
> Confirmed twice over: measured (`wrote 1 → reads 1`), then by disassembly —
> `g_ak39_gpio_getpin` reads the **pin-state register**, twelve bytes away from the output data
> register that `setpin` writes. It is a genuine hardware pad read.

#### Sound playback

```
GET /cgi-bin/ctl?token=<t>&command=play&file=doorbell
```

`play` is the one command that takes caller-supplied data (`file=`) and puts it into a path, so
it is validated hard before use:

```sh
case "$f" in
  ""|*[!A-Za-z0-9_-]*) echo "ERR file"; exit 0 ;;
esac
```

**Bare name only.** No dots, no slashes, no extension — anything outside `[A-Za-z0-9_-]` is
rejected, so `../`, absolute paths and command substitution cannot survive the check. The
directory (`/mnt/sounds/`) and the `.mp3` suffix are supplied by `ctl`, never by the caller. A
name that passes validation but does not exist returns `ERR nofile`.

The handler then raises `SPK_PA` (the speaker amplifier, which is `0` on a cold boot — without
it the decoder runs and you hear nothing) and launches the decoder detached, so the clip
outlives the CGI request rather than being killed when it exits:

```sh
setsid ak_adec_demo 16000 1 mp3 "/mnt/sounds/$f.mp3" </dev/null >/dev/null 2>&1 &
```

> ⚠️ **The `16000` is a hard-coded sample rate, and it must match the file.** `ak_adec_demo`
> takes the rate as an argument and does **not** read it from the MP3, so a mismatch plays at the
> wrong speed and pitch with no error. Every clip in `/mnt/sounds/` is therefore standardised to
> **16 kHz mono**. Upstream's README suggests `41100`, which is both a typo for `44100` and wrong
> for a 16 kHz file — that combination plays speech about 2.5× too fast.
>
> There is also **no working volume control**, so clips must be attenuated before upload.
> Full detail in [ptz.md](ptz.md#speaker--audio-out-works).

> ⚠️ It is not a fix for the stock CGIs. `webui`, `system`, `settings`, `settings_submit.sh`,
> `events`, `video`, `del_video.sh` and `pwd_change` sit in the same directory and remain
> exploitable. Adding `ctl` reduces how often you *use* the vulnerable pages; it does not remove
> them. The isolated VLAN is still the control that matters.

### System — `/cgi-bin/system`

```
GET /cgi-bin/system?token=<t>&command=reboot
```

`reboot` is the only command. Without it the page reports `date`, the IP from
`ip route get 1`, `uptime`, and a `df -h` table for `mtdblock6` (`/etc/jffs2`) plus `mmcblk0`
(the SD card) when present.

### Settings — `/cgi-bin/settings_submit.sh`

This is a generic writer for `gergesettings.txt`, not a fixed form handler. It walks the
existing file line by line, preserves comments and blank lines, and for each `key=value` line
checks whether `key=` appears in the query string — if so it rewrites that line from the shell
variable of the same name, which `header` already set. Unmatched keys in the query string are
ignored, and keys absent from the file are never added.

It writes `/etc/jffs2/gergesettings.txt` **and** `/mnt/anyka_hack/gergesettings.txt` when the
card is present, keeping both copies in step. That matters — see
[sd-card.md](sd-card.md#settings-precedence).

> ⚠️ It writes its scratch file `data.tmp` into the **current working directory**, which for a
> busybox httpd CGI is the `cgi-bin` directory on the SD card. That is why a stray
> `cgi-bin/data.tmp` shows up on cards whose settings have been saved from the web UI. It is
> harmless, and it is not in this repo.

Changes need a reboot, which the "Saving Done" page offers a button for.

The Sensor & Image form does not map one-to-one onto file keys. Three checkboxes are folded
into `libre_anyka_app`'s `extra_args`:

| `extra_args` | Day/Night invert | IR filter invert |
|---|---|---|
| `-i 1` | off | off |
| `-i 2` | off | **on** |
| `-i 3` | **on** | **on** |
| `-i 4` | **on** | off |

Plus ` -u` appended for "Upside Down image (rotate 180 degrees)". This camera runs `-i 4 -u`.

The sensor dropdown is populated from `ls /usr/modules/sensor*.ko`, so a module living
somewhere else — like this camera's `/mnt/sensor_gc1084.ko` — **will not be listed, and saving
that form will silently reset `sensor_kern_module` to whichever in-flash module is selected.**
That will break video on next boot. Edit `gergesettings.txt` directly instead.

### Events, video, deletion

The Events page lists `*.mp4` in `/mnt/anyka_hack/web_interface/www/video/`. It shows a "Motion
recording is disabled!" banner when `md_record_sec=0` (the default, and this camera's setting),
and a "No SD card Inserted!" banner when the card is missing.

* `video?token=<t>&file=<name>` plays `/video/<name>.mp4` in a `<video>` element.
* `video?token=<t>&scan=true` runs `/mnt/anyka_hack/ffmpeg/wrap_mp4.sh` to wrap new `.h264`
  captures into MP4. **This stops the main app while it runs, to free memory** — which is why
  the watchdog treats a running `wrap_mp4.sh` as a reason *not* to restart the app. It needs the
  37 MB `ffmpeg` binary, which is not in this repo; `wrap_mp4.sh` itself is vendored.
* `del_video.sh?token=<t>&file=<name>` "deletes" by renaming both the `.h264` in
  `/mnt/video_encode/` and the `.mp4` to `delete.bak`, and offers an Undo that renames them
  back. Only **one** deletion is undoable — the next delete overwrites `delete.bak`.

## Media endpoints

Neither of these is authenticated, on any port. They are separate servers inside
`libre_anyka_app`, not part of the web UI.

### RTSP, port 554

| Path | Stream | Verified |
|---|---|---|
| `rtsp://<ip>:554/vs0` | **h264 1280×720 @20 fps** + PCM A-law 8 kHz mono | `200 OK` |
| `rtsp://<ip>:554/vs1` | h264 640×360 @20 fps + PCM A-law 8 kHz mono | `200 OK` |
| `rtsp://<ip>:554/vs2` | — | `404 Not Found` |

`image_width` / `image_height` in `gergesettings.txt` set the **sub** channel only — the file's
own comment says so. They do not constrain `/vs0`, which stays at the sensor's 720p.

The 404 response carries `Server: nginx/1.17.8`, which is a borrowed string from
`libre_anyka_app`'s error path, not a real nginx. Do not fingerprint on it.

### Snapshots, port 3000

```
http://<ip>:3000/snapshot.jpeg
```

The filename is **ignored entirely**. Any `*.jpeg` path returns a fresh frame — verified with
`snapshot`, `preview`, `12345` and `zzz`. The web UI exploits this as a cache-buster, polling
`http://<ip>:3000/<random>.jpeg` every 300 ms for a ~3 fps live preview:

```js
setInterval(function() {
  document.getElementById("snapshot").src =
    "http://<ip>:3000/" + Math.round(Math.random()*100000) + ".jpeg";
}, 300);
```

Frames are 640×360 JPEG, ~32 KB. Paths that do not end in `.jpeg` are not answered with a 404 —
**the connection is dropped** (curl reports exit `000`, no HTTP status). Bare `/` behaves the
same way.

> ⚠️ **This server is fragile. Only ever speak HTTP to it.** A bare TCP connect — a socket opened
> and closed without a valid request — **takes it down** until `libre_anyka_app` restarts. RTSP on
> 554 keeps serving throughout, so it reads as a camera fault rather than as something the prober
> did.
>
> In practice that means: no port scans on a schedule, no TCP-only uptime checks, no availability
> monitor pointed at 3000. Use `curl -fsS -o /dev/null http://<ip>:3000/snapshot.jpeg`, which is
> both safe and a stronger check, since a returned frame proves the encoder is alive. Details in
> [troubleshooting.md](troubleshooting.md#finding-the-camera).

## Other listening ports

Verified with `netstat -ltnp` on the camera:

| Port | Process | Notes |
|---|---|---|
| 21 | `tcpsvd 0 21 ftpd -w /` | **Writable FTP rooted at `/`.** See the warning below. |
| 23 | `telnetd` | Root login, plaintext. `run_telnet=1`. |
| 80 | `busybox httpd` | The web UI. `run_web_interface=1`. |
| 554 | `libre_anyka_app` | RTSP, unauthenticated. |
| 3000 | `libre_anyka_app` | Snapshots, unauthenticated. |
| 8782 | `cmd_serverd` | **Bound to `127.0.0.1` only.** Required by the PTZ daemon. |

> ⚠️ **FTP is enabled by default and it is writable over the entire filesystem.** `run_ftp=1`
> starts busybox `ftpd -w /`. Anonymous login is *rejected* (`530 Login failed`, verified), so
> it is not wide open — but it accepts the **root account with the same root password**, in
> plaintext, and `-w` grants write access to `/`. That is enough to overwrite `gergehack.sh` or
> `Factory/config.sh` and own the camera on the next boot. It also serves
> `gergesettings.txt`, which contains the **WiFi PSK in cleartext**.
>
> Nothing in this project needs FTP. Set `run_ftp=0` in `gergesettings.txt` unless you are
> actively using it.

## Recipes

Log in and keep the token, using only the tools a normal box has:

```sh
CAM=192.168.1.20
TOKEN=$(curl -s "http://$CAM/cgi-bin/login_validate.sh?p=webui" \
        | sed -n 's/.*token=\([A-Za-z0-9]*\).*/\1/p')
echo "$TOKEN"
```

Then drive it:

```sh
curl -s "http://$CAM/cgi-bin/webui?token=$TOKEN&command=ptzinit" >/dev/null   # home first
curl -s "http://$CAM/cgi-bin/webui?token=$TOKEN&command=ptzl"    >/dev/null   # pan left 10°
curl -s "http://$CAM/cgi-bin/webui?token=$TOKEN&command=iroff"   >/dev/null   # IR-cut off
curl -s -o frame.jpg "http://$CAM:3000/snapshot.jpeg"                         # no token needed
```

A login invalidates any other session, so a script that logs in repeatedly will fight with a
browser tab. If you have telnet, prefer reading the existing token over minting a new one:

```sh
TOKEN=$(ssh-style-telnet-read /tmp/token.txt)   # or just write to /tmp/ptz.daemon directly
```

Honestly, if you have telnet, skip the web UI — `echo left > /tmp/ptz.daemon` is one hop
instead of three and has no session to invalidate. The web UI's real value is that it works
from a phone browser with no client software.

## See also

* [ptz.md](ptz.md) — the PTZ daemon behind every `command=`, and the IR-cut filter
* [sd-card.md](sd-card.md) — where these files live and how settings persist
* [home-assistant.md](home-assistant.md) — consuming the streams
* [troubleshooting.md](troubleshooting.md) — when none of this responds
