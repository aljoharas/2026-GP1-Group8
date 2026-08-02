const express = require('express');
const router = express.Router();
const pool = require('../db/index');
const verifyToken = require('../middleware/verifyToken');
const { recordActivity } = require('../lib/activity');
require('dotenv').config();

const RAWG_KEY = process.env.RAWG_API_KEY;
const RAWG_BASE = 'https://api.rawg.io/api';
const IGDB_CLIENT_ID = process.env.IGDB_CLIENT_ID;
const IGDB_CLIENT_SECRET = process.env.IGDB_CLIENT_SECRET;
const RECOMMENDER_URL = process.env.RECOMMENDER_URL || 'http://localhost:8000';

function triggerRecommenderRefresh() {
  fetch(`${RECOMMENDER_URL}/refresh`, { method: 'POST' })
    .catch(err => console.warn('[recommender] refresh failed:', err.message));
}

// Helper — fetch from RAWG
async function fetchFromRawg(endpoint) {
  const url = `${RAWG_BASE}${endpoint}&key=${RAWG_KEY}`;
  const response = await fetch(url);
  if (!response.ok) throw new Error('RAWG API error');
  return response.json();
}

// IGDB token cache — Twitch tokens last ~60 days so one fetch covers a long time
let _igdbToken = null;
let _igdbTokenExpiry = 0;

async function getIGDBToken() {
  if (_igdbToken && Date.now() < _igdbTokenExpiry) return _igdbToken;
  const resp = await fetch(
    `https://id.twitch.tv/oauth2/token?client_id=${IGDB_CLIENT_ID}&client_secret=${IGDB_CLIENT_SECRET}&grant_type=client_credentials`,
    { method: 'POST' }
  );
  if (!resp.ok) throw new Error('IGDB auth failed');
  const data = await resp.json();
  _igdbToken = data.access_token;
  _igdbTokenExpiry = Date.now() + (data.expires_in - 300) * 1000; // expire 5 min early
  return _igdbToken;
}

// Helper — fetch themes, game_modes, keywords from IGDB by slug
async function fetchIGDBData(slug) {
  const token = await getIGDBToken();
  const resp = await fetch('https://api.igdb.com/v4/games', {
    method: 'POST',
    headers: {
      'Client-ID': IGDB_CLIENT_ID,
      'Authorization': `Bearer ${token}`,
    },
    body: `where slug = "${slug}"; fields themes.name,game_modes.name,keywords.name,cover.url,summary,storyline; limit 1;`,
  });
  if (!resp.ok) throw new Error(`IGDB error ${resp.status}`);
  const results = await resp.json();
  return results[0] || null;
}

