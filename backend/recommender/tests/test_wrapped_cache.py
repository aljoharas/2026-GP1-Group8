"""
Unit tests for wrapped_cache.py. No database: FakeConn keeps wrapped_cache rows
in a dict and understands the three statements the module runs.

Run from recommender/:  pytest
"""

import json
from datetime import datetime, timezone
from decimal import Decimal

import numpy as np
import pandas as pd
import pytest

import wrapped
import wrapped_cache
from wrapped import FULL, LOCKED, PARTIAL, WRAPPED_TZ
from wrapped_cache import READ, REFRESH, SKIP


def riyadh(*args):
    return datetime(*args, tzinfo=WRAPPED_TZ)


class FakeCursor:
    def __init__(self, conn):
        self.conn = conn
        self.rowcount = 0
        self._row = None

    def execute(self, sql, params):
        conn = self.conn
        conn.statements.append(sql.split()[0].upper())
        if conn.fail:
            raise RuntimeError("db down")
        if sql.lstrip().startswith("SELECT"):
            uid, year, since = params
            row = conn.rows.get((uid, year))
            self._row = {"payload": row["payload"]} if row and row["generated_at"] >= since else None
        elif sql.lstrip().startswith("INSERT"):
            uid, year, payload, generated_at = params
            # Json adapter -> stored as JSONB, read back as a fresh dict
            conn.rows[(uid, year)] = {"payload": json.loads(json.dumps(payload.adapted)), "generated_at": generated_at}
        elif sql.lstrip().startswith("DELETE"):
            (max_year,) = params
            doomed = [k for k in conn.rows if k[1] <= max_year]
            for k in doomed:
                del conn.rows[k]
            self.rowcount = len(doomed)

    def fetchone(self):
        return self._row

    def close(self):
        pass


class FakeConn:
    def __init__(self, fail=False):
        self.rows = {}
        self.statements = []
        self.fail = fail
        self.commits = 0
        self.rollbacks = 0

    def cursor(self, cursor_factory=None):
        return FakeCursor(self)

    def commit(self):
        self.commits += 1

    def rollback(self):
        self.rollbacks += 1


class Builder:
    """Stands in for the endpoint's build(): counts calls, returns a new value each time."""

    def __init__(self, year=2026):
        self.year = year
        self.calls = 0

    def __call__(self):
        self.calls += 1
        return {"year": self.year, "locked": False, "empty_state": False, "total_hours": float(self.calls)}


def run(conn, now, year=2026, access=FULL, early_access=False, build=None, uid="u1"):
    build = build or Builder(year)
    return wrapped_cache.get_or_build(conn, uid, year, access, early_access, now, build), build


# --- cache_mode / window ------------------------------------------------------

@pytest.mark.parametrize("now, expected", [
    (riyadh(2026, 12, 30, 23, 59), SKIP),   # before release
    (riyadh(2026, 12, 31, 0, 0), REFRESH),
    (riyadh(2026, 12, 31, 23, 59), REFRESH),
    (riyadh(2027, 1, 1, 0, 0), READ),
    (riyadh(2027, 1, 14, 23, 59), READ),    # last day of the window
    (riyadh(2027, 1, 15, 0, 0), SKIP),      # window over
    (riyadh(2027, 6, 1), SKIP),
])
def test_cache_mode_window_for_normal_users(now, expected):
    assert wrapped_cache.cache_mode(2026, FULL, False, now) == expected


def test_cache_mode_uses_riyadh_time():
    # 21:30 UTC on Dec 30 is already 00:30 Dec 31 in Riyadh
    assert wrapped_cache.cache_mode(2026, FULL, False, datetime(2026, 12, 30, 21, 30, tzinfo=timezone.utc)) == REFRESH
    # 21:30 UTC on Jan 14 is already Jan 15 in Riyadh
    assert wrapped_cache.cache_mode(2026, FULL, False, datetime(2027, 1, 14, 21, 30, tzinfo=timezone.utc)) == SKIP


@pytest.mark.parametrize("now", [riyadh(2026, 11, 1), riyadh(2026, 12, 31, 12), riyadh(2027, 1, 5), riyadh(2027, 2, 1)])
@pytest.mark.parametrize("access", [PARTIAL, FULL])
def test_cache_mode_early_access_always_skips(now, access):
    assert wrapped_cache.cache_mode(2026, access, True, now) == SKIP


