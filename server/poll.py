#!/usr/bin/env python3
"""Minute-level fallback poller. Skips when a live poll just happened."""
import fcntl
import os
import sys
import time

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
import common  # noqa: E402
import poller  # noqa: E402


def main():
    os.makedirs(common.DATA, exist_ok=True)
    lock = open(os.path.join(common.DATA, "poll.lock"), "w")
    try:
        fcntl.flock(lock, fcntl.LOCK_EX | fcntl.LOCK_NB)
    except BlockingIOError:
        print("previous poll still running, skip")
        return 0

    now = int(time.time())
    minute = now - now % 60
    con = common.connect()
    common.ensure_schema(con)

    try:
        total, idle = poller.poll_once()
    except Exception as exc:
        con.execute(
            "INSERT OR REPLACE INTO polls(minute, ok, total, idle, error) VALUES (?,0,0,0,?)",
            (minute, str(exc)[:300]),
        )
        con.commit()
        print(f"poll failed: {exc}")
        return 1

    if minute % 3600 < 60:
        cutoff = minute - common.RETENTION_DAYS * 86400
        with con:
            con.execute("DELETE FROM states WHERE minute < ?", (cutoff,))

    print(f"polled minute={minute} total={total} idle={idle}")
    return 0


if __name__ == "__main__":
    sys.exit(main())
