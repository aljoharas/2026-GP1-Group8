"""
Gaming Wrapped — a yearly summary of a user's gaming activity.

Calculated live on every request and never stored. Node verifies the Firebase
token and calls GET /wrapped?uid=...&year=...; this module does the rest.

Data source: library_entries rows with source = 'manual' only. Steam rows are
out of scope and are filtered out in SQL, so they never reach pandas.

Period: one calendar year in Asia/Riyadh, based on logged_at, from Jan 1 00:00
to Dec 31 23:59:59 or now, whichever is earlier. Rating/review-only rows have logged_at NULL and are excluded by that
filter automatically.

Timezone assumption: Flutter sends logged_at as an ISO string with no UTC
offset (DateTime.toIso8601String() on a local time). Postgres reads such naive
timestamps in the DB session timezone, which is UTC on our server (set in the
server's configuration file). So a log entered at 01:00 Riyadh time is stored
as 01:00 UTC (04:00 Riyadh). The window below is still built and compared in
Asia/Riyadh; the stored value is simply taken as the truth.

Every log is its own row (a new play-through), so one game can have many rows.
hours_played is the hours for that one log; NULL counts as 0.
"""

import json
from datetime import date, datetime
from typing import Callable
from zoneinfo import ZoneInfo

import pandas as pd
import psycopg2.extras

WRAPPED_TZ = ZoneInfo("Asia/Riyadh")
WRAPPED_SOURCE = "manual"
MIN_YEAR = 2000
MAX_YEAR = 2100

# Statuses dropped from the year's logs. Manual logs are only ever
# playing/completed/paused today; plan_to_play is a wishlist entry, not play.
EXCLUDED_STATUSES = ("plan_to_play",)

# Access states returned by access_state()
LOCKED = "locked"
PARTIAL = "partial"
FULL = "full"

TOP_GAMES_LIMIT = 3

# Card 4: a game is online when any of its IGDB game_modes contains one of
# these, ignoring case. "Massively Multiplayer Online (MMO)" matches "multiplayer".
ONLINE_MODE_KEYWORDS = ("multiplayer", "battle royale", "co-operative")

# Card 6: play-style groups and personalities
FINISHED = "finished"
PAUSED = "paused"
PLAYING = "playing"
PLAY_STYLE_MIN_GAMES = 3
PLAY_STYLE_MIN_SHARE = 0.4
PERSONALITY_BY_GROUP = {
    FINISHED: "the_closer",
    PLAYING: "the_juggler",
    PAUSED: "save_and_quit",
}

LOG_COLUMNS = [
    "id",
    "game_id",
    "status",
    "hours_played",
    "logged_at",
    "name",
    "game_modes",
]

UNLOCK_COLUMNS = ["achievement_id", "unlocked_at", "logged_at"]


# --- Period & access ----------------------------------------------------------

def parse_year(raw: str | None, now: datetime) -> int:
    """Return the requested year, defaulting to the current Riyadh year.
    Raises ValueError for a non-integer or out-of-range value.
    """
    if raw is None or raw.strip() == "":
        return now.astimezone(WRAPPED_TZ).year
    try:
        year = int(raw.strip())
    except ValueError:
        raise ValueError("year must be an integer")
    if year < MIN_YEAR or year > MAX_YEAR:
        raise ValueError(f"year must be between {MIN_YEAR} and {MAX_YEAR}")
    return year


def year_window(year: int, now: datetime | None = None) -> tuple[datetime, datetime]:
    """[start, end] of the year in Asia/Riyadh. end is Dec 31 23:59:59, or now
    if that is earlier, so a partial year never includes logs dated later.
    """
    now = (now or datetime.now(WRAPPED_TZ)).astimezone(WRAPPED_TZ)
    # .999999 so a log at 23:59:59.5 (Flutter sends milliseconds) still counts
    year_end = datetime(year, 12, 31, 23, 59, 59, 999999, tzinfo=WRAPPED_TZ)
    return datetime(year, 1, 1, tzinfo=WRAPPED_TZ), min(year_end, now)


def release_date(year: int) -> date:
    """The day a year's Wrapped unlocks for everyone."""
    return date(year, 12, 31)


def access_state(year: int, early_access: bool, now: datetime) -> str:
    """LOCKED, PARTIAL or FULL for this year as of `now`.

    Past years are FULL. Future years are LOCKED. The current year is FULL from
    its release date on; before that it is PARTIAL with early access and LOCKED
    without.
    """
    today = now.astimezone(WRAPPED_TZ).date()
    if year < today.year:
        return FULL
    if year > today.year:
        return LOCKED
    if today >= release_date(year):
        return FULL
    return PARTIAL if early_access else LOCKED


