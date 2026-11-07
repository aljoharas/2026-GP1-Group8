"""
Player Archetypes — turning a real user's manual logs into compute_features input.

Same data rules as Wrapped: library_entries rows with source = 'manual' and a
logged_at (rating/review-only rows have none and are not play logs). Steam
rows never reach this module. hours_played NULL counts as 0.

Trophies: the app stores ticked achievements as display names in
library_entries.achievements. A game's list is its rows in the achievements
table; names are matched ignoring case and surrounding whitespace, and each
name counts once per game however many logs tick it. A game's list size is
its number of distinct names, so unlocked can never exceed it (a few games
have several achievements with the same display name). Ticked names that match
nothing are counted and reported, not guessed at.
"""

from __future__ import annotations

import pandas as pd
import psycopg2.extras

import wrapped


def normalise_name(name: str) -> str:
    return name.strip().casefold()


def load_manual_logs(conn, uid: str) -> pd.DataFrame:
    """Every manual play log the user has, prepared like Wrapped's
    (wrapped.prepare_logs) plus an "achievements" column of ticked names.
    """
    cur = conn.cursor(cursor_factory=psycopg2.extras.RealDictCursor)
    cur.execute("""
        SELECT
            le.id,
            le.game_id,
            le.status,
            le.hours_played,
            le.logged_at,
            g.name,
            g.game_modes,
            COALESCE(le.achievements, '{}') AS achievements
        FROM library_entries le
        JOIN games g ON g.id = le.game_id
        WHERE le.user_id = %s
          AND le.source = %s
          AND le.logged_at IS NOT NULL
    """, (uid, wrapped.WRAPPED_SOURCE))
    rows = [dict(row) for row in cur.fetchall()]
    cur.close()
    return prepare_logs(rows)


def prepare_logs(rows: list[dict]) -> pd.DataFrame:
    """wrapped.prepare_logs, keeping each row's ticked achievement names."""
    logs = wrapped.prepare_logs(rows)
    logs["achievements"] = [list(r.get("achievements") or []) for r in rows]
    return logs


def load_achievement_names(conn, game_ids: list[int]) -> dict[int, set[str]]:
    """Each game's achievement list as normalised display names, in one query.
    Games with no achievements are absent.
    """
    if not game_ids:
        return {}
    cur = conn.cursor()
    cur.execute("""
        SELECT game_id, display_name
        FROM achievements
        WHERE game_id = ANY(%s)
          AND display_name IS NOT NULL
    """, (list(game_ids),))
    names: dict[int, set[str]] = {}
    for game_id, display_name in cur.fetchall():
        if display_name.strip():
            names.setdefault(game_id, set()).add(normalise_name(display_name))
    cur.close()
    return names


def build_games(
    logs: pd.DataFrame,
    game_genres: dict[int, list[str]],
    achievement_names: dict[int, set[str]],
) -> tuple[list[dict], int]:
    """Logs (prepare_logs) → one compute_features game dict per game, plus the
    number of distinct ticked names (per game) that matched no achievement.
    game_genres is wrapped.load_game_genres-shaped; achievement_names is
    load_achievement_names-shaped.
    """
    if logs.empty:
        return [], 0
    latest = wrapped.latest_log_per_game(logs)
    games, unmatched = [], 0
    for game_id, game_logs in logs.groupby("game_id", sort=True):
        ticked = {
            normalise_name(n)
            for names in game_logs["achievements"]
            for n in names
            if isinstance(n, str) and n.strip()
        }
        listed = achievement_names.get(int(game_id), set())
        unmatched += len(ticked - listed)
        games.append({
            "game_id": int(game_id),
            "hours": float(game_logs["hours_played"].sum()),
            "completed": bool((game_logs["status"] == "completed").any()),
            "latest_status": latest.loc[game_id, "status"],
            "trophies_unlocked": len(ticked & listed),
            "trophies_available": len(listed),
            "genres": list(game_genres.get(int(game_id), [])),
            "is_online": wrapped.is_online(game_logs["game_modes"].iloc[0]),
            "months": sorted({ts.strftime("%Y-%m") for ts in game_logs["logged_at"]}),
        })
    return games, unmatched
