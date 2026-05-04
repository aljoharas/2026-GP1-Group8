const express = require('express');
const router = express.Router();
const pool = require('../db/index');
const verifyToken = require('../middleware/verifyToken');

// REGISTER
// Called after Firebase creates the user in Flutter
router.post('/register', verifyToken, async (req, res) => {
  const { username, bio, avatar_url } = req.body;
  const { uid, email } = req.user;

  if (!username || username.trim().length < 3) {
    return res.status(400).json({
      message: 'Username must be at least 3 characters'
    });
  }

  try {
    // Check username not taken
    const taken = await pool.query(
      'SELECT id FROM users WHERE username = $1',
      [username.trim()]
    );
    if (taken.rows.length > 0) {
      return res.status(409).json({ message: 'Username already taken' });
    }

    // Check user doesn't already exist
    const exists = await pool.query(
      'SELECT id FROM users WHERE id = $1',
      [uid]
    );
    if (exists.rows.length > 0) {
      return res.status(409).json({ message: 'Account already exists' });
    }

    // Insert user — Firebase UID is the primary key
    const result = await pool.query(
      `INSERT INTO users (id, email, username, bio, avatar_url)
       VALUES ($1, $2, $3, $4, $5)
       RETURNING id, email, username, bio, avatar_url, created_at`,
      [uid, email, username.trim(), bio ? bio.trim() : null, avatar_url || null]
    );

    return res.status(201).json({
      message: 'Account created',
      user: result.rows[0],
    });

  } catch (error) {
    console.error('Register error:', error.message);
    return res.status(500).json({ message: 'Server error' });
  }
});

// LOGIN
// Called after Firebase signs the user in Flutter
router.post('/login', verifyToken, async (req, res) => {
  const { uid } = req.user;

  try {
    const result = await pool.query(
      `SELECT id, email, username, bio, avatar_url, created_at
       FROM users WHERE id = $1`,
      [uid]
    );

    if (result.rows.length === 0) {
      return res.status(404).json({ message: 'User not found' });
    }

    return res.status(200).json({
      message: 'Login successful',
      user: result.rows[0],
    });

  } catch (error) {
    console.error('Login error:', error.message);
    return res.status(500).json({ message: 'Server error' });
  }
});

module.exports = router;