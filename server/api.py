#!/usr/bin/env python3
"""Read-only JSON API for the laundry history."""
import hmac
import json
import os
import re
import sys
import threading
import time
import traceback
import urllib.parse
from http.server import BaseHTTPRequestHandler, ThreadingHTTPServer

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
import common  # noqa: E402
import poller  # noqa: E402

HOST = "127.0.0.1"
PORT = 18787
TOKEN_FILE = os.path.join(common.DATA, "token")

_cache = {}
_cache_lock = threading.Lock()
TOKEN = ""


def load_token():
    global TOKEN
    with open(TOKEN_FILE, encoding="utf-8") as fh:
        TOKEN = fh.read().strip()


def natkey(s):
    return [(0, int(t)) if t.isdigit() else (1, t) for t in re.split(r"(\d+)", s)]


def campus_rank(name):
    return {"本部": 0, "阳澄湖校区": 1, "独墅湖校区": 2}.get(name, 3)


def building_rank(name):
    if name.startswith("阳光房"):
        return 3
    if name.startswith("研"):
        return 2
    if "栋" in name:
        return 0
    return 1


def rle(axis):
    runs = []
    start = 0
    cur = axis[0]
    for i in range(1, len(axis)):
        if axis[i] != cur:
            runs.append([start, i - start, cur])
            start = i
            cur = axis[i]
    runs.append([start, len(axis) - start, cur])
    return runs


