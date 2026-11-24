"""Step 1: match the survey's game names to the app's games (checkpoint).

1. Each entry gets a title by the recorded decision (survey_names.py).
2. The title is looked up in the app's games table (read-only): genres from game_genres,
   modes from games.game_modes.
3. Titles not in the table, or in it without modes, go to lookup_games.js: the app's RAWG
   search (title, genres) and the app's IGDB lookup (game_modes). Nothing is written.
4. online = the app's rule (wrapped.is_online: a mode containing multiplayer, battle royale or
   co-operative); multiplayer-only = online and no "Single player" mode.

    backend/recommender/.venv/bin/python notebooks/survey_validation/match_games.py
Writes notebooks/survey_validation/survey_game_matches.csv (one row per respondent x game;
IDs R01-R20, no timestamps) and survey_game_matches_distinct.csv (one row per raw name).
"""
from __future__ import annotations

import json
import re
import subprocess
import sys
import unicodedata
from pathlib import Path

import pandas as pd

HERE = Path(__file__).resolve().parent
REPO = HERE.parents[1]
sys.path.insert(0, str(HERE))
sys.path.insert(0, str(REPO / "backend" / "recommender"))

import survey_names as SN  # noqa: E402
import wrapped  # noqa: E402

SURVEY = REPO / "data" / "Gaming_Habits_Survey.csv"
SCRATCH = HERE / ".lookup"          # intermediate JSON, gitignored below


def title_key(s: str) -> str:
    s = unicodedata.normalize("NFKD", str(s)).encode("ascii", "ignore").decode().casefold()
    return re.sub(r"[^a-z0-9]", "", s)


def load_entries(path: Path = SURVEY) -> pd.DataFrame:
    """One row per respondent x listed game: respondent (R01..), slot, raw, hours, status, trophies.
    The five game blocks are the four columns after each 'Game n name' column."""
    d = pd.read_csv(path)
    name_cols = [c for c in d.columns if "name" in c.lower()]
    rows = []
    for i, r in d.iterrows():
        for slot, c in enumerate(name_cols, start=1):
            raw = r[c]
            if pd.isna(raw) or not str(raw).strip():
                continue
            k = d.columns.get_loc(c)
            rows.append({"respondent": f"R{i + 1:02d}", "slot": slot, "raw": str(raw).strip(),
                         "hours": r.iloc[k + 1], "status": r.iloc[k + 2], "trophies": r.iloc[k + 3]})
    return pd.DataFrame(rows)


def db_games() -> pd.DataFrame:
    from db import get_connection
    conn = get_connection()
    conn.set_session(readonly=True)
    try:
        cur = conn.cursor()
        cur.execute("""
            SELECT g.id, g.rawg_id, g.slug, g.name, g.released_at, g.rawg_rating_count,
                   COALESCE(g.game_modes, '{}') AS game_modes,
                   COALESCE(array_agg(gn.name) FILTER (WHERE gn.name IS NOT NULL), '{}') AS genres
            FROM games g
            LEFT JOIN game_genres gg ON gg.game_id = g.id
            LEFT JOIN genres gn ON gn.id = gg.genre_id
            GROUP BY g.id
        """)
        cols = [c[0] for c in cur.description]
        df = pd.DataFrame(cur.fetchall(), columns=cols)
        conn.rollback()
    finally:
        conn.close()
    df["key"] = df["name"].map(title_key)
    return df.sort_values("rawg_rating_count", ascending=False, na_position="last")


