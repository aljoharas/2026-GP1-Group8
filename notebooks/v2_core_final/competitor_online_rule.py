"""Model 2.0.2 = 2.0.1 plus one post-cluster rule: a user whose online share is below
competitor_min_online_share cannot be Competitor. Centres, scaler, imputation, names, families,
descriptions, temperature and the atypical threshold are copied as they are.

Why: Competitor's own definition is online ("Online, competitive, and in it for the long
sessions"; centre online_share 0.77), but it sits between the other centres, so an offline user
with long per-game hours can still be nearest to it.

The threshold is taken from the training data, the same way as the atypical threshold: the 5th
percentile of online_share among the v2-core training players (v2core_training_features.csv,
3,333 players, seed 42) whose nearest centre is Competitor. Stored:
  competitor_min_online_share   that percentile
  competitor_online_rule        what the rule does and how the threshold was computed

    python notebooks/v2_core_final/competitor_online_rule.py
Rewrites models/archetype_model.json (refuses unless it is 2.0.1 or 2.0.2).
"""
import json
import sys
from pathlib import Path

import numpy as np
import pandas as pd

from atypical_threshold import MODEL, TRAIN, nearest_distances

PERCENTILE = 5
ARCHETYPE = "Competitor"


def main():
    m = json.loads(MODEL.read_text())
    if m["version"] not in ("2.0.1", "2.0.2"):
        sys.exit(f"expected model 2.0.1 or 2.0.2, found {m['version']}")
    X = pd.read_csv(TRAIN)
    d, _ = nearest_distances(X, m)
    nearest = d.argmin(axis=1)
    shares = np.round(np.bincount(nearest, minlength=len(m["clusters"])) / len(X), 4)
    assert np.allclose(shares, [c["training_share"] for c in m["clusters"]]), "not the training population"

    competitor = [c["name"] for c in m["clusters"]].index(ARCHETYPE)
    online = X.loc[nearest == competitor, "online_share"].to_numpy(dtype=float)
    threshold = float(np.percentile(online, PERCENTILE))

    out = dict(m)
    out["version"] = "2.0.2"
    out["competitor_min_online_share"] = threshold
    out["competitor_online_rule"] = {
        "rule": f"post-cluster: a user with online_share below competitor_min_online_share cannot be "
                f"{ARCHETYPE}; the softmax, percentages, blend and atypical check run over the other "
                f"archetypes (nearest remaining centre), and {ARCHETYPE} is listed last at 0%",
        "why": f"{ARCHETYPE} is defined by online play (centre online_share "
               f"{m['clusters'][competitor]['centre']['online_share']:.2f}), but its centre sits between "
               "the others, so offline users with long per-game hours could land on it",
        "method": f"{PERCENTILE}th percentile of online_share among the training players whose nearest "
                  f"centre is {ARCHETYPE}",
        "percentile": PERCENTILE,
        "training_players": int(len(X)),
        "competitor_players": int(len(online)),
    }
    MODEL.write_text(json.dumps(out, indent=2) + "\n")
    print(f"2.0.2: competitor_min_online_share {threshold:.4f} "
          f"({len(online)} Competitor-nearest training players)")


if __name__ == "__main__":
    main()
