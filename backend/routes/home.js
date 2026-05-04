const express = require('express');
const router = express.Router();
const pool = require('../db');
const verifyToken = require('../middleware/verifyToken');

const RECOMMENDER_URL = process.env.RECOMMENDER_URL || 'http://localhost:8000';

router.get('/recommended', verifyToken, async (req, res) => {
  const { uid } = req.user;

  // Try the Python recommender service first
  try {
    const controller = new AbortController();
    const timeoutId = setTimeout(() => controller.abort(), 3000);
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

//  Friends Activity
router.get('/friends-activity', verifyToken, async (req, res) => {
  const { uid } = req.user;

  try {
  
    const friendsResult = await pool.query(`
      SELECT 
        CASE 
          WHEN requester_id = $1 THEN addressee_id
          ELSE requester_id
        END as friend_id
      FROM friendships
      WHERE (requester_id = $1 OR addressee_id = $1)
        AND status = 'accepted'
    `, [uid]);

    const friendIds = friendsResult.rows.map(r => r.friend_id);

    if (friendIds.length === 0) {
      return res.json({ activities: [] });
    }

    
    const result = await pool.query(`
      SELECT 
        af.id, af.type, af.payload, af.created_at,
        u.username, u.avatar_url,
        g.name as game_name, COALESCE(g.cover_image, g.background_image) as cover_image
      FROM activity_feed af
      JOIN users u ON af.user_id = u.id
      LEFT JOIN games g ON af.game_id = g.id
      WHERE af.user_id = ANY($1::text[])
      ORDER BY af.created_at DESC
      LIMIT 10
    `, [friendIds]);

    res.json({ activities: result.rows });
  } catch (err) {
    console.error(err);
    res.status(500).json({ message: 'Server error' });
  }
});

module.exports = router;