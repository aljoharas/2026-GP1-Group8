"""
Player Archetypes — turning a real user's manual logs into compute_features input.

Same data rules as Wrapped: library_entries rows with source = 'manual' and a
logged_at (rating/review-only rows have none and are not play logs). Steam
rows never reach this module. hours_played NULL counts as 0.

Trophies: the app stores ticked achievements as display names in
library_entries.achievements. Names are not matched to any list. Per game:
    unlocked  = distinct ticked names across all its logs (case and
                surrounding whitespace ignored)
    available = games.achievements_count (RAWG), when above 0
                else the larger of its achievements-table list size and unlocked
                (fallback 1)
                else 0: no list, left out of trophy_rate (fallback 2)
compute_features caps each game's unlocked at available, so a game's rate is
never above 1.
"""

from __future__ import annotations

import pandas as pd
import psycopg2.extras

import wrapped

# Where a game's trophy_rate denominator came from (build_games' counts)
TROPHY_RAWG = "rawg_count"
TROPHY_FALLBACK = "fallback"
TROPHY_EXCLUDED = "excluded"


def normalise_name(name: str) -> str:
    return name.strip().casefold()


def load_manual_logs(conn, uid: str) -> pd.DataFrame:
    """Every manual play log the user has, prepared like Wrapped's
    (wrapped.prepare_logs) plus "achievements" (ticked names) and
    "achievements_count" (games.achievements_count).
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
            COALESCE(le.achievements, '{}') AS achievements,
            g.achievements_count
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
    """wrapped.prepare_logs, keeping each row's ticked names and its game's
    RAWG achievements_count (None when unknown).
    """
    logs = wrapped.prepare_logs(rows)
    logs["achievements"] = [list(r.get("achievements") or []) for r in rows]
    logs["achievements_count"] = [r.get("achievements_count") for r in rows]
    return logs


def load_achievement_list_sizes(conn, game_ids: list[int]) -> dict[int, int]:
    """Rows in the achievements table per game, in one query. Games with none
    are absent.
    """
    if not game_ids:
        return {}
    cur = conn.cursor()
    cur.execute("""
        SELECT game_id, COUNT(*)
        FROM achievements
        WHERE game_id = ANY(%s)
        GROUP BY game_id
    """, (list(game_ids),))
    sizes = {game_id: int(n) for game_id, n in cur.fetchall()}
    cur.close()
    return sizes


def trophy_denominator(rawg_count, list_size: int, unlocked: int) -> tuple[int, str]:
    """(available, source) for one game; see the module docstring."""
    if rawg_count is not None and not pd.isna(rawg_count) and int(rawg_count) > 0:
        return int(rawg_count), TROPHY_RAWG
    fallback = max(list_size, unlocked)
    if fallback > 0:
        return fallback, TROPHY_FALLBACK
    return 0, TROPHY_EXCLUDED


def build_games(
    logs: pd.DataFrame,
    game_genres: dict[int, list[str]],
    list_sizes: dict[int, int],
) -> tuple[list[dict], dict[str, int]]:
    """Logs (prepare_logs) → one compute_features game dict per game, plus how
    many games took their trophy denominator from each source.
    game_genres is wrapped.load_game_genres-shaped; list_sizes is
    load_achievement_list_sizes-shaped.
    """
    sources = {TROPHY_RAWG: 0, TROPHY_FALLBACK: 0, TROPHY_EXCLUDED: 0}
    if logs.empty:
        return [], sources
    latest = wrapped.latest_log_per_game(logs)
    games = []
    for game_id, game_logs in logs.groupby("game_id", sort=True):
        ticked = {
            normalise_name(n)
            for names in game_logs["achievements"]
            for n in names
            if isinstance(n, str) and n.strip()
        }
        available, source = trophy_denominator(
            game_logs["achievements_count"].iloc[0], list_sizes.get(int(game_id), 0), len(ticked),
        )
        sources[source] += 1
        games.append({
            "game_id": int(game_id),
            "hours": float(game_logs["hours_played"].sum()),
            "completed": bool((game_logs["status"] == "completed").any()),
            "latest_status": latest.loc[game_id, "status"],
            "trophies_unlocked": len(ticked),
            "trophies_available": available,
            "genres": list(game_genres.get(int(game_id), [])),
            "is_online": wrapped.is_online(game_logs["game_modes"].iloc[0]),
            "months": sorted({ts.strftime("%Y-%m") for ts in game_logs["logged_at"]}),
        })
    return games, sources