# --- Loading ------------------------------------------------------------------

def load_user(conn, uid: str) -> dict | None:
    cur = conn.cursor(cursor_factory=psycopg2.extras.RealDictCursor)
    cur.execute("""
        SELECT id, username, avatar_url, wrapped_early_access
        FROM users
        WHERE id = %s
    """, (uid,))
    row = cur.fetchone()
    cur.close()
    return dict(row) if row else None


def load_manual_logs(conn, uid: str) -> list[dict]:
    """Every manual log the user has (any year). The year window is applied in
    pandas by select_year_logs so it is compared in Asia/Riyadh.
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
            g.game_modes
        FROM library_entries le
        JOIN games g ON g.id = le.game_id
        WHERE le.user_id = %s
          AND le.source = %s
          AND le.logged_at IS NOT NULL
    """, (uid, WRAPPED_SOURCE))
    rows = [dict(row) for row in cur.fetchall()]
    cur.close()
    return rows


def load_trophy_unlocks(conn, uid: str) -> list[dict]:
    """Every unlocked achievement the user has on a manual log (any year).
    One row per (achievement, log): the same achievement can sit under several
    logs, so trophies_earned_card dedupes by achievement_id.
    """
    cur = conn.cursor(cursor_factory=psycopg2.extras.RealDictCursor)
    cur.execute("""
        SELECT
            ua.achievement_id,
            ua.unlocked_at,
            le.logged_at
        FROM user_achievements ua
        JOIN library_entries le ON le.id = ua.library_entry_id
        WHERE ua.user_id = %s
          AND ua.unlocked = true
          AND le.user_id = %s
          AND le.source = %s
    """, (uid, uid, WRAPPED_SOURCE))
    rows = [dict(row) for row in cur.fetchall()]
    cur.close()
    return rows


def load_games(conn, game_ids: list[int]) -> dict[int, dict]:
    """name, cover_image and background_image for the given games, in one query."""
    if not game_ids:
        return {}
    cur = conn.cursor(cursor_factory=psycopg2.extras.RealDictCursor)
    cur.execute("""
        SELECT id, name, cover_image, background_image
        FROM games
        WHERE id = ANY(%s)
    """, (list(game_ids),))
    games = {row["id"]: dict(row) for row in cur.fetchall()}
    cur.close()
    return games


def prepare_logs(rows: list[dict]) -> pd.DataFrame:
    """Rows → DataFrame with stable dtypes, even when empty.
    hours_played: Decimal/NULL → float (NULL = 0.0). logged_at → Asia/Riyadh.
    """
    df = pd.DataFrame(rows, columns=LOG_COLUMNS)
    df["hours_played"] = (
        df["hours_played"]
        .map(lambda h: 0.0 if h is None or pd.isna(h) else float(h))
        .astype("float64")
    )
    df["logged_at"] = pd.to_datetime(df["logged_at"], utc=True).dt.tz_convert(WRAPPED_TZ)
    df["game_id"] = df["game_id"].astype("int64")
    df["game_modes"] = df["game_modes"].map(parse_game_modes)
    return df


def parse_game_modes(raw) -> tuple[str, ...]:
    """games.game_modes → tuple of strings. The column is text[] (psycopg2
    gives a list), but a JSON array, a Postgres '{a,b}' literal or
    comma-separated text are accepted too. NULL/empty → ().
    """
    if raw is None or (not isinstance(raw, (list, tuple, str)) and pd.isna(raw)):
        return ()
    if isinstance(raw, str):
        text = raw.strip()
        if text.startswith("["):
            try:
                raw = json.loads(text)
            except ValueError:
                raw = text.strip("[]").split(",")
        else:
            raw = text.strip("{}").split(",")
    return tuple(str(m).strip().strip('"') for m in raw if m is not None and str(m).strip().strip('"'))


def is_online(game_modes: tuple[str, ...]) -> bool:
    """True when any mode contains an ONLINE_MODE_KEYWORDS entry, ignoring case."""
    return any(kw in mode.casefold() for mode in game_modes for kw in ONLINE_MODE_KEYWORDS)


def latest_log_per_game(year_logs: pd.DataFrame) -> pd.DataFrame:
    """Block D: each game's newest log in the year. Ties on logged_at go to the
    higher id (the later insert). Indexed by game_id.
    """
    return (
        year_logs.sort_values(["game_id", "logged_at", "id"], kind="mergesort")
        .groupby("game_id")
        .tail(1)
        .set_index("game_id")
    )


