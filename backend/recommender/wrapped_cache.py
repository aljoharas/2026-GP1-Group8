"""
Stored Endgame (Wrapped) responses for the release window.

A year's Wrapped is requested heavily from Dec 31 (release) to Jan 14 (when
the home banner closes). Inside that window, normal users' responses are kept
in wrapped_cache (db/migrations/014_wrapped_cache.sql):

  * Dec 31: the year is still in progress, so every open recalculates and
    replaces the stored row.
  * Jan 1 - Jan 14: the year is closed. The stored row is served if it was
    generated on or after Jan 1 00:00 Riyadh (final data); otherwise the
    response is calculated once, stored and served.

Everything else is calculated live and never touches the table: locked years,
any request outside the window, and every request from an early-access user
(internal testers always see fresh data). After Jan 14 the year's rows are
deleted by delete_expired, which main.py runs once a day.

The cache is an optimisation only: a failed read or write logs a warning and
the request is answered live. Every function takes `now` instead of reading
the clock, so tests control time.
"""

from __future__ import annotations

import datetime as dt
import json
import logging
from decimal import Decimal
from typing import Callable

import psycopg2.extras

from wrapped import LOCKED, WRAPPED_TZ, release_date

log = logging.getLogger("wrapped_cache")

SKIP = "skip"        # calculate live, no read, no write
REFRESH = "refresh"  # calculate, replace the stored row
READ = "read"        # serve the final stored row, else calculate and store it

# Last day of the window: Jan WINDOW_LAST_JAN_DAY of the following year
WINDOW_LAST_JAN_DAY = 14


def window_end(year: int) -> dt.date:
    """Last day (inclusive, Riyadh) the year's cached rows are used."""
    return dt.date(year + 1, 1, WINDOW_LAST_JAN_DAY)


def final_since(year: int) -> dt.datetime:
    """A row generated at or after this instant holds the year's final data."""
    return dt.datetime(year + 1, 1, 1, tzinfo=WRAPPED_TZ)


def cache_mode(year: int, access: str, early_access: bool, now: dt.datetime) -> str:
    """SKIP, REFRESH or READ for this request."""
    if access == LOCKED or early_access:
        return SKIP
    today = now.astimezone(WRAPPED_TZ).date()
    if today == release_date(year):
        return REFRESH
    if release_date(year) < today <= window_end(year):
        return READ
    return SKIP


def to_payload(response: dict) -> dict:
    """Round-trip through JSON so what is stored and what is returned are the
    same plain dict. build_wrapped already returns native types; the default
    handler is a safety net for Decimal / numpy / pandas / datetime values.
    """
    return json.loads(json.dumps(response, default=_json_default, allow_nan=False))


def _json_default(value):
    if isinstance(value, Decimal):
        return float(value)
    if isinstance(value, (dt.datetime, dt.date)):
        return value.isoformat()
    # numpy scalars and pandas Timestamps, without importing either here
    if hasattr(value, "isoformat"):
        return value.isoformat()
    if getattr(value, "ndim", 0) > 0 and hasattr(value, "tolist"):
        return value.tolist()  # arrays / Series
    if hasattr(value, "item"):
        return value.item()
    raise TypeError(f"{type(value).__name__} is not JSON serializable")


def read_final(conn, uid: str, year: int) -> dict | None:
    """The stored payload if it holds the closed year's final data.

    The generated_at bound is what keeps a Dec 31 snapshot from being served as
    final. It also covers a user whose early-access flag was turned off: any
    row of theirs written before the year closed fails the same check and is
    recalculated. (Early-access users don't write rows today, but rows from an
    earlier build or a manual insert are handled the same way.)
    """
    cur = conn.cursor(cursor_factory=psycopg2.extras.RealDictCursor)
    cur.execute("""
        SELECT payload
        FROM wrapped_cache
        WHERE user_id = %s AND year = %s AND generated_at >= %s
    """, (uid, year, final_since(year)))
    row = cur.fetchone()
    cur.close()
    return row["payload"] if row else None


def store(conn, uid: str, year: int, payload: dict, now: dt.datetime) -> None:
    """Replace the user's row for the year."""
    cur = conn.cursor()
    cur.execute("""
        INSERT INTO wrapped_cache (user_id, year, payload, generated_at)
        VALUES (%s, %s, %s, %s)
        ON CONFLICT (user_id, year)
        DO UPDATE SET payload = EXCLUDED.payload, generated_at = EXCLUDED.generated_at
    """, (uid, year, psycopg2.extras.Json(payload), now))
    cur.close()
    conn.commit()


def last_expired_year(now: dt.datetime) -> int:
    """Newest year whose window has ended as of now (Jan 14 has passed)."""
    today = now.astimezone(WRAPPED_TZ).date()
    return today.year - 1 if today > window_end(today.year - 1) else today.year - 2


def delete_expired(conn, now: dt.datetime) -> int:
    """Delete every row whose window has ended, any user. Returns the count.
    Safe to run repeatedly: a second run finds nothing to delete.
    """
    cur = conn.cursor()
    cur.execute("DELETE FROM wrapped_cache WHERE year <= %s", (last_expired_year(now),))
    deleted = cur.rowcount
    cur.close()
    conn.commit()
    return deleted


def _rollback(conn) -> None:
    # A failed statement leaves psycopg2 in an aborted transaction; without a
    # rollback the live calculation's queries on this connection would fail too.
    try:
        conn.rollback()
    except Exception:
        pass


def get_or_build(
    conn,
    uid: str,
    year: int,
    access: str,
    early_access: bool,
    now: dt.datetime,
    build: Callable[[], dict],
) -> dict:
    """The /wrapped response for an unlocked year, from the cache when allowed."""
    mode = cache_mode(year, access, early_access, now)
    if mode == SKIP:
        return build()

    if mode == READ:
        try:
            cached = read_final(conn, uid, year)
        except Exception as e:
            log.warning("wrapped cache read failed (uid=%s year=%s): %s", uid, year, e)
            _rollback(conn)
            cached = None
        if cached is not None:
            return cached

    payload = to_payload(build())
    try:
        store(conn, uid, year, payload, now)
    except Exception as e:
        log.warning("wrapped cache write failed (uid=%s year=%s): %s", uid, year, e)
        _rollback(conn)
    return payload
