const admin = require('firebase-admin');
const pool = require('../db/index');

// Same init-guard as middleware/verifyToken.js — safe regardless of which
// file happens to require firebase-admin first.
if (!admin.apps.length) {
  const serviceAccount = require('../serviceAccountKey.json');
  admin.initializeApp({
    credential: admin.credential.cert(serviceAccount),
  });
}

// Fire-and-forget, same contract as lib/activity.js and lib/reminders.js — a
// push failure must never break whatever triggered it.
async function sendPushToUser(userId, { title, body, data = {} }) {
  if (!userId) return;

  try {
    const tokens = await pool.query(
      'SELECT token FROM device_tokens WHERE user_id = $1',
      [userId]
    );
    if (tokens.rows.length === 0) return;

    const response = await admin.messaging().sendEachForMulticast({
      tokens: tokens.rows.map((r) => r.token),
      notification: { title, body },
      data,
    });

    // Drop any token Firebase reports as dead, so they don't pile up and get
    // retried forever.
    const dead = [];
    response.responses.forEach((r, i) => {
      if (!r.success && r.error?.code === 'messaging/registration-token-not-registered') {
        dead.push(tokens.rows[i].token);
      }
    });
    if (dead.length > 0) {
      await pool.query('DELETE FROM device_tokens WHERE token = ANY($1)', [dead]);
    }
  } catch (error) {
    console.error('[push] failed to send:', error.message);
  }
}

module.exports = { sendPushToUser };