// Helper — save a game from RAWG into your database
// This is called whenever we get a game from RAWG that isn't in our DB yet
async function saveGameToDB(rawgGame) {
  const {
    id: rawg_id,
    slug,
    name,
    description_raw,
    background_image,
    released,
    rating,
    ratings_count,
    playtime,
    esrb_rating,
    metacritic,
    genres,
    platforms,
    developers,
    publishers,
  } = rawgGame;

  // Insert the game — ON CONFLICT DO NOTHING means if it's already there, skip
  const gameResult = await pool.query(
    `INSERT INTO games
       (rawg_id, slug, name, description, background_image,
        released_at, rawg_rating, rawg_rating_count, playtime_hrs, esrb_rating, metacritic_score)
     VALUES ($1,$2,$3,$4,$5,$6,$7,$8,$9,$10,$11)
     ON CONFLICT (rawg_id) DO UPDATE
       SET name = EXCLUDED.name,
           description = COALESCE(EXCLUDED.description, games.description),
           rawg_rating = EXCLUDED.rawg_rating,
           metacritic_score = COALESCE(EXCLUDED.metacritic_score, games.metacritic_score),
           updated_at = now()
     RETURNING id`,
    [
      rawg_id, slug, name, description_raw, background_image,
      released, rating, ratings_count, playtime,
      esrb_rating?.slug || null, metacritic || null,
    ]
  );

  const gameId = gameResult.rows[0].id;

  // Save genres
  if (genres) {
    for (const genre of genres) {
      const g = await pool.query(
        `INSERT INTO genres (name) VALUES ($1)
         ON CONFLICT (name) DO UPDATE SET name = EXCLUDED.name
         RETURNING id`,
        [genre.name]
      );
      await pool.query(
        `INSERT INTO game_genres (game_id, genre_id) VALUES ($1, $2)
         ON CONFLICT DO NOTHING`,
        [gameId, g.rows[0].id]
      );
    }
  }

  // Save platforms
  if (platforms) {
    for (const p of platforms) {
      const pl = await pool.query(
        `INSERT INTO platforms (name) VALUES ($1)
         ON CONFLICT (name) DO UPDATE SET name = EXCLUDED.name
         RETURNING id`,
        [p.platform.name]
      );
      await pool.query(
        `INSERT INTO game_platforms (game_id, platform_id) VALUES ($1, $2)
         ON CONFLICT DO NOTHING`,
        [gameId, pl.rows[0].id]
      );
    }
  }

  // Save developers — fall back to publishers if RAWG left developers empty
  const devList = (developers && developers.length > 0) ? developers : (publishers || []);
  console.log(`[saveGameToDB] "${name}" — RAWG developers: ${JSON.stringify(developers)}, publishers: ${JSON.stringify(publishers)}, using: ${JSON.stringify(devList)}`);
  for (const dev of devList) {
    if (!dev.name) continue;
    const d = await pool.query(
      `INSERT INTO developers (name) VALUES ($1)
       ON CONFLICT (name) DO UPDATE SET name = EXCLUDED.name
       RETURNING id`,
      [dev.name]
    );
    await pool.query(
      `INSERT INTO game_developers (game_id, developer_id) VALUES ($1, $2)
       ON CONFLICT DO NOTHING`,
      [gameId, d.rows[0].id]
    );
  }

  // Enrich with IGDB data (themes, game_modes, keywords) if not already set
  try {
    const existing = await pool.query(
      'SELECT themes FROM games WHERE id = $1',
      [gameId]
    );
    const alreadyEnriched = existing.rows[0]?.themes?.length > 0;

    if (!alreadyEnriched && slug) {
      const igdb = await fetchIGDBData(slug);
      if (igdb) {
        const themes    = (igdb.themes     || []).map(t => t.name);
        const gameModes = (igdb.game_modes || []).map(m => m.name);
        const keywords  = (igdb.keywords   || []).slice(0, 50).map(k => k.name);
        const rawCoverUrl = igdb.cover?.url;
        // IGDB URLs start with // and use t_thumb; upgrade to https + t_cover_big
        const coverImage = rawCoverUrl
          ? `https:${rawCoverUrl.replace('t_thumb', 't_cover_big')}`
          : null;
        await pool.query(
          `UPDATE games SET themes = $1, game_modes = $2, keywords = $3,
                           cover_image  = COALESCE($4, cover_image),
                           summary      = COALESCE($5, summary),
                           storyline    = COALESCE($6, storyline),
                           updated_at   = now()
           WHERE id = $7`,
          [themes, gameModes, keywords, coverImage,
           igdb.summary || null, igdb.storyline || null, gameId]
        );
      }
    }
  } catch (err) {
    // IGDB enrichment is best-effort — never block game save
    console.warn(`[IGDB] enrichment skipped for "${slug}":`, err.message);
  }

  return gameId;
}

// SEARCH GAMES
// Flutter calls: GET /games/search?q=elden+ring
router.get('/search', verifyToken, async (req, res) => {
  const { q } = req.query;

  if (!q || q.trim().length < 2) {
    return res.status(400).json({ message: 'Search query too short' });
  }

  try {
    // First check our own database
    const local = await pool.query(
      `SELECT g.id, g.rawg_id, g.name, g.background_image, g.cover_image,
              g.rawg_rating, g.released_at,
              array_agg(DISTINCT ge.name) as genres
       FROM games g
       LEFT JOIN game_genres gg ON g.id = gg.game_id
       LEFT JOIN genres ge ON gg.genre_id = ge.id
       WHERE g.name ILIKE $1
       GROUP BY g.id
       LIMIT 20`,
      [`%${q.trim()}%`]
    );

    // If we have results locally, return them immediately
    if (local.rows.length > 0) {
      return res.status(200).json({ games: local.rows, source: 'cache' });
    }

    // Otherwise fetch from RAWG and return as a thin passthrough.
    // We deliberately do NOT pre-save these games here. saveGameToDB does
    // ~30+ sequential queries plus an IGDB call per game; running that in
    // the background for every search exhausts the Supabase pool (15 conn
    // limit). /games/:id saves the game lazily when the user actually opens
    // it, which is the only time we truly need it cached.
    const rawgData = await fetchFromRawg(`/games?search=${encodeURIComponent(q)}&page_size=20&`);
    return res.status(200).json({ games: rawgData.results, source: 'rawg' });

  } catch (error) {
    console.error('Search error:', error.message);
    return res.status(500).json({ message: 'Server error' });
  }
});

