"""
Loadout Recommender — FastAPI microservice (port 8000).
Node.js verifies Firebase tokens before calling this service,
so no auth is performed here.

The feature matrix is built once at startup and cached in memory.
Call POST /refresh after ingesting new games to rebuild it.

User-library data for collaborative filtering is fetched fresh per request
but cached for _COLLAB_TTL seconds to avoid hammering the DB.
"""

import time
from contextlib import asynccontextmanager
from fastapi import FastAPI, HTTPException, Query
from fastapi.responses import JSONResponse
import psycopg2.extras

from db import get_connection
from recommender import build_feature_matrix, build_item_similarity, recommend

# --- Shared state loaded at startup -------------------------------------------

_state = {
    "all_games": [],
    "all_genre_ids": [],
    "all_theme_names": [],
    "all_mode_names": [],
    "matrix": None,
    "game_id_to_row": {},
}

# Collaborative filtering cache — rebuilt every _COLLAB_TTL seconds
_COLLAB_TTL = 300  # 5 minutes
_collab_cache = {
    "timestamp": 0.0,
    "item_similarity": {},  # {game_id: [(other_game_id, sim), ...]}
}


def _load_matrix():
    """Query the DB and rebuild the feature matrix. Called at startup and on /refresh."""
    conn = get_connection()
    try:
        cur = conn.cursor(cursor_factory=psycopg2.extras.RealDictCursor)

        cur.execute("SELECT id FROM genres ORDER BY id")
        all_genre_ids = [row["id"] for row in cur.fetchall()]

        # Distinct IGDB themes and game_modes (populated after running enrich_igdb.py)
        cur.execute("""
            SELECT DISTINCT unnest(themes) AS t FROM games
            WHERE themes IS NOT NULL AND themes <> '{}'
            ORDER BY t
        """)
        all_theme_names = [row["t"] for row in cur.fetchall()]

        cur.execute("""
            SELECT DISTINCT unnest(game_modes) AS m FROM games
            WHERE game_modes IS NOT NULL AND game_modes <> '{}'
            ORDER BY m
        """)
        all_mode_names = [row["m"] for row in cur.fetchall()]

        cur.execute("""
            SELECT
                g.id,
                g.rawg_id,
                g.name,
                g.background_image,
                g.rawg_rating,
                g.rawg_rating_count,
                g.metacritic_score,
                COALESCE(g.themes, '{}')     AS themes,
                COALESCE(g.game_modes, '{}') AS game_modes,
                COALESCE(
                    array_agg(gg.genre_id) FILTER (WHERE gg.genre_id IS NOT NULL),
                    ARRAY[]::int[]
                ) AS genre_ids,
                array_agg(DISTINCT ge.name) FILTER (WHERE ge.name IS NOT NULL) AS genres,
                array_agg(DISTINCT p.name)  FILTER (WHERE p.name IS NOT NULL)  AS platforms
            FROM games g
            LEFT JOIN game_genres gg    ON g.id = gg.game_id
            LEFT JOIN genres ge         ON gg.genre_id = ge.id
            LEFT JOIN game_platforms gp ON g.id = gp.game_id
            LEFT JOIN platforms p       ON gp.platform_id = p.id
            GROUP BY g.id
        """)
        all_games = [dict(row) for row in cur.fetchall()]
        cur.close()
    finally:
        conn.close()

    matrix = build_feature_matrix(all_games, all_genre_ids, all_theme_names, all_mode_names)
    game_id_to_row = {g["id"]: i for i, g in enumerate(all_games)}

    _state["all_games"] = all_games
    _state["all_genre_ids"] = all_genre_ids
    _state["all_theme_names"] = all_theme_names
    _state["all_mode_names"] = all_mode_names
    _state["matrix"] = matrix
    _state["game_id_to_row"] = game_id_to_row

    return len(all_games)


# --- App lifecycle ------------------------------------------------------------

@asynccontextmanager
async def lifespan(app: FastAPI):
    count = _load_matrix()
    print(f"[recommender] matrix ready — {count} games loaded")
    yield


app = FastAPI(title="Loadout Recommender", version="1.0.0", lifespan=lifespan)


# --- Endpoints ----------------------------------------------------------------

@app.get("/health")
def health():
    enriched = sum(1 for g in _state["all_games"] if g.get("themes"))
    return {
        "status": "ok",
        "game_count": len(_state["all_games"]),
        "enriched_count": enriched,
        "theme_count": len(_state["all_theme_names"]),
        "mode_count": len(_state["all_mode_names"]),
    }


@app.post("/refresh")
def refresh():
    """Rebuild the feature matrix. Call this after new games are ingested."""
    try:
        count = _load_matrix()
    except Exception as e:
        raise HTTPException(status_code=500, detail=f"Refresh failed: {str(e)}")
    return {"status": "ok", "game_count": count}


