const express = require('express');
const router = express.Router();
const pool = require('../db/index');
const verifyToken = require('../middleware/verifyToken');
const multer = require('multer');
const cloudinary = require('cloudinary').v2;

// ── Cloudinary config from .env ───────────────────────────────────────────
cloudinary.config({
  cloud_name: process.env.CLOUDINARY_CLOUD_NAME,
  api_key: process.env.CLOUDINARY_API_KEY,
  api_secret: process.env.CLOUDINARY_API_SECRET,
});

// ── Multer (store in memory, not disk) ────────────────────────────────────
const upload = multer({ storage: multer.memoryStorage() });

// UPLOAD AVATAR — POST /users/upload-avatar
router.post('/upload-avatar', verifyToken, upload.single('avatar'), async (req, res) => {
  if (!req.file) {
    return res.status(400).json({ message: 'No file provided' });
  }

  try {
    // Upload buffer directly to Cloudinary
    const result = await new Promise((resolve, reject) => {
      const stream = cloudinary.uploader.upload_stream(
        {
          folder: 'profile_pictures',
          transformation: [{ width: 512, height: 512, crop: 'fill' }],
        },
        (error, result) => {
          if (error) reject(error);
          else resolve(result);
        }
      );
      stream.end(req.file.buffer);
    });

    return res.status(200).json({ avatar_url: result.secure_url });
  } catch (error) {
    console.error('Cloudinary upload error:', error.message);
    return res.status(500).json({ message: 'Image upload failed' });
  }
});

// GET my profile
router.get('/me', verifyToken, async (req, res) => {
  const { uid } = req.user;

  try {
    const result = await pool.query(
      `SELECT id, email, username, bio, avatar_url,
              notifications_enabled, created_at
       FROM users WHERE id = $1`,
      [uid]
    );

    if (result.rows.length === 0) {
      return res.status(404).json({ message: 'User not found' });
    }

    return res.status(200).json({ user: result.rows[0] });

  } catch (error) {
    console.error('Get profile error:', error.message);
    return res.status(500).json({ message: 'Server error' });
  }
});

// GET friends count — GET /users/me/friends-count
router.get('/me/friends-count', verifyToken, async (req, res) => {
  const { uid } = req.user;
  try {
    const result = await pool.query(
      `SELECT COUNT(*) FROM friendships
       WHERE (requester_id = $1 OR addressee_id = $1) AND status = 'accepted'`,
      [uid]
    );
    return res.status(200).json({ count: parseInt(result.rows[0].count, 10) });
  } catch (error) {
    console.error('Friends count error:', error.message);
    return res.status(500).json({ message: 'Server error' });
  }
});

// UPDATE my profile
router.patch('/me', verifyToken, async (req, res) => {
  const { uid } = req.user;
  const { username, bio, avatar_url } = req.body;

  const fields = [];
  const values = [];
  let i = 1;

  // If the client explicitly sent a username, it must be valid. Treating an
  // empty string as "no change" would silently drop the field and return 200,
  // which makes the UI claim the save succeeded.
  if (username !== undefined) {
    const trimmed = typeof username === 'string' ? username.trim() : '';
    if (trimmed.length < 3) {
      return res.status(400).json({
        message: 'Username must be at least 3 characters',
      });
    }
    fields.push(`username = $${i++}`);
    values.push(trimmed);
  }
  if (bio !== undefined) { fields.push(`bio = $${i++}`); values.push(bio); }
  if (avatar_url) { fields.push(`avatar_url = $${i++}`); values.push(avatar_url); }

  if (fields.length === 0) {
    return res.status(400).json({ message: 'Nothing to update' });
  }

  fields.push(`updated_at = now()`);
  values.push(uid);

  try {
    const result = await pool.query(
      `UPDATE users SET ${fields.join(', ')}
       WHERE id = $${i}
       RETURNING id, email, username, bio, avatar_url, updated_at`,
      values
    );

    return res.status(200).json({ user: result.rows[0] });

  } catch (error) {
    if (error.code === '23505') {
      return res.status(409).json({ message: 'Username already taken' });
    }
    console.error('Update profile error:', error.message);
    return res.status(500).json({ message: 'Server error' });
  }
});