// GET /games/:rawgId/favorite — check if favorited
router.get('/:rawgId/favorite', verifyToken, async (req, res) => {
  const { uid } = req.user;
  const { rawgId } = req.params;
  try {
    const game = await pool.query('SELECT id FROM games WHERE rawg_id = $1', [rawgId]);
    if (game.rows.length === 0) return res.status(200).json({ isFavorite: false });
    const result = await pool.query(
      'SELECT 1 FROM favorites WHERE user_id = $1 AND game_id = $2',
      [uid, game.rows[0].id]
    );
    return res.status(200).json({ isFavorite: result.rows.length > 0 });
  } catch (error) {
    console.error('Get favorite error:', error.message);
    return res.status(500).json({ message: 'Server error' });
  }
});

// POST /games/:rawgId/favorite — toggle favorite
router.post('/:rawgId/favorite', verifyToken, async (req, res) => {
  const { uid } = req.user;
  const { rawgId } = req.params;
  try {
    const game = await pool.query('SELECT id FROM games WHERE rawg_id = $1', [rawgId]);
    if (game.rows.length === 0) return res.status(404).json({ message: 'Game not found' });
    const gameId = game.rows[0].id;

    const existing = await pool.query(
      'SELECT 1 FROM favorites WHERE user_id = $1 AND game_id = $2',
      [uid, gameId]
    );

    if (existing.rows.length > 0) {
      await pool.query('DELETE FROM favorites WHERE user_id = $1 AND game_id = $2', [uid, gameId]);
      return res.status(200).json({ isFavorite: false });
    } else {
      await pool.query('INSERT INTO favorites (user_id, game_id) VALUES ($1, $2)', [uid, gameId]);
      return res.status(200).json({ isFavorite: true });
    }
  } catch (error) {
    console.error('Toggle favorite error:', error.message);
    return res.status(500).json({ message: 'Server error' });
  }
});

// POST /games/:id/rate
// rating: 1–5 saves the rating; rating: 0 removes it (sets to NULL)
router.post('/:id/rate', verifyToken, async (req, res) => {
  const { id } = req.params;
  const userId = req.user.uid;
  const ratingNum = parseInt(req.body.rating);

  if (isNaN(ratingNum) || ratingNum < 0 || ratingNum > 5) {
    return res.status(400).json({ message: 'Rating must be between 0 and 5' });
  }

  const ratingValue = ratingNum === 0 ? null : ratingNum;

  try {
    const gameRes = await pool.query(
      'SELECT id FROM games WHERE rawg_id = $1',
      [id]
    );
    if (gameRes.rows.length === 0) {
      return res.status(404).json({ message: 'Game not found' });
    }
    const gameId = gameRes.rows[0].id;

    const updated = await pool.query(
      `UPDATE library_entries SET user_rating = $3, updated_at = now()
       WHERE id = (
         SELECT id FROM library_entries
         WHERE user_id = $1 AND game_id = $2
         ORDER BY added_at DESC LIMIT 1
       ) RETURNING id`,
      [userId, gameId, ratingValue]
    );

    if (updated.rowCount === 0 && ratingValue !== null) {
      await pool.query(
        `INSERT INTO library_entries (user_id, game_id, user_rating, status, logged_at, added_at, updated_at)
         VALUES ($1, $2, $3, 'completed', NULL, now(), now())`,
        [userId, gameId, ratingValue]
      );
    }

    // Clearing a rating shouldn't announce itself, and re-rating should move
    // the existing card rather than stack a new one — hence the dedupe key.
    if (ratingValue !== null) {
      await recordActivity({
        userId,
        type: 'game_rated',
        gameId,
        payload: { rating: ratingValue },
        dedupeKey: `rating:${userId}:${gameId}`,
      });
    } else {
      await pool.query(
        'DELETE FROM activity_feed WHERE dedupe_key = $1',
        [`rating:${userId}:${gameId}`]
      );
    }

    return res.status(200).json({ message: ratingValue === null ? 'Rating removed' : 'Rating saved' });
  } catch (error) {
    console.error('Rate error:', error.message);
    return res.status(500).json({ message: 'Server error' });
  }
});