def test_cache_mode_locked_skips():
    assert wrapped_cache.cache_mode(2026, LOCKED, False, riyadh(2026, 12, 31, 12)) == SKIP


# --- Dec 31 -------------------------------------------------------------------

def test_dec_31_always_recalculates_and_replaces():
    conn = FakeConn()
    first, b1 = run(conn, riyadh(2026, 12, 31, 9))
    second, b2 = run(conn, riyadh(2026, 12, 31, 20))
    assert b1.calls == 1 and b2.calls == 1
    assert "SELECT" not in conn.statements
    assert conn.rows[("u1", 2026)]["generated_at"] == riyadh(2026, 12, 31, 20)
    assert conn.rows[("u1", 2026)]["payload"] == second


# --- Jan 1 - Jan 14 -------------------------------------------------------------

def test_jan_1_with_only_dec_31_snapshot_recalculates_once_then_reads():
    conn = FakeConn()
    run(conn, riyadh(2026, 12, 31, 23))  # Dec 31 snapshot

    jan1, b1 = run(conn, riyadh(2027, 1, 1, 8))
    assert b1.calls == 1
    assert conn.rows[("u1", 2026)]["generated_at"] == riyadh(2027, 1, 1, 8)

    later, b2 = run(conn, riyadh(2027, 1, 9, 15))
    assert b2.calls == 0
    assert later == jan1


def test_jan_1_with_no_row_calculates_and_stores():
    conn = FakeConn()
    response, b = run(conn, riyadh(2027, 1, 3))
    assert b.calls == 1
    assert conn.rows[("u1", 2026)]["payload"] == response


def test_jan_14_is_served_from_cache():
    conn = FakeConn()
    stored, _ = run(conn, riyadh(2027, 1, 2))
    served, b = run(conn, riyadh(2027, 1, 14, 23, 59))
    assert b.calls == 0
    assert served == stored


def test_jan_15_is_not_served_or_written():
    conn = FakeConn()
    run(conn, riyadh(2027, 1, 2))
    statements_before = len(conn.statements)
    _, b = run(conn, riyadh(2027, 1, 15))
    assert b.calls == 1
    assert len(conn.statements) == statements_before


def test_dec_30_normal_user_caches_nothing():
    # Dec 30 is LOCKED for normal users; even if called, nothing is touched
    conn = FakeConn()
    _, b = run(conn, riyadh(2026, 12, 30, 12), access=LOCKED)
    assert b.calls == 1
    assert conn.statements == [] and conn.rows == {}


def test_past_year_outside_window_is_live():
    conn = FakeConn()
    _, b = run(conn, riyadh(2026, 11, 19), year=2025)
    assert b.calls == 1
    assert conn.statements == []


def test_rows_are_per_user():
    conn = FakeConn()
    run(conn, riyadh(2027, 1, 2), uid="a")
    _, b = run(conn, riyadh(2027, 1, 3), uid="b")
    assert b.calls == 1
    assert set(conn.rows) == {("a", 2026), ("b", 2026)}


# --- Early access ---------------------------------------------------------------

@pytest.mark.parametrize("now, access", [
    (riyadh(2026, 11, 19), PARTIAL),
    (riyadh(2026, 12, 31, 12), FULL),
    (riyadh(2027, 1, 5), FULL),
])
def test_early_access_never_reads_or_writes(now, access):
    conn = FakeConn()
    conn.rows[("u1", 2026)] = {"payload": {"stale": True}, "generated_at": riyadh(2027, 1, 2)}
    response, b = run(conn, now, access=access, early_access=True)
    assert b.calls == 1
    assert response != {"stale": True}
    assert conn.statements == []
    assert conn.rows[("u1", 2026)]["payload"] == {"stale": True}


def test_flag_turned_off_old_pre_release_row_is_not_served():
    # A row written before the year closed (e.g. from an early-access test) is
    # never served as final once the user is a normal user again.
    conn = FakeConn()
    conn.rows[("u1", 2026)] = {"payload": {"test": True}, "generated_at": riyadh(2026, 11, 1)}
    response, b = run(conn, riyadh(2027, 1, 4))
    assert b.calls == 1
    assert response != {"test": True}
    assert conn.rows[("u1", 2026)]["generated_at"] == riyadh(2027, 1, 4)


# --- Failures -----------------------------------------------------------------

