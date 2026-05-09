"""
Content-based recommender for Loadout.

Feature vector layout (per game, fixed-length):
  [genre_0  ... genre_N   (one-hot),  N = distinct genres  (game_genres table)
   theme_0  ... theme_M   (one-hot),  M = distinct IGDB themes
   mode_0   ... mode_K    (one-hot),  K = distinct IGDB game_modes
   metacritic_norm,                   0.0–1.0  (NULL → 0.5 neutral)
   rawg_rating_norm]                  0.0–1.0  (rawg_rating is 0–5)

Theme and mode columns are all-zero for games not yet enriched via IGDB —
the recommender still works, it just improves as enrichment covers more games.

User taste profile:
  Weighted average of feature vectors for games the user has interacted with.
  Negative weights (low ratings) push disliked genres/themes away.

Ratings are on a 0–10 scale. 6 is neutral; above is positive, below is negative.
"""

import numpy as np
from scipy.sparse import csr_matrix
from sklearn.metrics.pairwise import cosine_similarity
from sklearn.neighbors import NearestNeighbors


def _entry_weight(user_rating, is_favorite, status):
    """
    Returns a signed weight for a library entry.
    user_rating is 0–10: (rating - 6) / 4 maps to [-1.5, +1.0].
    Status and favorite provide a base multiplier when no rating exists.
    """
    if user_rating is not None:
        # Continuous signed weight: 10 → +1.0, 6 → 0.0, 0 → -1.5
        base = (float(user_rating) - 6.0) / 4.0  # cast handles Decimal from psycopg2
        # Favorites boost the signal; they can't make a bad rating positive
        return base + (0.5 if is_favorite else 0.0)
    if is_favorite:
        return 2.5
    if status == "completed":
        return 1.0
    return 0.5  # playing or unknown


def build_feature_matrix(games, all_genre_ids, all_theme_names=None, all_mode_names=None):
    """
    games: list of dicts — id, metacritic_score, rawg_rating, genre_ids (list[int]),
           themes (list[str] or None), game_modes (list[str] or None)
    all_genre_ids:    sorted list of genre IDs from the game_genres table
    all_theme_names:  sorted list of distinct IGDB theme name strings (optional)
    all_mode_names:   sorted list of distinct IGDB game_mode name strings (optional)

    Returns numpy float32 array of shape:
      (len(games), n_genres + n_themes + n_modes + 2)
    """
    all_theme_names = all_theme_names or []
    all_mode_names = all_mode_names or []

    genre_index = {gid: i for i, gid in enumerate(all_genre_ids)}
    theme_index = {t: i for i, t in enumerate(all_theme_names)}
    mode_index  = {m: i for i, m in enumerate(all_mode_names)}

    n_genres = len(all_genre_ids)
    n_themes = len(all_theme_names)
    n_modes  = len(all_mode_names)
    n_features = n_genres + n_themes + n_modes + 2

    matrix = np.zeros((len(games), n_features), dtype=np.float32)

    for row, game in enumerate(games):
        # Genres (one-hot) — columns 0 … n_genres-1
        for gid in (game.get("genre_ids") or []):
            col = genre_index.get(gid)
            if col is not None:
                matrix[row, col] = 1.0

        # Themes (one-hot) — columns n_genres … n_genres+n_themes-1
        for theme in (game.get("themes") or []):
            col = theme_index.get(theme)
            if col is not None:
                matrix[row, n_genres + col] = 1.0

        # Game modes (one-hot) — columns n_genres+n_themes … n_genres+n_themes+n_modes-1
        for mode in (game.get("game_modes") or []):
            col = mode_index.get(mode)
            if col is not None:
                matrix[row, n_genres + n_themes + col] = 1.0

        # Quality features are scaled down so they don't dominate cosine similarity
        # over the binary one-hot genre/theme/mode columns (otherwise any high-rated
        # game looks similar to every user's profile)
        QUALITY_WEIGHT = 0.15

        # Metacritic — second-to-last column
        mc = game.get("metacritic_score")
        matrix[row, n_genres + n_themes + n_modes] = QUALITY_WEIGHT * ((float(mc) / 100.0) if mc is not None else 0.5)

        # RAWG rating — last column
        rr = game.get("rawg_rating")
        matrix[row, n_genres + n_themes + n_modes + 1] = QUALITY_WEIGHT * ((float(rr) / 5.0) if rr is not None else 0.5)

    return matrix


def compute_taste_profile(user_library, game_id_to_row, matrix):
    """
    Returns a 1-D numpy array (the user's taste profile),
    or None on cold start (no usable library data).
    """
    weighted_sum = None
    total_abs_weight = 0.0

    for entry in user_library:
        row = game_id_to_row.get(entry["game_id"])
        if row is None:
            continue

        w = _entry_weight(entry["user_rating"], entry["is_favorite"], entry["status"])
        vec = matrix[row]

        weighted_sum = w * vec if weighted_sum is None else weighted_sum + w * vec
        total_abs_weight += abs(w)

    if weighted_sum is None or total_abs_weight == 0:
        return None

    return weighted_sum / total_abs_weight


