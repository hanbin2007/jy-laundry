import json
import time
import urllib.parse
import urllib.request

import common


def fetch_page(page):
    body = urllib.parse.urlencode(
        {
            "goodsPage": page,
            "machineTypeId": "00",
            "orgId": "0",
            "pageSize": common.PAGE_SIZE,
            "shopId": common.SHOP_ID,
            "token": "",
        }
    ).encode()
    req = urllib.request.Request(common.ENDPOINT, data=body, method="POST")
    req.add_header("Content-Type", "application/x-www-form-urlencoded; charset=utf-8")
    req.add_header("User-Agent", "laundry-poller/1.0")
    with urllib.request.urlopen(req, timeout=15) as resp:
        payload = json.loads(resp.read().decode("utf-8"))
    if payload.get("code") != 0:
        raise RuntimeError(payload.get("msg") or "bad code")
    return payload.get("data") or {}


def fetch_all():
    items = []
    page = 1
    for _ in range(6):
        data = fetch_page(page)
        chunk = data.get("items") or []
        items.extend(chunk)
        nxt = data.get("goodsPage")
        if len(chunk) < common.PAGE_SIZE or not nxt or nxt == page:
            break
        page = nxt
    return items


def store(con, items, now):
    minute = now - now % 60
    total = 0
    idle = 0
    machine_rows = []
    state_rows = []

    for item in items:
        try:
            gid = int(item["goodsId"])
        except Exception:
            continue
        name = str(item.get("goodsName") or "")
        status = item.get("deviceWorkStatus")
        remaining = item.get("endUseTimeValue") or ""
        try:
            status = int(status)
        except Exception:
            status = -1

        campus, building, label = common.split_name(name)
        if not common.in_focus(campus, building, name):
            continue

        total += 1
        if status == 10:
            idle += 1
        stored = status if status in (10, 20) else -1

        machine_rows.append(
            (gid, name, campus, building, label, status, remaining, now, now)
        )
        state_rows.append((gid, minute, stored))

    with con:
        con.executemany(
            """
            INSERT INTO machines(goods_id, name, campus, building, label,
                                 work_status, remaining, first_seen, last_seen)
            VALUES (?,?,?,?,?,?,?,?,?)
            ON CONFLICT(goods_id) DO UPDATE SET
                name=excluded.name,
                campus=excluded.campus,
                building=excluded.building,
                label=excluded.label,
                work_status=excluded.work_status,
                remaining=excluded.remaining,
                last_seen=excluded.last_seen
            """,
            machine_rows,
        )
        con.executemany(
            "INSERT OR REPLACE INTO states(goods_id, minute, status) VALUES (?,?,?)",
            state_rows,
        )
        con.execute(
            "INSERT OR REPLACE INTO polls(minute, ok, total, idle, error) VALUES (?,1,?,?,NULL)",
            (minute, total, idle),
        )
        con.execute(
            "INSERT OR REPLACE INTO meta(key, value) VALUES ('last_fetch', ?)",
            (str(now),),
        )

    return total, idle


def poll_once():
    now = int(time.time())
    items = fetch_all()
    con = common.connect()
    try:
        common.ensure_schema(con)
        return store(con, items, now)
    finally:
        con.close()