// POST /games/:id/review
router.post('/:id/review', verifyToken, async (req, res) => {
  const { id } = req.params;
  const userId = req.user.uid;
  const { text, rating } = req.body;

  try {
    const gameRes = await pool.query(
      'SELECT id FROM games WHERE rawg_id = $1',
      [id]
    );
    if (gameRes.rows.length === 0) {
      return res.status(404).json({ message: 'Game not found' });
    }
    const gameId = gameRes.rows[0].id;

    const trimmedText = (text || '').trim();
    const reviewText = trimmedText.length > 0 ? trimmedText : null;
    const ratingNum = rating && parseInt(rating) >= 1 && parseInt(rating) <= 5
      ? parseInt(rating) : null;

    const updated = await pool.query(
      `UPDATE library_entries
       SET review_text = $3,
           user_rating = COALESCE($4, user_rating),
           updated_at = now()
       WHERE id = (
         SELECT id FROM library_entries
         WHERE user_id = $1 AND game_id = $2
         ORDER BY added_at DESC LIMIT 1
       ) RETURNING id`,
      [userId, gameId, reviewText, ratingNum]
    );

    if (updated.rowCount === 0 && reviewText !== null) {
      await pool.query(
        `INSERT INTO library_entries (user_id, game_id, review_text, user_rating, status, logged_at, added_at, updated_at)
         VALUES ($1, $2, $3, $4, 'completed', NULL, now(), now())`,
        [userId, gameId, reviewText, ratingNum]
      );
    }

    // Same edit-not-event reasoning as ratings: one card per user per game,
    // refreshed when they rewrite it, removed when they clear the text.
    if (reviewText !== null) {
      await recordActivity({
        userId,
        type: 'game_reviewed',
        gameId,
        payload: { review_text: reviewText, rating: ratingNum },
        dedupeKey: `review:${userId}:${gameId}`,
      });
    } else {
      await pool.query(
        'DELETE FROM activity_feed WHERE dedupe_key = $1',
        [`review:${userId}:${gameId}`]
      );
    }

    return res.status(200).json({ message: 'Review saved' });
  } catch (error) {
    console.error('Review error:', error.message);
    return res.status(500).json({ message: 'Server error' });
  }
});

// GET /games/:id/reviews
router.get('/:id/reviews', verifyToken, async (req, res) => {
  const { id } = req.params;
  const userId = req.user.uid;

  try {
    const gameRes = await pool.query(
      'SELECT id FROM games WHERE rawg_id = $1',
      [id]
    );
    if (gameRes.rows.length === 0) {
      return res.status(404).json({ message: 'Game not found' });
    }
    const gameId = gameRes.rows[0].id;

    const reviews = await pool.query(
      `SELECT CAST(le.user_rating AS INTEGER) as user_rating, le.review_text, le.updated_at,
              u.username, u.avatar_url,
              (le.user_id = $2) as is_own
       FROM library_entries le
       LEFT JOIN users u ON le.user_id = u.id
       WHERE le.game_id = $1
         AND le.review_text IS NOT NULL
         AND le.review_text != ''
       ORDER BY (le.user_id = $2) DESC, le.updated_at DESC
       LIMIT 20`,
      [gameId, userId]
    );

    const userRatingRes = await pool.query(
      `SELECT CAST(user_rating AS INTEGER) as user_rating FROM library_entries
       WHERE user_id = $1 AND game_id = $2 AND user_rating IS NOT NULL
       ORDER BY added_at DESC LIMIT 1`,
      [userId, gameId]
    );

    const communityRes = await pool.query(
      `SELECT ROUND(AVG(user_rating)::numeric, 1) as avg_rating,
              COUNT(*) as count
       FROM library_entries
       WHERE game_id = $1 AND user_rating IS NOT NULL`,
      [gameId]
    );

    const { avg_rating, count } = communityRes.rows[0];

    return res.status(200).json({
      reviews: reviews.rows,
      userRating: userRatingRes.rows[0]?.user_rating ?? null,
      communityRating: avg_rating ? parseFloat(avg_rating) : null,
      communityRatingCount: parseInt(count) || 0,
    });
  } catch (error) {
    console.error('Reviews error:', error.message);
    return res.status(500).json({ message: 'Server error' });
  }
});

