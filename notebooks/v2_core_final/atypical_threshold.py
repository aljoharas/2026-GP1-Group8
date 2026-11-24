"""Model 2.0.1 = 2.0.0 plus the atypical check. Nothing else changes: centres, scaler, imputation,
names, families, descriptions and temperature are copied as they are.

For each of the 3,333 training players (v2-core, seed 42; tables/v2core_training_features.csv
reproduces the model's own training shares exactly), the distance to the nearest centre in the
scaled space, exactly as the service scores. Stored:
  atypical_distance_threshold   the 95th percentile of those distances
  training_distance_quantiles   the 0th..100th percentiles (101 values), for distance_percentile
  atypical                      how it was computed

    python notebooks/v2_core_final/atypical_threshold.py
Rewrites models/archetype_model.json (refuses unless it is 2.0.0 or 2.0.1).
"""
import json
import sys
from pathlib import Path

import numpy as np
import pandas as pd

REPO = Path(__file__).resolve().parents[2]
MODEL = REPO / "models" / "archetype_model.json"
TRAIN = REPO / "notebooks" / "survey_validation" / "tables" / "v2core_training_features.csv"
PERCENTILE = 95


def nearest_distances(X: pd.DataFrame, m: dict) -> np.ndarray:
    x = X[m["features"]].fillna(pd.Series(m["imputation"])).to_numpy(dtype=float)
    z = (x - np.array(m["scaler"]["mean"])) / np.array(m["scaler"]["scale"])
    c = np.array([cl["centre_scaled"] for cl in m["clusters"]])
    d = np.sqrt(((z[:, None, :] - c[None, :, :]) ** 2).sum(axis=2))
    return d, d.min(axis=1)


def main():
    m = json.loads(MODEL.read_text())
    if m["version"] not in ("2.0.0", "2.0.1"):
        sys.exit(f"expected model 2.0.0 or 2.0.1, found {m['version']}")
    X = pd.read_csv(TRAIN)
    d, nearest = nearest_distances(X, m)
    shares = np.round(np.bincount(d.argmin(axis=1), minlength=len(m["clusters"])) / len(X), 4)
    assert np.allclose(shares, [c["training_share"] for c in m["clusters"]]), "not the training population"
    out = dict(m)
    out["version"] = "2.0.1"
    out["atypical_distance_threshold"] = float(np.percentile(nearest, PERCENTILE))
    out["training_distance_quantiles"] = [float(q) for q in np.percentile(nearest, np.arange(101))]
    out["atypical"] = {
        "method": f"{PERCENTILE}th percentile of the training players' distance to their nearest centre "
                  "(scaled space, as scored); a user beyond it is flagged atypical and gets no blend",
        "percentile": PERCENTILE,
        "training_players": int(len(X)),
        "flagged_share_of_training": float((nearest > out["atypical_distance_threshold"]).mean()),
    }
    MODEL.write_text(json.dumps(out, indent=2) + "\n")
    print(f"2.0.1: threshold {out['atypical_distance_threshold']:.4f} "
          f"(flags {out['atypical']['flagged_share_of_training']:.2%} of training players)")


if __name__ == "__main__":
    main()