def select_year_logs(logs: pd.DataFrame, year: int, now: datetime | None = None) -> pd.DataFrame:
    """The year's counted logs: inside the Riyadh window, status not excluded."""
    start, end = year_window(year, now)
    in_window = (logs["logged_at"] >= start) & (logs["logged_at"] <= end)
    counted = ~logs["status"].isin(EXCLUDED_STATUSES)
    return logs[in_window & counted].reset_index(drop=True)


def game_hours(year_logs: pd.DataFrame) -> pd.Series:
    """Hours per game for the year: hours_played summed across every log of the
    game, indexed by game_id. NULL hours were already turned into 0.0 by
    prepare_logs, so a game with only NULL/0 logs is present with 0.0.
    """
    return year_logs.groupby("game_id")["hours_played"].sum().astype("float64")


def rank_top_games(year_logs: pd.DataFrame, per_game: pd.Series, limit: int = TOP_GAMES_LIMIT) -> pd.DataFrame:
    """The top games by hours, only games with more than 0 hours.

    Ties, in order: more logs in the year, then the most recent logged_at, then
    name A→Z. Hours are compared at 1 decimal (what the card shows), so float
    noise like 0.1 + 0.2 vs 0.3 can't decide the order.
    Returns columns game_id, hours, log_count, latest_logged_at, name.
    """
    stats = year_logs.groupby("game_id").agg(
        log_count=("id", "size"),
        latest_logged_at=("logged_at", "max"),
        name=("name", "first"),
    )
    ranked = stats.join(per_game.rename("hours"))
    ranked = ranked[ranked["hours"] > 0].assign(
        hours_key=lambda df: df["hours"].round(1),
        name_key=lambda df: df["name"].str.casefold(),
    )
    ranked = ranked.sort_values(
        ["hours_key", "log_count", "latest_logged_at", "name_key"],
        ascending=[False, False, False, True],
        kind="mergesort",
    )
    return (
        ranked.head(limit)
        .reset_index()[["game_id", "hours", "log_count", "latest_logged_at", "name"]]
    )


# --- Cards --------------------------------------------------------------------

def total_hours_card(per_game: pd.Series) -> float | None:
    """Card 1: total hours logged in the year, to 1 decimal. None when 0."""
    total = round(float(per_game.sum()), 1)
    return total if total > 0 else None  # checked after rounding on purpose: a "0.0 hours" card is pointless


def games_played_card(year_logs: pd.DataFrame) -> int:
    """Card 2: distinct games logged in the year (games, not play-throughs).
    Never skipped; games with only NULL/0-hour logs still count.
    """
    return int(year_logs["game_id"].nunique())


def top_games_card(ranked: pd.DataFrame, games: dict[int, dict]) -> list[dict] | None:
    """Card 3: up to TOP_GAMES_LIMIT games from rank_top_games, with name and
    cover from `games` (load_games). None when no game has hours.
    """
    if ranked.empty:
        return None
    items = []
    for game in ranked.itertuples(index=False):
        info = games.get(game.game_id, {})
        items.append({
            "game_id":     int(game.game_id),
            "name":        info.get("name") or game.name,
            "cover_image": info.get("cover_image") or info.get("background_image"),
            "hours":       round(float(game.hours), 1),
        })
    return items


def rank_top_online_game(year_logs: pd.DataFrame, per_game: pd.Series) -> pd.DataFrame:
    """The online game with the most hours, same ties as card 3. Empty when no
    online game has more than 0 hours. Games with no game_modes are not online.
    """
    online_logs = year_logs[year_logs["game_modes"].map(is_online)]
    return rank_top_games(online_logs, per_game, limit=1)


def top_online_game_card(ranked_online: pd.DataFrame, games: dict[int, dict]) -> dict | None:
    """Card 4: the single top online game, shaped like a top_games item."""
    items = top_games_card(ranked_online, games)
    return items[0] if items else None


def trophies_earned_card(unlocks: pd.DataFrame, year: int, now: datetime | None = None) -> int | None:
    """Card 5: achievements first unlocked inside the year window.

    unlocks has columns achievement_id, unlocked_at, logged_at (load_trophy_unlocks).
    Unlock date = unlocked_at, else the linked log's logged_at. Each
    achievement counts once, at its earliest unlock in any year, so one
    achievement under several logs isn't counted twice or again next year.
    None when the count is 0.
    """
    if unlocks.empty:
        return None
    unlocked_at = pd.to_datetime(unlocks["unlocked_at"], utc=True)
    logged_at = pd.to_datetime(unlocks["logged_at"], utc=True)
    first_unlock = (
        unlocks.assign(unlock_date=unlocked_at.fillna(logged_at).dt.tz_convert(WRAPPED_TZ))
        .dropna(subset=["unlock_date"])
        .groupby("achievement_id")["unlock_date"]
        .min()
    )
    start, end = year_window(year, now)
    count = int(((first_unlock >= start) & (first_unlock <= end)).sum())
    return count if count > 0 else None


