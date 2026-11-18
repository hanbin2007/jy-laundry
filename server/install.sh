#!/bin/bash
set -euo pipefail
SRC="$(cd "$(dirname "$0")" && pwd)"
BASE=/opt/laundry

id -u laundry >/dev/null 2>&1 || useradd --system --no-create-home --shell /usr/sbin/nologin laundry

mkdir -p "$BASE/data"
install -o root -g root -m 644 "$SRC/common.py" "$BASE/common.py"
install -o root -g root -m 755 "$SRC/poll.py" "$BASE/poll.py"
install -o root -g root -m 755 "$SRC/api.py" "$BASE/api.py"
install -o root -g root -m 644 "$SRC/poller.py" "$BASE/poller.py"

if [ ! -s "$BASE/data/token" ]; then
    install -o laundry -g laundry -m 600 "$SRC/token" "$BASE/data/token"
fi
chown -R laundry:laundry "$BASE/data"
chmod 700 "$BASE/data"

install -o root -g root -m 644 "$SRC/laundry-poll.service" /etc/systemd/system/laundry-poll.service
install -o root -g root -m 644 "$SRC/laundry-poll.timer" /etc/systemd/system/laundry-poll.timer
install -o root -g root -m 644 "$SRC/laundry-api.service" /etc/systemd/system/laundry-api.service

systemctl daemon-reload
systemctl enable --now laundry-poll.timer >/dev/null
systemctl enable --now laundry-api.service >/dev/null
systemctl restart laundry-api.service

install -o root -g root -m 644 "$SRC/nginx-laundry.conf" /etc/nginx/conf.d/laundry-api.conf
nginx -t
systemctl reload nginx

runuser -u laundry -- /usr/bin/python3 "$BASE/poll.py" || true
sleep 1

echo "== timers =="
systemctl list-timers laundry-poll.timer --no-pager | head -3
echo "== api =="
systemctl is-active laundry-api.service
echo "== local =="
curl -s -m 5 http://127.0.0.1:18787/health; echo
