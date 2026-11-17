"""Real users (read-only) with the served v1 model and the v2-core draft, the latter at each
candidate temperature. Same data path as /archetype. Anonymised output:
notebooks/v2_core_final/real_users.csv

    backend/recommender/.venv/bin/python notebooks/v2_core_real_users.py
"""
import copy
import sys
from pathlib import Path

import pandas as pd

REPO = Path(__file__).resolve().parents[1]
sys.path.insert(0, str(REPO / "backend" / "recommender"))

import archetypes  # noqa: E402
import wrapped  # noqa: E402
from db import get_connection  # noqa: E402

TEMPERATURES = [0.5, 0.6, 0.75, 1.0]
OUT = REPO / "notebooks" / "v2_core_final"
V1 = archetypes.load_model(REPO / "models" / "archetype_model_v1.json")
DRAFT = archetypes.load_model(OUT / "archetype_model_v2_core_draft.json")


def user_games(conn):
    cur = conn.cursor()
    cur.execute("""
        SELECT user_id, COUNT(DISTINCT game_id) FROM library_entries
        WHERE source = %s AND logged_at IS NOT NULL AND status <> ALL(%s)
        GROUP BY user_id HAVING COUNT(DISTINCT game_id) >= %s
    """, (wrapped.WRAPPED_SOURCE, list(wrapped.EXCLUDED_STATUSES), V1["min_games"]))
    uids = sorted(u for u, _ in cur.fetchall())
    cur.close()
    for uid in uids:
        logs = archetypes.load_manual_logs(conn, uid)
        ids = sorted(int(g) for g in logs["game_id"].unique())
        games, _ = archetypes.build_games(logs, wrapped.load_game_genres(conn, ids),
                                          archetypes.load_achievement_list_sizes(conn, ids))
        yield games


def top2(resp):
    s = resp["scores"]
    return f"{s[0]['archetype']} {s[0]['percent']}% / {s[1]['archetype']} {s[1]['percent']}%"


def main():
    conn = get_connection()
    conn.set_session(readonly=True, autocommit=False)
    rows = []
    try:
        for n, games in enumerate(user_games(conn), start=1):
            a = archetypes.archetype_response(games, V1)
            row = {"user": f"user {n}", "games": len(games), "v1 (T = 0.75)": top2(a)}
            for T in TEMPERATURES:
                m = copy.copy(DRAFT)
                m["scoring"] = {**DRAFT["scoring"], "temperature": T}
                b = archetypes.archetype_response(games, m)
                row[f"v2-core T = {T}"] = top2(b)
                row[f"top % T = {T}"] = b["scores"][0]["percent"]
            row["v2-core archetype"] = b["archetype"]
            row["changed vs v1"] = b["archetype"] != a["archetype"]
            rows.append(row)
        conn.rollback()
    finally:
        conn.close()
    out = pd.DataFrame(rows)
    out.to_csv(OUT / "real_users.csv", index=False)
    pd.set_option("display.width", 250)
    print(out.T.to_string())


if __name__ == "__main__":
    main()