def play_style_groups(year_logs: pd.DataFrame) -> pd.Series:
    """Sort each of the year's games into exactly one group, indexed by game_id:
    FINISHED if any log in the year is completed, else PAUSED if its latest
    log (block D) is paused, else PLAYING.
    """
    finished = (year_logs["status"] == "completed").groupby(year_logs["game_id"]).any()
    latest_status = latest_log_per_game(year_logs)["status"].reindex(finished.index)
    groups = pd.Series(PLAYING, index=finished.index)
    groups[latest_status == "paused"] = PAUSED
    groups[finished] = FINISHED
    return groups


def play_style_card(year_logs: pd.DataFrame) -> dict | None:
    """Card 6: play-style personality plus the finished/paused/playing counts.

    In order: fewer than 3 games → None; every game finished → credits_chaser;
    none finished → forever_in_progress; one group strictly biggest with at
    least 40% → its personality; otherwise (a tie, or under 40%) → None.
    """
    groups = play_style_groups(year_logs)
    counts = {g: int((groups == g).sum()) for g in (FINISHED, PAUSED, PLAYING)}
    total = sum(counts.values())
    if total < PLAY_STYLE_MIN_GAMES:
        return None

    if counts[FINISHED] == total:
        personality = "credits_chaser"
    elif counts[FINISHED] == 0:
        personality = "forever_in_progress"
    else:
        biggest = max(counts.values())
        leaders = [g for g, n in counts.items() if n == biggest]
        if len(leaders) > 1 or biggest / total < PLAY_STYLE_MIN_SHARE:
            return None
        personality = PERSONALITY_BY_GROUP[leaders[0]]

    return {"personality": personality, **counts}


# --- Response -----------------------------------------------------------------

def locked_response(year: int) -> dict:
    return {
        "year": year,
        "locked": True,
        "release_date": release_date(year).isoformat(),
    }


# Every card key, in response order. The unlocked response always carries all
# of them; a card that isn't built yet (or has nothing to show) is None.
CARD_KEYS = [
    "total_hours",
    "games_played",
    "top_games",
    "top_online_game",
    "trophies_earned",
    "play_style",
    "replay",
    "rating",
    "friends_hours",
    "similar_friend",
]


def build_wrapped(
    year: int,
    access: str,
    year_logs: pd.DataFrame,
    now: datetime | None = None,
    *,
    game_lookup: Callable[[list[int]], dict[int, dict]],
    trophy_lookup: Callable[[], list[dict]] | None = None,
) -> dict:
    """Assemble the unlocked response from the year's counted logs.
    game_lookup(game_ids) returns load_games-shaped info; it is called once,
    only when there are top games or a top online game to show.
    trophy_lookup() returns load_trophy_unlocks-shaped rows for this user;
    without it card 5 stays None.
    """
    start, end = year_window(year, now)
    response = {
        "year": year,
        "locked": False,
        "release_date": release_date(year).isoformat(),
        "is_partial": access == PARTIAL,
        "empty_state": year_logs.empty,
        "window": {
            "start": start.date().isoformat(),
            "end": end.date().isoformat(),
        },
        **{key: None for key in CARD_KEYS},
    }
    if year_logs.empty:
        response["games_played"] = 0
        return response

    per_game = game_hours(year_logs)
    response["total_hours"] = total_hours_card(per_game)
    response["games_played"] = games_played_card(year_logs)

    ranked = rank_top_games(year_logs, per_game)
    ranked_online = rank_top_online_game(year_logs, per_game)
    # One lookup for both cards' names and covers
    game_ids = list(dict.fromkeys(int(g) for g in pd.concat([ranked["game_id"], ranked_online["game_id"]])))
    games = game_lookup(game_ids) if game_ids else {}
    response["top_games"] = top_games_card(ranked, games)
    response["top_online_game"] = top_online_game_card(ranked_online, games)

    if trophy_lookup is not None:
        unlocks = pd.DataFrame(trophy_lookup(), columns=UNLOCK_COLUMNS)
        response["trophies_earned"] = trophies_earned_card(unlocks, year, now)

    response["play_style"] = play_style_card(year_logs)
    return response