def _load_collab_cache():
    """Fetch every user's library, group by user_id, and rebuild the item-similarity
    matrix used by item-based CF. Cached for _COLLAB_TTL seconds.
    """
    now = time.time()
    if now - _collab_cache["timestamp"] < _COLLAB_TTL:
        return

    conn = get_connection()
    try:
        cur = conn.cursor(cursor_factory=psycopg2.extras.RealDictCursor)

        cur.execute("""
            SELECT
                le.user_id,
                le.game_id,
                le.user_rating,
                le.status,
                CASE WHEN f.game_id IS NOT NULL THEN TRUE ELSE FALSE END AS is_favorite
            FROM library_entries le
            LEFT JOIN favorites f ON f.game_id = le.game_id AND f.user_id = le.user_id

            UNION ALL

            SELECT
                f.user_id,
                f.game_id,
                NULL::int AS user_rating,
                'favorited' AS status,
                TRUE AS is_favorite
            FROM favorites f
            WHERE f.game_id NOT IN (
                SELECT game_id FROM library_entries WHERE user_id = f.user_id
            )
        """)
        rows = cur.fetchall()
        cur.close()
    finally:
        conn.close()

    libraries = {}
    for row in rows:
        uid = row["user_id"]
        libraries.setdefault(uid, []).append({
            "game_id":     row["game_id"],
            "user_rating": row["user_rating"],
            "status":      row["status"],
            "is_favorite": row["is_favorite"],
        })

    all_game_ids = [g["id"] for g in _state["all_games"]]
    item_similarity = build_item_similarity(libraries, all_game_ids, top_k=50)

    _collab_cache["item_similarity"] = item_similarity
    _collab_cache["timestamp"] = now
    print(f"[recommender] item-similarity rebuilt — {len(item_similarity)} games, "
          f"{len(libraries)} users")


@app.get("/recommend")
def get_recommendations(
    uid: str = Query(..., description="Firebase UID of the authenticated user"),
    limit: int = Query(10, ge=1, le=50),
):
    # Fetch current user's library fresh — user data changes constantly
    conn = None
    try:
        conn = get_connection()
        cur = conn.cursor(cursor_factory=psycopg2.extras.RealDictCursor)

        cur.execute("""
            SELECT
                le.game_id,
                le.user_rating,
                le.status,
                CASE WHEN f.game_id IS NOT NULL THEN TRUE ELSE FALSE END AS is_favorite
            FROM library_entries le
            LEFT JOIN favorites f
                   ON f.game_id = le.game_id AND f.user_id = le.user_id
            WHERE le.user_id = %s
        """, (uid,))
        user_library = [dict(row) for row in cur.fetchall()]

        cur.execute("""
            SELECT
                f.game_id,
                NULL::int AS user_rating,
                'favorited' AS status,
                TRUE AS is_favorite
            FROM favorites f
            WHERE f.user_id = %s
              AND f.game_id NOT IN (
                  SELECT game_id FROM library_entries WHERE user_id = %s
              )
        """, (uid, uid))
        user_library.extend([dict(row) for row in cur.fetchall()])

        cur.close()
        conn.close()
        conn = None
    except Exception as e:
        if conn:
            conn.close()
        raise HTTPException(status_code=500, detail=f"Database error: {str(e)}")

    user_library_game_ids = {entry["game_id"] for entry in user_library}

    # Refresh collaborative cache if stale (rebuilds item-similarity matrix)
    try:
        _load_collab_cache()
    except Exception as e:
        print(f"[recommender] collab cache refresh failed (non-fatal): {e}")

    item_similarity = _collab_cache["item_similarity"]

    # Use cached matrix — only games with rawg_rating_count > 200 are candidates,
    # but library games stay in scope so the taste profile can be built
    eligible_games = [
        g for g in _state["all_games"]
        if (g["rawg_rating_count"] is not None and g["rawg_rating_count"] > 200)
        or g["id"] in user_library_game_ids
    ]

    results = recommend(
        all_games=eligible_games,
        all_genre_ids=_state["all_genre_ids"],
        user_library=user_library,
        user_library_game_ids=user_library_game_ids,
        top_n=limit,
        matrix=_state["matrix"],
        game_id_to_row=_state["game_id_to_row"],
        item_similarity=item_similarity,
    )

    if not results:
        return JSONResponse(content={"games": [], "cold_start": True})

    output = [
        {
            "id":                g["id"],
            "rawg_id":           g["rawg_id"],
            "name":              g["name"],
            "background_image":  g["background_image"],
            "rawg_rating":       g["rawg_rating"],
            "rawg_rating_count": g["rawg_rating_count"],
            "metacritic_score":  g["metacritic_score"],
            "genres":            g["genres"] or [],
            "platforms":         g["platforms"] or [],
        }
        for g in results
    ]

    return {"games": output, "cold_start": False}