def main():
    entries = load_entries()
    dec = entries.apply(lambda r: SN.decide(r["respondent"], r["raw"]), axis=1, result_type="expand")
    entries[["title", "decision_confidence", "reason"]] = dec

    db = db_games()
    first = db.drop_duplicates("key")
    by_key = first.set_index("key")
    titles = sorted(entries["title"].unique())
    lookups, found = [], {}
    by_slug = db.drop_duplicates("slug").set_index("slug")
    for t in titles:
        k = title_key(t)
        if t in SN.NOT_FOUND:
            found[t] = {"source": "not found", "matched_title": None, "genres": [], "game_modes": [], "exact": False,
                        "note": SN.NOT_FOUND[t]}
            continue
        if t in SN.SLUG_PINS:
            slug, why = SN.SLUG_PINS[t]
            if slug in by_slug.index:
                g = by_slug.loc[slug]
                found[t] = {"source": "app games table (pinned slug)", "matched_title": g["name"], "genres": list(g["genres"]),
                            "game_modes": list(g["game_modes"]), "exact": True, "note": why}
                if not g["game_modes"]:
                    lookups.append({"title": t, "slug": slug, "released": str(g["released_at"] or ""), "need": "igdb"})
            else:
                lookups.append({"title": t, "slug": slug, "need": "rawg-slug+igdb", "note": why,
                                "igdb_slug": SN.IGDB_SLUG.get(t)})
            continue
        if k in by_key.index:
            g = by_key.loc[k]
            found[t] = {"source": "app games table", "matched_title": g["name"], "genres": list(g["genres"]),
                        "game_modes": list(g["game_modes"]), "exact": True}
            if not g["game_modes"]:
                lookups.append({"title": t, "slug": g["slug"], "released": str(g["released_at"] or ""), "need": "igdb"})
        else:
            lookups.append({"title": t, "need": "rawg+igdb"})

    SCRATCH.mkdir(exist_ok=True)
    (SCRATCH / "in.json").write_text(json.dumps(lookups, indent=2))
    subprocess.run(["node", str(HERE / "lookup_games.js"), str(SCRATCH / "in.json"), str(SCRATCH / "out.json")], check=True)
    for r in json.loads((SCRATCH / "out.json").read_text()):
        t = r["title"]
        if r["need"] == "rawg-slug+igdb":
            r["rawg_exact"] = bool(r.get("rawg_name"))   # pinned by slug: the right game by construction
        if r["need"] == "igdb":
            found[t]["game_modes"] = r.get("game_modes") or []
            found[t]["modes_source"] = f"IGDB ({r.get('igdb_method')})" if r.get("game_modes") is not None else "none found"
        else:
            found[t] = {"source": "RAWG search" if r.get("rawg_name") else "not found",
                        "matched_title": r.get("rawg_name"), "genres": r.get("genres") or [],
                        "game_modes": r.get("game_modes") or [], "exact": bool(r.get("rawg_exact")),
                        "released": r.get("released"),
                        "modes_source": f"IGDB ({r.get('igdb_method')})" if r.get("game_modes") is not None else "none found",
                        "error": r.get("error"), "note": r.get("note")}
        found[t]["igdb_name"] = r.get("igdb_name")

    rows = []
    for _, e in entries.iterrows():
        f = found.get(e["title"], {"source": "not found"})
        modes = f.get("game_modes") or []
        online = wrapped.is_online(tuple(modes))
        mp_only = online and not any("single" in m.casefold() for m in modes)
        override = SN.MODE_OVERRIDES.get(e["title"])
        if override:
            online, mp_only = override[0], override[1]
        # confidence = is this the right game; data gaps don't lower it (they're the app's data)
        conf = e["decision_confidence"]
        flags, gaps = [], []
        if f.get("source") == "not found" or not f.get("matched_title"):
            flags.append("no match: " + (f.get("note") or "lookup found nothing"))
        elif not f.get("exact"):
            flags.append("lookup returned a different title")
        if flags:
            conf = SN.LOW
        if f.get("matched_title") and not modes:
            gaps.append("no game modes (counts as offline)")
        if f.get("matched_title") and not f.get("genres"):
            gaps.append("no genres (left out of genre diversity)")
        rows.append({
            "respondent": e["respondent"], "slot": e["slot"], "raw name": e["raw"], "decided title": e["title"],
            "matched title": f.get("matched_title"), "source": f.get("source"), "released": f.get("released"),
            "genres": ";".join(f.get("genres") or []), "game_modes": ";".join(modes),
            "modes source": f.get("modes_source", "app games table" if modes else ""),
            "online": online, "multiplayer-only": mp_only, "confidence": conf,
            "decision": e["reason"] + (f" | {f['note']}" if f.get("note") and f.get("matched_title") else "")
                        + (f" | mode override: {override[2]}" if override else ""),
            "lookup flags": "; ".join(flags), "data gaps": "; ".join(gaps),
            "hours": e["hours"], "status": e["status"], "trophies": e["trophies"],
        })
    out = pd.DataFrame(rows)
    out.to_csv(HERE / "survey_game_matches.csv", index=False)
    distinct = (out.assign(key=out["raw name"].str.casefold())
                .groupby(["key", "decided title"], as_index=False)
                .agg(**{"raw name": ("raw name", "first"), "matched title": ("matched title", "first"),
                        "genres": ("genres", "first"), "online": ("online", "first"),
                        "multiplayer-only": ("multiplayer-only", "first"), "confidence": ("confidence", "first"),
                        "source": ("source", "first"), "decision": ("decision", "first"),
                        "lookup flags": ("lookup flags", "first"), "data gaps": ("data gaps", "first"),
                        "entries": ("respondent", "size")})
                .drop(columns="key"))
    distinct.to_csv(HERE / "survey_game_matches_distinct.csv", index=False)
    print(f"{len(out)} entries, {len(distinct)} distinct raw names (case-insensitive, split where series "
          f"decisions differ by respondent); low confidence: {int((out['confidence'] == SN.LOW).sum())} entries")
    print(out["source"].value_counts().to_string())


def alternatives():
    """The Step 3 alternative matches (SN.ALTERNATIVES), looked up the same way (RAWG search + IGDB),
    written to survey_game_matches_alternatives.csv."""
    items = [{"title": t, "need": "rawg+igdb", "respondent": rid, "raw_key": raw, "reason": why}
             for (rid, raw), (t, _slug, why) in SN.ALTERNATIVES.items()]
    SCRATCH.mkdir(exist_ok=True)
    (SCRATCH / "alt_in.json").write_text(json.dumps(items, indent=2))
    subprocess.run(["node", str(HERE / "lookup_games.js"), str(SCRATCH / "alt_in.json"), str(SCRATCH / "alt_out.json")], check=True)
    rows = []
    for r in json.loads((SCRATCH / "alt_out.json").read_text()):
        modes = r.get("game_modes") or []
        online = wrapped.is_online(tuple(modes))
        rows.append({"respondent": r["respondent"], "raw key": r["raw_key"], "alternative title": r["title"],
                     "matched title": r.get("rawg_name"), "exact": r.get("rawg_exact"), "genres": ";".join(r.get("genres") or []),
                     "game_modes": ";".join(modes), "online": online,
                     "multiplayer-only": online and not any("single" in m.casefold() for m in modes),
                     "reason": r["reason"], "error": r.get("error")})
    out = pd.DataFrame(rows)
    out.to_csv(HERE / "survey_game_matches_alternatives.csv", index=False)
    print(out[["respondent", "alternative title", "matched title", "exact", "genres", "game_modes", "online"]].to_string(index=False))


if __name__ == "__main__":
    main()
    alternatives()