def build_overview(hours):
    hours = max(1, min(hours, common.RETENTION_DAYS * 24))
    minutes = hours * 60
    now = int(time.time())

    con = common.connect()
    try:
        last = con.execute(
            "SELECT minute, ok, total, idle, error FROM polls ORDER BY minute DESC LIMIT 1"
        ).fetchone()
        end_minute = last[0] if last else now - now % 60
        start_minute = end_minute - (minutes - 1) * 60

        machines = con.execute(
            "SELECT goods_id, name, campus, building, label, work_status, remaining"
            " FROM machines WHERE campus=? AND building=? AND name NOT LIKE ?",
            (common.FOCUS_CAMPUS, common.FOCUS_BUILDING, "%" + common.FOCUS_EXCLUDE + "%"),
        ).fetchall()

        rows = con.execute(
            "SELECT goods_id, minute, status FROM states"
            " WHERE minute >= ? AND minute <= ?",
            (start_minute, end_minute),
        ).fetchall()

        polled = {
            r[0]
            for r in con.execute(
                "SELECT minute FROM polls WHERE ok=1 AND minute >= ? AND minute <= ?",
                (start_minute, end_minute),
            ).fetchall()
        }

        meta = dict(con.execute("SELECT key, value FROM meta").fetchall())
    finally:
        con.close()

    by_id = {}
    for gid, minute, status in rows:
        by_id.setdefault(gid, {})[(minute - start_minute) // 60] = status

    out_machines = []
    counts = [0] * minutes
    for gid, name, campus, building, label, work_status, remaining in machines:
        axis = [-1] * minutes
        data = by_id.get(gid, {})
        for offset, status in data.items():
            if 0 <= offset < minutes:
                axis[offset] = status
                if status == 10:
                    counts[offset] += 1
        out_machines.append(
            {
                "id": gid,
                "name": name,
                "campus": campus,
                "building": building,
                "label": label,
                "status": work_status,
                "remaining": remaining or "",
                "runs": rle(axis),
            }
        )

    out_machines.sort(
        key=lambda m: (
            campus_rank(m["campus"]),
            building_rank(m["building"]),
            natkey(m["building"]),
            natkey(m["label"]),
        )
    )

    series = [
        [i, counts[i] if (start_minute + i * 60) in polled else None]
        for i in range(0, minutes, 5)
    ]
    if (minutes - 1) % 5:
        last_idx = minutes - 1
        series.append(
            [last_idx, counts[last_idx] if (start_minute + last_idx * 60) in polled else None]
        )

    last_poll = None
    if last:
        fetched = int(meta.get("last_fetch", 0) or 0)
        last_poll = {
            "minute": last[0],
            "ok": bool(last[1]),
            "total": last[2],
            "idle": last[3],
            "error": last[4],
            "fetchedAt": fetched or None,
            "ageSeconds": max(0, now - fetched) if fetched else now - last[0],
        }

    return {
        "ok": True,
        "generatedAt": now,
        "window": {"start": start_minute, "minutes": minutes},
        "lastPoll": last_poll,
        "series": series,
        "machines": out_machines,
    }


def get_overview(hours):
    con = common.connect()
    try:
        last = con.execute("SELECT MAX(minute) FROM polls").fetchone()[0]
    finally:
        con.close()
    key = (hours, last, int(time.time()) // 10)

    with _cache_lock:
        hit = _cache.get(key)
        if hit:
            return hit

    payload = build_overview(hours)
    body = json.dumps(payload, ensure_ascii=False, separators=(",", ":")).encode()

    with _cache_lock:
        if len(_cache) > 32:
            _cache.clear()
        _cache[key] = body
    return body


_live_lock = threading.Lock()
_last_live = 0.0


def refresh_live(min_interval=4.0):
    """Fetch the vendor at most once per interval; every live fetch is persisted."""
    global _last_live
    with _live_lock:
        now = time.time()
        if now - _last_live < min_interval:
            return False
        _last_live = now
        try:
            total, idle = poller.poll_once()
            print(f"live poll total={total} idle={idle}", flush=True)
        except Exception:
            traceback.print_exc()
        return True


class Handler(BaseHTTPRequestHandler):
    server_version = "laundry/1.0"
    protocol_version = "HTTP/1.1"

    def _send(self, code, body=b"", content_type="application/json; charset=utf-8"):
        self.send_response(code)
        self.send_header("Content-Type", content_type)
        self.send_header("Content-Length", str(len(body)))
        self.send_header("Access-Control-Allow-Origin", "*")
        self.send_header("Access-Control-Allow-Headers", "X-Token, Content-Type")
        self.send_header("Access-Control-Allow-Methods", "GET, OPTIONS")
        self.send_header("Cache-Control", "no-store")
        self.end_headers()
        if body:
            self.wfile.write(body)

    def _authorized(self, query):
        supplied = self.headers.get("X-Token") or (query.get("token") or [""])[0]
        return bool(TOKEN) and hmac.compare_digest(supplied, TOKEN)

    def do_OPTIONS(self):
        self._send(204)

    def do_GET(self):
        parsed = urllib.parse.urlparse(self.path)
        query = urllib.parse.parse_qs(parsed.query)

        if parsed.path == "/health":
            self._send(200, json.dumps({"ok": True}).encode())
            return

        if parsed.path != "/api/v1/overview":
            self._send(404, json.dumps({"ok": False, "error": "not found"}).encode())
            return

        if not self._authorized(query):
            self._send(401, json.dumps({"ok": False, "error": "unauthorized"}).encode())
            return

        try:
            hours = int((query.get("hours") or ["3"])[0])
        except ValueError:
            hours = 3

        try:
            if (query.get("live") or ["0"])[0] == "1":
                refresh_live()
                payload = build_overview(hours)
                body = json.dumps(payload, ensure_ascii=False, separators=(",", ":")).encode()
                self._send(200, body)
            else:
                self._send(200, get_overview(hours))
        except Exception:
            traceback.print_exc()
            self._send(500, json.dumps({"ok": False, "error": "internal"}).encode())

    def log_message(self, fmt, *args):
        sys.stderr.write("%s %s\n" % (self.address_string(), fmt % args))


def main():
    load_token()
    con = common.connect()
    common.ensure_schema(con)
    con.close()

    server = ThreadingHTTPServer((HOST, PORT), Handler)
    server.daemon_threads = True
    print(f"laundry api listening on {HOST}:{PORT}")
    server.serve_forever()


if __name__ == "__main__":
    main()
