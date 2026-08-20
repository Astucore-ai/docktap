#!/bin/bash
# launchd KeepAlive helper. If the app is already running, wait and then become
# it (so bootstrap-while-running does not spawn a second copy). After exec,
# launchd is parent of the real binary and will restart it on crash.
NAME="${1:?}"
BIN="${2:?}"
while /usr/bin/pgrep -qx "$NAME"; do
  /bin/sleep 1
done
if [[ ! -x "$BIN" ]]; then
  echo "keep-alive: missing $BIN" >&2
  exit 1
fi
exec "$BIN"
