const express = require('express');
const router = express.Router();
const pool = require('../db/index');
const verifyToken = require('../middleware/verifyToken');
// middleware/verifyToken.js already runs the admin.initializeApp guard (it's
// required above), so requiring firebase-admin here just reuses that app.
const admin = require('firebase-admin');

// CHECK EMAIL — POST-FREE, email-first sign-in flow.
// Public — called before the user picks Login vs. Sign Up, so the app can
// send them straight to the right form. Checked against Firebase Auth
// directly (getUserByEmail) rather than the Postgres users table, since
// Firebase is the authoritative source for "does this email have an account".
router.get('/check-email/:email', async (req, res) => {
  const email = (req.params.email || '').trim().toLowerCase();

  if (!email || !email.includes('@')) {
    return res.status(200).json({ exists: false });
  }

  try {
    await admin.auth().getUserByEmail(email);
    return res.status(200).json({ exists: true });
  } catch (error) {
    if (error.code === 'auth/user-not-found') {
      return res.status(200).json({ exists: false });
    }
    console.error('Check email error:', error.message);
    return res.status(500).json({ message: 'Server error' });
  }
});

// RESOLVE LOGIN IDENTIFIER — lets sign-in accept a username as well as an
// email. Firebase Auth only ever signs in with an email, so this maps
// whatever the user typed to the account's real email; the client still
// calls signInWithEmailAndPassword with that. Public — needed before the user
// has a session, same as the other checks in this file.
router.get('/resolve-login/:identifier', async (req, res) => {
  const identifier = (req.params.identifier || '').trim();

  if (!identifier) {
    return res.status(200).json({ email: null });
  }

  try {
    const result = await pool.query(
      'SELECT email FROM users WHERE lower(email) = lower($1) OR lower(username) = lower($1)',
      [identifier]
    );
    return res.status(200).json({ email: result.rows[0]?.email ?? null });
  } catch (error) {
    console.error('Resolve login error:', error.message);
    return res.status(500).json({ message: 'Server error' });
  }
});

// CHECK USERNAME AVAILABILITY
// Public — called by Flutter before creating the Firebase user, so a taken
// username doesn't leave a half-registered email behind in Firebase.
router.get('/check-username/:username', async (req, res) => {
  const username = (req.params.username || '').trim();

  if (username.length < 3) {
    return res.status(200).json({
      available: false,
      message: 'Username must be at least 3 characters',
    });
  }

  try {
    const result = await pool.query(
      'SELECT 1 FROM users WHERE username = $1',
      [username]
    );
    return res.status(200).json({ available: result.rows.length === 0 });
  } catch (error) {
    console.error('Check username error:', error.message);
    return res.status(500).json({ message: 'Server error' });
  }
});

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
       RETURNING id, email, username, bio, avatar_url, notifications_enabled, created_at`,
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
      `SELECT id, email, username, bio, avatar_url, notifications_enabled, created_at
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