@pytest.mark.parametrize("now", [riyadh(2026, 12, 31, 12), riyadh(2027, 1, 5)])
def test_cache_failure_falls_back_to_live(now):
    conn = FakeConn(fail=True)
    response, b = run(conn, now)
    assert b.calls == 1
    assert response["total_hours"] == 1.0
    assert conn.rollbacks >= 1


# --- Cleanup ------------------------------------------------------------------

@pytest.mark.parametrize("now, expected", [
    (riyadh(2027, 1, 14, 23, 59), 2025),
    (riyadh(2027, 1, 15, 0, 0), 2026),
    (riyadh(2026, 11, 19), 2025),
    (riyadh(2026, 12, 31), 2025),
])
def test_last_expired_year(now, expected):
    assert wrapped_cache.last_expired_year(now) == expected


def test_cleanup_deletes_only_expired_rows_and_is_repeatable():
    conn = FakeConn()
    for uid, year in [("a", 2024), ("a", 2025), ("b", 2026), ("a", 2027)]:
        conn.rows[(uid, year)] = {"payload": {}, "generated_at": riyadh(year, 12, 31)}

    assert wrapped_cache.delete_expired(conn, riyadh(2027, 1, 14, 12)) == 2
    assert set(conn.rows) == {("b", 2026), ("a", 2027)}

    assert wrapped_cache.delete_expired(conn, riyadh(2027, 1, 15, 0, 1)) == 1
    assert set(conn.rows) == {("a", 2027)}

    assert wrapped_cache.delete_expired(conn, riyadh(2027, 1, 15, 0, 2)) == 0
    assert set(conn.rows) == {("a", 2027)}


# --- Serialization --------------------------------------------------------------

def year_logs(rows, year=2026, now=None):
    return wrapped.select_year_logs(wrapped.prepare_logs(rows), year, now)


def lookup(game_ids):
    return {gid: {"id": gid, "name": f"Game {gid}", "cover_image": f"c{gid}.jpg", "background_image": None} for gid in game_ids}


@pytest.mark.parametrize("rows", [
    [],
    [
        {"id": 1, "game_id": 1, "status": "completed", "hours_played": Decimal("12.5"),
         "logged_at": datetime(2026, 3, 1, tzinfo=timezone.utc), "name": "Game 1",
         "game_modes": '["Multiplayer"]', "user_rating": 8, "rawg_rating": Decimal("4.2"),
         "cover_image": "c1.jpg", "background_image": None},
        {"id": 2, "game_id": 2, "status": "playing", "hours_played": None,
         "logged_at": datetime(2026, 7, 1, tzinfo=timezone.utc), "name": "Game 2",
         "game_modes": None, "user_rating": None, "rawg_rating": None,
         "cover_image": None, "background_image": "b2.jpg"},
    ],
])
def test_cached_payload_matches_fresh_build(rows):
    now = riyadh(2027, 1, 3)
    fresh = wrapped.build_wrapped(2026, FULL, year_logs(rows, now=now), now, game_lookup=lookup)
    conn = FakeConn()
    first, _ = run(conn, now, build=lambda: fresh)
    served, _ = run(conn, riyadh(2027, 1, 4), build=lambda: pytest.fail("should be cached"))
    assert first == fresh
    assert served == fresh
    assert json.loads(json.dumps(served)) == fresh


def test_empty_state_is_cached():
    now = riyadh(2027, 1, 3)
    fresh = wrapped.build_wrapped(2026, FULL, year_logs([], now=now), now, game_lookup=lookup)
    assert fresh["empty_state"] is True
    conn = FakeConn()
    run(conn, now, build=lambda: fresh)
    assert conn.rows[("u1", 2026)]["payload"] == fresh


def test_to_payload_converts_non_native_types():
    payload = wrapped_cache.to_payload({
        "dec": Decimal("1.5"),
        "i64": np.int64(3),
        "i32": np.int32(4),
        "bool": np.bool_(True),
        "f64": np.float64(2.25),
        "ts": pd.Timestamp("2026-12-31T10:00:00+03:00"),
        "dt": riyadh(2026, 12, 31, 10),
        "arr": np.array([1, 2]),
    })
    assert payload == {
        "dec": 1.5, "i64": 3, "i32": 4, "bool": True, "f64": 2.25,
        "ts": "2026-12-31T10:00:00+03:00", "dt": "2026-12-31T10:00:00+03:00",
        "arr": [1, 2],
    }
    assert all(type(v) in (int, float, str, list, bool) for v in payload.values())
