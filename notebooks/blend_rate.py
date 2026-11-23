"""Blend rate under the family-agnostic rule (top two within 10 points), through the served
code path: archetypes.archetype_response with the served 2.0.0 model.

- the 3,333 training players (v2-core, 500 per persona, seed 42), from their games
- the real users with >= 5 manual-log games (read-only session, anonymised)

    python notebooks/blend_rate.py      (needs DATABASE_URL for the real users)
Writes notebooks/blend_rate/.
"""
import json
import sys
from pathlib import Path

import pandas as pd

sys.path.insert(0, str(Path(__file__).resolve().parent))
import archetype_v2_lib as L  # noqa: E402

sys.path.insert(0, str(L.REPO / "backend" / "recommender"))
import archetypes  # noqa: E402
import wrapped  # noqa: E402
from db import get_connection  # noqa: E402

OUT = L.REPO / "notebooks" / "blend_rate"
OUT.mkdir(exist_ok=True)
MODEL = archetypes.load_model()
assert MODEL["version"] == "2.0.0"
FAMILY = {c["name"]: c["family"] for c in MODEL["clusters"]}
CORE = L.sim2.rules_variant(rule5_trophy_hunters={"on": False})


def summarise(bodies):
    rows = []
    for b in bodies:
        s = b["scores"]
        rows.append({"archetype": b["archetype"], "second": s[1]["archetype"], "gap": s[0]["percent"] - s[1]["percent"],
                     "blend": b["blend"] is not None,
                     "same_family": FAMILY[s[0]["archetype"]] == FAMILY[s[1]["archetype"]]})
    return pd.DataFrame(rows)


# Training players
plays, cal, CAT, _, _ = L.load_inputs(L.REPO / "data" / "steam-200k.csv", L.REPO / "data" / "steam_catalogue.csv")
players = L.sim2.generate_players(cal, CAT, 500, L.MIX_SHARE, L.SEED, CORE)
# Simulated games carry their title as _name; the reason sentences read name
sim_df = summarise(archetypes.archetype_response([{**g, "name": g["_name"]} for g in p["games"]], MODEL)
                   for p in players)
sim_df["group"] = ["mixed" if p["persona"].startswith("mixed:") else p["persona"] for p in players]
blends = sim_df[sim_df["blend"]]
pairs = blends.apply(lambda r: f"{r['archetype']} → {r['second']}", axis=1).value_counts()
by_arch = sim_df.groupby("archetype")["blend"].agg(["size", "mean"]).rename(columns={"size": "players", "mean": "blend rate"})
by_group = sim_df.groupby("group")["blend"].mean().rename("blend rate")
sim = {
    "players": len(sim_df), "blends": int(sim_df["blend"].sum()), "rate": float(sim_df["blend"].mean()),
    "same_family_blends": int(blends["same_family"].sum()), "cross_family_blends": int((~blends["same_family"]).sum()),
    "old_rule_blends": int(blends["same_family"].sum()),
    "pairs": pairs.to_dict(), "by_archetype": by_arch.to_dict("index"), "by_group": by_group.to_dict(),
}
by_arch.round(4).to_csv(OUT / "training_by_archetype.csv")
pairs.to_csv(OUT / "training_pairs.csv")
print(f"training: {sim['blends']} of {sim['players']} blend ({sim['rate']:.1%}); same-family {sim['same_family_blends']}, "
      f"cross-family {sim['cross_family_blends']} (the old rule gave {sim['old_rule_blends']})")
print(by_arch.round(3).to_string())
print(by_group.round(3).to_string())
print(pairs.head(10).to_string())

# Real users, read-only
conn = get_connection()
conn.set_session(readonly=True, autocommit=False)
real = []
try:
    cur = conn.cursor()
    cur.execute("""
        SELECT user_id FROM library_entries
        WHERE source = %s AND logged_at IS NOT NULL AND status <> ALL(%s)
        GROUP BY user_id HAVING COUNT(DISTINCT game_id) >= %s ORDER BY user_id
    """, (wrapped.WRAPPED_SOURCE, list(wrapped.EXCLUDED_STATUSES), MODEL["min_games"]))
    uids = [r[0] for r in cur.fetchall()]
    cur.close()
    for n, uid in enumerate(uids, 1):
        logs = archetypes.load_manual_logs(conn, uid)
        ids = sorted(int(g) for g in logs["game_id"].unique())
        games, _ = archetypes.build_games(logs, wrapped.load_game_genres(conn, ids),
                                          archetypes.load_achievement_list_sizes(conn, ids))
        b = archetypes.archetype_response(games, MODEL)
        s = b["scores"]
        real.append({"user": f"user {n}", "games": len(games),
                     "top two": f"{s[0]['archetype']} {s[0]['percent']}% / {s[1]['archetype']} {s[1]['percent']}%",
                     "gap": s[0]["percent"] - s[1]["percent"], "family": b["family"],
                     "blend": (f"{b['blend']['primary']}, with a touch of {b['blend']['secondary']}"
                               if b["blend"] else None)})
    conn.rollback()
finally:
    conn.close()
real_df = pd.DataFrame(real)
real_df.to_csv(OUT / "real_users.csv", index=False)
print(real_df.to_string(index=False))

(OUT / "results.json").write_text(json.dumps({
    "rule": "blend when the top two archetypes are within 10 points, any family",
    "training": sim, "real_users": {"n": len(real_df), "blends": int(real_df["blend"].notna().sum()),
                                    "rows": real_df.to_dict("records")},
}, indent=2, default=float) + "\n")
print("wrote", OUT.relative_to(L.REPO))