// LOG A GAME — POST /users/me/games
router.post('/me/games', verifyToken, async (req, res) => {
  const { uid } = req.user;
  const { rawg_id, hours_played, comment, achievements, is_finished, is_paused, logged_at, platform_name } = req.body;

  if (!rawg_id) {
    return res.status(400).json({ message: 'rawg_id is required' });
  }

  try {
    const game = await pool.query(
      'SELECT id FROM games WHERE rawg_id = $1',
      [rawg_id]
    );

    if (game.rows.length === 0) {
      return res.status(404).json({
        message: 'Game not found. Open the game profile first so it gets saved to the DB.',
      });
    }

    const game_id = game.rows[0].id;
    const status = is_finished ? 'completed' : (is_paused ? 'paused' : 'playing');

    let platform_id = null;
    if (platform_name) {
      const platformResult = await pool.query(
        `INSERT INTO platforms (name) VALUES ($1)
         ON CONFLICT (name) DO UPDATE SET name = EXCLUDED.name
         RETURNING id`,
        [platform_name]
      );
      platform_id = platformResult.rows[0].id;
    }

    const result = await pool.query(
      `INSERT INTO library_entries
         (user_id, game_id, platform_id, hours_played, comment, achievements, logged_at, status)
       VALUES ($1, $2, $3, $4, $5, $6, $7, $8)
       RETURNING *`,
      [uid, game_id, platform_id, hours_played || null, comment || null, achievements || [], logged_at || new Date(), status]
    );

    return res.status(201).json({ entry: result.rows[0] });
  } catch (error) {
    console.error('Log game error:', error.message);
    return res.status(500).json({ message: 'Server error' });
  }
});

// GET MY LOGGED GAMES — GET /users/me/games
router.get('/me/games', verifyToken, async (req, res) => {
  const { uid } = req.user;

  try {
    const result = await pool.query(
      `SELECT le.id, le.hours_played, le.comment, le.achievements,
              (le.status = 'completed') AS is_finished,
              (le.status = 'paused') AS is_paused, le.logged_at,
              g.rawg_id, g.name, g.background_image, g.cover_image,
              p.name AS platform_name
       FROM library_entries le
       JOIN games g ON le.game_id = g.id
       LEFT JOIN platforms p ON le.platform_id = p.id
       WHERE le.user_id = $1
       ORDER BY le.logged_at DESC`,
      [uid]
    );

    return res.status(200).json({ games: result.rows });
  } catch (error) {
    console.error('Get logged games error:', error.message);
    return res.status(500).json({ message: 'Server error' });
  }
});

// PATCH /users/me/games/entries/:entryId — update achievements for a single log entry
router.patch('/me/games/entries/:entryId', verifyToken, async (req, res) => {
  const { uid } = req.user;
  const { entryId } = req.params;
  const { achievements } = req.body;

  try {
    const result = await pool.query(
      `UPDATE library_entries SET achievements = $1
       WHERE id = $2 AND user_id = $3 RETURNING id`,
      [achievements ?? [], entryId, uid]
    );
    if (result.rows.length === 0) {
      return res.status(404).json({ message: 'Entry not found' });
    }
    return res.status(200).json({ success: true });
  } catch (error) {
    console.error('Update entry achievements error:', error.message);
    return res.status(500).json({ message: 'Server error' });
  }
});

// DELETE /users/me/games/:rawgId — removes all library entries for this game
router.delete('/me/games/:rawgId', verifyToken, async (req, res) => {
  const { uid } = req.user;
  const { rawgId } = req.params;

  try {
    const game = await pool.query('SELECT id FROM games WHERE rawg_id = $1', [rawgId]);
    if (game.rows.length === 0) {
      return res.status(404).json({ message: 'Game not found' });
    }

    const result = await pool.query(
      'DELETE FROM library_entries WHERE user_id = $1 AND game_id = $2 RETURNING id',
      [uid, game.rows[0].id]
    );

    return res.status(200).json({ deleted: result.rowCount });
  } catch (error) {
    console.error('Delete game error:', error.message);
    return res.status(500).json({ message: 'Server error' });
  }
});

// GET /users/me/favorites
router.get('/me/favorites', verifyToken, async (req, res) => {
  const { uid } = req.user;
  try {
    const result = await pool.query(
      `SELECT g.rawg_id, g.name, g.background_image, g.cover_image
       FROM favorites f
       JOIN games g ON f.game_id = g.id
       WHERE f.user_id = $1
       ORDER BY f.created_at DESC`,
      [uid]
    );
    return res.status(200).json({ favorites: result.rows });
  } catch (error) {
    console.error('Get favorites error:', error.message);
    return res.status(500).json({ message: 'Server error' });
  }
});

// GET another user's public profile
router.get('/:id', verifyToken, async (req, res) => {
  const { id } = req.params;

  try {
    const result = await pool.query(
      `SELECT id, username, bio, avatar_url, created_at
       FROM users WHERE id = $1`,
      [id]
    );

    if (result.rows.length === 0) {
      return res.status(404).json({ message: 'User not found' });
    }

    return res.status(200).json({ user: result.rows[0] });

  } catch (error) {
    console.error('Get user error:', error.message);
    return res.status(500).json({ message: 'Server error' });
  }
});

module.exports = router;