def build_item_similarity(all_user_libraries, all_game_ids, top_k=50):
    """
    Item-based CF: precompute the top_k most similar games to each game,
    using cosine similarity over the user × game rating matrix.

    Two games are similar when many users rated them similarly (positive
    weights for liked, negative for disliked). Pure CF — no genre/theme
    content used here.

    Returns dict {game_id: [(other_game_id, similarity), ...]} where the
    list is sorted by similarity descending, length up to top_k, and only
    positive similarities are kept.
    """
    if not all_user_libraries or not all_game_ids:
        return {}

    user_ids = list(all_user_libraries.keys())
    game_idx = {gid: i for i, gid in enumerate(all_game_ids)}
    n_users = len(user_ids)
    n_games = len(all_game_ids)

    # Build sparse user × game weight matrix
    rows, cols, data = [], [], []
    for u_idx, uid in enumerate(user_ids):
        for entry in all_user_libraries[uid]:
            g_idx = game_idx.get(entry["game_id"])
            if g_idx is None:
                continue
            w = _entry_weight(entry["user_rating"], entry["is_favorite"], entry["status"])
            if w == 0:
                continue
            rows.append(u_idx)
            cols.append(g_idx)
            data.append(w)

    if not data:
        return {}

    R = csr_matrix(
        (np.array(data, dtype=np.float32), (rows, cols)),
        shape=(n_users, n_games),
    )

    # Item-item nearest neighbors over the transposed (game × user) matrix
    k = min(top_k + 1, n_games)  # +1 because each game is its own nearest neighbor
    nn = NearestNeighbors(n_neighbors=k, metric="cosine", algorithm="brute")
    nn.fit(R.T)
    distances, indices = nn.kneighbors(R.T)

    similar_items = {}
    for i, gid in enumerate(all_game_ids):
        pairs = []
        for d, j in zip(distances[i], indices[i]):
            if j == i:
                continue
            sim = 1.0 - float(d)
            if sim > 0:
                pairs.append((all_game_ids[j], sim))
        similar_items[gid] = pairs
    return similar_items


def item_collab_scores(user_library, item_similarity, candidate_game_ids):
    """
    Item-based CF score for each candidate game:
        score(c) = Σ sim(c, g) × weight(g)  for g in user library
                 / Σ |sim(c, g)|             (so high-similarity items dominate)

    Negative similarities and library weights both contribute — a candidate
    similar to games the user disliked gets pushed down.

    Returns dict {game_id: float} with values mapped to [0, 1] (negatives clipped).
    """
    if not item_similarity or not user_library:
        return {}

    candidate_set = set(candidate_game_ids)
    weighted_sum = {}
    sim_norm = {}

    for entry in user_library:
        gid = entry["game_id"]
        w = _entry_weight(entry["user_rating"], entry["is_favorite"], entry["status"])
        if w == 0:
            continue
        for sim_gid, sim in item_similarity.get(gid, []):
            if sim_gid not in candidate_set:
                continue
            weighted_sum[sim_gid] = weighted_sum.get(sim_gid, 0.0) + sim * w
            sim_norm[sim_gid] = sim_norm.get(sim_gid, 0.0) + abs(sim)

    if not weighted_sum:
        return {}

    raw = {gid: weighted_sum[gid] / sim_norm[gid] for gid in weighted_sum if sim_norm[gid] > 0}
    if not raw:
        return {}

    # Clip negatives to 0 (CF abstains rather than fights content) then scale to [0, 1]
    clipped = {gid: max(0.0, v) for gid, v in raw.items()}
    max_val = max(clipped.values())
    if max_val == 0:
        return {}
    return {gid: v / max_val for gid, v in clipped.items()}


def recommend(all_games, all_genre_ids, user_library, user_library_game_ids, top_n=10,
              matrix=None, game_id_to_row=None,
              item_similarity=None, alpha=0.7):
    """
    Hybrid recommender: blends content-based (alpha) and item-based CF (1-alpha) scores.
    Returns a list of game dicts (up to top_n), or [] on cold start.

    Pass matrix and game_id_to_row to use a pre-built cached matrix (avoids
    rebuilding on every request). When omitted they are built from all_games.
    """
    if not all_games:
        return []

    if matrix is None or game_id_to_row is None:
        matrix = build_feature_matrix(all_games, all_genre_ids)
        game_id_to_row = {g["id"]: i for i, g in enumerate(all_games)}

    profile = compute_taste_profile(user_library, game_id_to_row, matrix)
    if profile is None:
        return []

    # Candidates: not in library and present in the matrix
    candidates = [g for g in all_games if g["id"] not in user_library_game_ids and g["id"] in game_id_to_row]
    if not candidates:
        return []

    candidate_indices = [game_id_to_row[g["id"]] for g in candidates]
    content_raw = cosine_similarity(profile.reshape(1, -1), matrix[candidate_indices])[0]

    # Clip content scores to [0, 1] — orthogonal/opposite means "no relation", not "worst available"
    content_norm = np.clip(content_raw, 0.0, 1.0)

    # Item-based CF
    if item_similarity:
        candidate_game_ids = [g["id"] for g in candidates]
        collab_map = item_collab_scores(user_library, item_similarity, candidate_game_ids)
        collab_arr = np.array([collab_map.get(g["id"], 0.0) for g in candidates], dtype=np.float32)
        final_scores = alpha * content_norm + (1.0 - alpha) * collab_arr
    else:
        final_scores = content_norm

    sorted_games = [g for _, g in sorted(zip(final_scores, candidates), key=lambda x: x[0], reverse=True)]
    return sorted_games[:top_n]