// GET /games/:id/achievements
// Cached in the achievements table — only hits RAWG on a miss, then persists.
router.get('/:id/achievements', verifyToken, async (req, res) => {
  const { id } = req.params; // RAWG id
  try {
    const gameRow = await pool.query('SELECT id FROM games WHERE rawg_id = $1', [id]);
    const gameId = gameRow.rows[0]?.id;

    if (gameId) {
      const cached = await pool.query(
        `SELECT id, display_name AS name, description, icon_url AS image, percent
         FROM achievements WHERE game_id = $1 ORDER BY id`,
        [gameId]
      );
      if (cached.rows.length > 0) {
        return res.status(200).json({ achievements: cached.rows });
      }
    }

    let all = [];
    let url = `${RAWG_BASE}/games/${id}/achievements?page_size=40&key=${RAWG_KEY}`;
    while (url && all.length < 200) {
      const response = await fetch(url);
      if (!response.ok) break;
      const data = await response.json();
      all = all.concat(data.results || []);
      url = data.next || null;
    }

    if (gameId && all.length > 0) {
      for (const a of all) {
        const pct = a.percent != null ? parseFloat(a.percent) : null;
        await pool.query(
          `INSERT INTO achievements (game_id, api_name, display_name, description, icon_url, percent)
           VALUES ($1, $2, $3, $4, $5, $6)
           ON CONFLICT (game_id, api_name) DO UPDATE
             SET display_name = EXCLUDED.display_name,
                 description  = EXCLUDED.description,
                 icon_url     = EXCLUDED.icon_url,
                 percent      = EXCLUDED.percent`,
          [gameId, String(a.id), a.name, a.description || null, a.image || null,
           Number.isFinite(pct) ? pct : null]
        );
      }
      const saved = await pool.query(
        `SELECT id, display_name AS name, description, icon_url AS image, percent
         FROM achievements WHERE game_id = $1 ORDER BY id`,
        [gameId]
      );
      return res.status(200).json({ achievements: saved.rows });
    }

    return res.status(200).json({ achievements: all });
  } catch (error) {
    console.error('Achievements error:', error.message);
    return res.status(500).json({ message: 'Failed to fetch achievements' });
  }
});

// GET SINGLE GAME PROFILE
// Flutter calls: GET /games/:id  (id is always a RAWG id)
router.get('/:id', verifyToken, async (req, res) => {
  const { id } = req.params;

  try {
    // Check our database first — match only by rawg_id to avoid collisions
    // with internal sequential DB ids
    const local = await pool.query(
      `SELECT g.*,
              array_agg(DISTINCT ge.name) FILTER (WHERE ge.name IS NOT NULL) as genres,
              array_agg(DISTINCT p.name)  FILTER (WHERE p.name IS NOT NULL)  as platforms,
              array_agg(DISTINCT d.name)  FILTER (WHERE d.name IS NOT NULL)  as developers
       FROM games g
       LEFT JOIN game_genres gg    ON g.id = gg.game_id
       LEFT JOIN genres ge         ON gg.genre_id = ge.id
       LEFT JOIN game_platforms gp ON g.id = gp.game_id
       LEFT JOIN platforms p       ON gp.platform_id = p.id
       LEFT JOIN game_developers gd ON g.id = gd.game_id
       LEFT JOIN developers d      ON gd.developer_id = d.id
       WHERE g.rawg_id = $1
       GROUP BY g.id`,
      [id]
    );

    // If found in DB with developers saved, serve from cache
    const localGame = local.rows[0];
    const hasDevelopers = localGame?.developers && localGame.developers.length > 0;
    if (local.rows.length > 0 && hasDevelopers) {
      return res.status(200).json({ game: localGame });
    }

    // Not in DB or missing developers — fetch full details from RAWG
    const rawgId = local.rows.length > 0 ? local.rows[0].rawg_id : id;
    const rawgGame = await fetchFromRawg(`/games/${rawgId}?`);
    await saveGameToDB(rawgGame);
    triggerRecommenderRefresh();

    // Fetch again from our DB to get the joined data
    const saved = await pool.query(
      `SELECT g.*,
              array_agg(DISTINCT ge.name) FILTER (WHERE ge.name IS NOT NULL) as genres,
              array_agg(DISTINCT p.name)  FILTER (WHERE p.name IS NOT NULL)  as platforms,
              array_agg(DISTINCT d.name)  FILTER (WHERE d.name IS NOT NULL)  as developers
       FROM games g
       LEFT JOIN game_genres gg    ON g.id = gg.game_id
       LEFT JOIN genres ge         ON gg.genre_id = ge.id
       LEFT JOIN game_platforms gp ON g.id = gp.game_id
       LEFT JOIN platforms p       ON gp.platform_id = p.id
       LEFT JOIN game_developers gd ON g.id = gd.game_id
       LEFT JOIN developers d      ON gd.developer_id = d.id
       WHERE g.rawg_id = $1
       GROUP BY g.id`,
      [rawgGame.id]
    );

    return res.status(200).json({ game: saved.rows[0] });

  } catch (error) {
    console.error('Get game error:', error.message);
    return res.status(500).json({ message: 'Server error' });
  }
});

module.exports = router;