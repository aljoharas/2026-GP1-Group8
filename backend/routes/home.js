const express = require('express');
const router = express.Router();
const pool = require('../db');
const verifyToken = require('../middleware/verifyToken');
const { getFriendIds } = require('../lib/activity');

const RECOMMENDER_URL = process.env.RECOMMENDER_URL || 'http://localhost:8000';

router.get('/recommended', verifyToken, async (req, res) => {
  const { uid } = req.user;

  // Try the Python recommender service first
  try {
    const controller = new AbortController();
    const timeoutId = setTimeout(() => controller.abort(), 10000);
    const pyRes = await fetch(
      `${RECOMMENDER_URL}/recommend?uid=${encodeURIComponent(uid)}&limit=10`,
      { signal: controller.signal }
    );
    clearTimeout(timeoutId);

    if (pyRes.ok) {
      const data = await pyRes.json();
      if (!data.cold_start && data.games.length > 0) {
        return res.json({ games: data.games });
      }
    }
  } catch (err) {
    console.warn('[recommender] service unreachable, using random fallback:', err.message);
  }

  // Fallback: original random query (used on cold start or if Python service is down)
  try {
    const result = await pool.query(`
      SELECT
        g.id, g.rawg_id, g.name, g.background_image, g.cover_image,
        g.rawg_rating, g.rawg_rating_count, g.metacritic_score,
        array_agg(DISTINCT ge.name) FILTER (WHERE ge.name IS NOT NULL) as genres,
        array_agg(DISTINCT p.name)  FILTER (WHERE p.name IS NOT NULL)  as platforms
      FROM games g
      LEFT JOIN game_genres gg    ON g.id = gg.game_id
      LEFT JOIN genres ge         ON gg.genre_id = ge.id
      LEFT JOIN game_platforms gp ON g.id = gp.game_id
      LEFT JOIN platforms p       ON gp.platform_id = p.id
      WHERE g.rawg_rating_count > 500
        AND g.id NOT IN (
          SELECT game_id FROM library_entries WHERE user_id = $1
        )
      GROUP BY g.id
      ORDER BY RANDOM()
      LIMIT 10
    `, [uid]);

    res.json({ games: result.rows });
  } catch (err) {
    console.error(err);
    res.status(500).json({ message: 'Server error' });
  }
});

//  Popular
router.get('/popular', verifyToken, async (req, res) => {
  try {
    const result = await pool.query(`
      SELECT
        g.id, g.rawg_id, g.name, g.background_image, g.cover_image,
        g.rawg_rating, g.rawg_rating_count, g.metacritic_score,
        array_agg(DISTINCT ge.name) FILTER (WHERE ge.name IS NOT NULL) as genres,
        array_agg(DISTINCT p.name)  FILTER (WHERE p.name IS NOT NULL)  as platforms
      FROM games g
      LEFT JOIN game_genres gg    ON g.id = gg.game_id
      LEFT JOIN genres ge         ON gg.genre_id = ge.id
      LEFT JOIN game_platforms gp ON g.id = gp.game_id
      LEFT JOIN platforms p       ON gp.platform_id = p.id
      WHERE g.rawg_rating_count > 1000
      GROUP BY g.id
      ORDER BY g.rawg_rating_count DESC
      LIMIT 10
    `);

    res.json({ games: result.rows });
  } catch (err) {
    console.error(err);
    res.status(500).json({ message: 'Server error' });
  }
});

// NEW FROM FRIENDS — the games friends are currently playing.
//
// Returns the same row shape as /popular and /recommended so the home screen
// renders it with the identical cover-art card, plus who is playing it. The
// friend feed itself (the chronological cards) lives at /friends/feed.
router.get('/friends-activity', verifyToken, async (req, res) => {
  const { uid } = req.user;

  try {
    const friendIds = await getFriendIds(uid);

    if (friendIds.length === 0) {
      return res.json({ games: [] });
    }

    // DISTINCT ON collapses the row to one per game, so two friends playing
    // the same thing produce one card rather than a duplicate. The ORDER BY
    // inside picks which friend gets the credit — the most recent one.
    const result = await pool.query(`
      SELECT DISTINCT ON (g.id)
        g.id, g.rawg_id, g.name, g.background_image, g.cover_image,
        g.rawg_rating, g.rawg_rating_count, g.metacritic_score,
        u.id AS friend_id, u.username AS friend_username,
        u.avatar_url AS friend_avatar_url,
        le.status AS friend_status, le.logged_at
      FROM library_entries le
      JOIN games g ON g.id = le.game_id
      JOIN users u ON u.id = le.user_id
      WHERE le.user_id = ANY($1::text[])
        AND le.status = 'playing'
        AND le.logged_at IS NOT NULL
      ORDER BY g.id, le.logged_at DESC
      LIMIT 20
    `, [friendIds]);

    // DISTINCT ON forces an ORDER BY on the distinct column, so the newest-first
    // ordering the row is meant to have has to be applied after the fact.
    const games = result.rows
      .sort((a, b) => new Date(b.logged_at) - new Date(a.logged_at))
      .slice(0, 10);

    res.json({ games });
  } catch (err) {
    console.error(err);
    res.status(500).json({ message: 'Server error' });
  }
});

module.exports = router;