import os
import sqlite3

BASE = "/opt/laundry"
DATA = os.path.join(BASE, "data")
DB = os.path.join(DATA, "laundry.db")
SHOP_ID = "202508240002140000019281846374"
ENDPOINT = "https://userapi.qiekj.com/appointNew/near/newMachines"
PAGE_SIZE = 200
RETENTION_DAYS = 7
FOCUS_CAMPUS = "本部"
FOCUS_BUILDING = "前3栋"
FOCUS_EXCLUDE = "女生"


def in_focus(campus, building, name):
    return (
        campus == FOCUS_CAMPUS
        and building == FOCUS_BUILDING
        and FOCUS_EXCLUDE not in name
    )


def split_name(raw):
    campuses = ["阳澄湖校区", "独墅湖校区", "本部"]
    campus = "其他"
    for c in campuses:
        if raw.startswith(c):
            campus = c
            break
    rest = raw[len(campus):] if raw.startswith(campus) else raw

    building = rest
    if "栋" in rest:
        building = rest[: rest.index("栋") + 1]
    elif rest.startswith("研") and "楼" in rest:
        building = rest[: rest.index("楼") + 1]
    elif rest.startswith("阳光房"):
        building = "阳光房"

    label = rest[len(building):] or building
    return campus, building, label


def connect():
    con = sqlite3.connect(DB, timeout=15)
    con.execute("PRAGMA journal_mode=WAL")
    con.execute("PRAGMA synchronous=NORMAL")
    con.execute("PRAGMA busy_timeout=10000")
    return con


def ensure_schema(con):
    con.executescript(
        """
        CREATE TABLE IF NOT EXISTS machines (
            goods_id   INTEGER PRIMARY KEY,
            name       TEXT NOT NULL,
            campus     TEXT NOT NULL,
            building   TEXT NOT NULL,
            label      TEXT NOT NULL,
            work_status INTEGER,
            remaining  TEXT,
            first_seen INTEGER NOT NULL,
            last_seen  INTEGER NOT NULL
        );

        CREATE TABLE IF NOT EXISTS states (
            goods_id INTEGER NOT NULL,
            minute   INTEGER NOT NULL,
            status   INTEGER NOT NULL,
            PRIMARY KEY (goods_id, minute)
        ) WITHOUT ROWID;

        CREATE INDEX IF NOT EXISTS idx_states_minute ON states(minute);

        CREATE TABLE IF NOT EXISTS polls (
            minute INTEGER PRIMARY KEY,
            ok     INTEGER NOT NULL,
            total  INTEGER NOT NULL,
            idle   INTEGER NOT NULL,
            error  TEXT
        );

        CREATE TABLE IF NOT EXISTS meta (
            key   TEXT PRIMARY KEY,
            value TEXT NOT NULL
        );
        """
    )
    con.commit()
