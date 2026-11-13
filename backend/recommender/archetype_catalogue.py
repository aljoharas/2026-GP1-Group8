"""
Player Archetypes — the real-game catalogue used by simulator v2.

Training only. Built from the Kaggle "Steam Store Games (Clean dataset)" steam.csv
(nikdavis, SteamSpy data, 2019) and Steam 200k (for popularity). The committed
output is data/steam_catalogue.csv; the generator only reads that file, so Colab
does not need the 6 MB Kaggle file.

Per game:
    appid, name
    genres               RAWG genre names, ";"-joined (GENRE_MAP + TAG_MAP below)
    is_online            categories include any of ONLINE_CATEGORIES
    is_multiplayer_only  is_online and no "Single-player" category
    achievement_count    size of the Steam achievement list (0 = no list)
    typical_length_h     SteamSpy median_playtime in hours, clipped to LENGTH_CLIP;
                         NaN when median_playtime is 0 (no data)
    steam200k_players    Steam 200k users with play hours > 0 on the title (0 = not matched)
"""

from __future__ import annotations

import re
import unicodedata

import numpy as np
import pandas as pd

from archetype_sim import GENRES

ONLINE_CATEGORIES = {"Multi-player", "Online Multi-Player", "Online PvP", "MMO", "Online Co-op"}
SINGLE_PLAYER = "Single-player"
LENGTH_CLIP = (1.0, 150.0)  # hours

# Steam store genre -> RAWG genre. Steam genres with no RAWG equivalent are dropped:
# business models (Early Access, Free to Play), content descriptors (Violent, Gore,
# Nudity, Sexual Content) and software (Utilities, Design & Illustration, ...).
GENRE_MAP = {
    "Action": "Action", "Adventure": "Adventure", "Casual": "Casual", "Indie": "Indie",
    "Massively Multiplayer": "Massively Multiplayer", "Racing": "Racing", "RPG": "RPG",
    "Simulation": "Simulation", "Sports": "Sports", "Strategy": "Strategy",
    "Education": "Educational",
}
# Eight RAWG genres are not Steam store genres at all. RAWG imports Steam user tags,
# so they are taken from steamspy_tags (the game's top user tags).
TAG_MAP = {
    "FPS": "Shooter", "Shooter": "Shooter", "Shoot 'Em Up": "Shooter", "Third-Person Shooter": "Shooter",
    "Puzzle": "Puzzle", "Arcade": "Arcade", "Platformer": "Platformer", "Fighting": "Fighting",
    "Family Friendly": "Family", "Board Game": "Board Games", "Card Game": "Card",
    "Education": "Educational",
}
assert set(GENRE_MAP.values()) | set(TAG_MAP.values()) == set(GENRES)

# Steam 200k lists separate clients ("... - Multiplayer", "... Beta") that are the
# same store product
_CLIENT_SUFFIX = re.compile(r"\s*(-\s*(multiplayer|single ?player)|beta)\s*$", re.IGNORECASE)


def title_key(name: str) -> str:
    """Case-, accent-, symbol- and space-insensitive title key (™, ®, ':' ignored)."""
    s = unicodedata.normalize("NFKD", str(name)).encode("ascii", "ignore").decode().casefold()
    return re.sub(r"[^a-z0-9]", "", s)


def _split(value) -> list[str]:
    return [] if pd.isna(value) or value == "" else str(value).split(";")


def rawg_genres(steam_genres, tags) -> list[str]:
    out = [GENRE_MAP[g] for g in _split(steam_genres) if g in GENRE_MAP]
    out += [TAG_MAP[t] for t in _split(tags) if t in TAG_MAP]
    return [g for g in GENRES if g in set(out)]  # RAWG order, no duplicates


def match_steam200k(store: pd.DataFrame, plays: pd.DataFrame) -> pd.DataFrame:
    """Steam 200k title -> appid. Exact title_key match first, then with a client
    suffix removed. Ties between store entries with the same key go to the
    most-owned one. Returns columns game, appid (NaN = no match), players.
    """
    owners_low = store["owners"].str.split("-").str[0].astype(int)
    ranked = store.assign(_own=owners_low).sort_values("_own", ascending=False, kind="stable")
    by_key = {}
    for key, appid in zip(ranked["name"].map(title_key), ranked["appid"]):
        by_key.setdefault(key, int(appid))
    players = plays.groupby("game")["user_id"].nunique()
    rows = []
    for game, n in players.items():
        appid = by_key.get(title_key(game)) or by_key.get(title_key(_CLIENT_SUFFIX.sub("", game)))
        rows.append({"game": game, "appid": appid, "players": int(n)})
    return pd.DataFrame(rows)


def build_catalogue(store: pd.DataFrame, plays: pd.DataFrame) -> tuple[pd.DataFrame, pd.DataFrame]:
    """(catalogue, steam200k_matches). Games with no RAWG genre (software, or only
    content-descriptor genres) are dropped: the generator draws games by genre.
    """
    matches = match_steam200k(store, plays)
    pop = matches.dropna(subset=["appid"]).groupby("appid")["players"].sum()

    cats = store["categories"].map(lambda c: set(_split(c)))
    is_online = cats.map(lambda c: bool(c & ONLINE_CATEGORIES))
    minutes = store["median_playtime"].astype(float)
    length = (minutes / 60).where(minutes > 0).clip(*LENGTH_CLIP)

    cat = pd.DataFrame({
        "appid": store["appid"].astype(int),
        "name": store["name"],
        "genres": [";".join(rawg_genres(g, t)) for g, t in zip(store["genres"], store["steamspy_tags"])],
        "is_online": is_online,
        "is_multiplayer_only": is_online & ~cats.map(lambda c: SINGLE_PLAYER in c),
        "achievement_count": store["achievements"].astype(int),
        "typical_length_h": length,
        "median_playtime_raw_h": minutes / 60,
        "steam200k_players": store["appid"].map(pop).fillna(0).astype(int),
    })
    cat = cat[cat["genres"] != ""].reset_index(drop=True)
    return cat, matches


def load_catalogue(path) -> pd.DataFrame:
    """data/steam_catalogue.csv as the generator uses it: games with a typical
    length and at least one Steam 200k player (popularity weight > 0).
    """
    cat = pd.read_csv(path)
    cat = cat[cat["typical_length_h"].notna() & (cat["steam200k_players"] > 0)].reset_index(drop=True)
    cat["genre_list"] = cat["genres"].str.split(";")
    return cat
