const express = require('express');
const router = express.Router();
const pool = require('../db/index');
const verifyToken = require('../middleware/verifyToken');
const { checkReminders } = require('../lib/reminders');

// GET /notifications — newest first.
//
// The table stores the other party as related_user_id; it's aliased to actor_id
// here so the app has one consistent name for "who did this".
//
// The friendships join is what makes an Accept/Decline row trustworthy: a
// request accepted on another device leaves the notification behind, and
// rendering buttons off the stored row alone would offer actions that no longer
// work. friendship_status comes from the live friendship instead.
router.get('/', verifyToken, async (req, res) => {
  const { uid } = req.user;
  const limit = Math.min(parseInt(req.query.limit, 10) || 50, 100);

  try {
    // Also self-heals here, not just on unread-count — opening the list
    // straight from a cold app launch shouldn't depend on the home screen
    // having loaded first.
    await checkReminders(uid);

    const result = await pool.query(
      `SELECT n.id, n.type, n.message, n.is_read, n.created_at,
              u.id AS actor_id, u.username AS actor_username,
              u.avatar_url AS actor_avatar_url,
              f.id     AS friendship_id,
              f.status AS friendship_status
       FROM notifications n
       LEFT JOIN users u ON u.id = n.related_user_id
       LEFT JOIN friendships f
              ON f.requester_id = n.related_user_id AND f.addressee_id = n.user_id
       WHERE n.user_id = $1
       ORDER BY n.created_at DESC
       LIMIT $2`,
      [uid, limit]
    );
    return res.status(200).json({ notifications: result.rows });
  } catch (error) {
    console.error('Get notifications error:', error.message);
    return res.status(500).json({ message: 'Server error' });
  }
});

// GET /notifications/unread-count — drives the dot on the bell.
router.get('/unread-count', verifyToken, async (req, res) => {
  const { uid } = req.user;
  try {
    // Called on every home-screen load, which makes it the natural place to
    // passively surface reminders without a scheduled job.
    await checkReminders(uid);

    const result = await pool.query(
      'SELECT COUNT(*) FROM notifications WHERE user_id = $1 AND is_read = FALSE',
      [uid]
    );
    return res.status(200).json({ count: parseInt(result.rows[0].count, 10) });
  } catch (error) {
    console.error('Unread count error:', error.message);
    return res.status(500).json({ message: 'Server error' });
  }
});

// POST /notifications/read-all — declared before /:id/read so "read-all" is
// never captured as an id.
router.post('/read-all', verifyToken, async (req, res) => {
  const { uid } = req.user;
  try {
    await pool.query(
      'UPDATE notifications SET is_read = TRUE WHERE user_id = $1 AND is_read = FALSE',
      [uid]
    );
    return res.status(200).json({ success: true });
  } catch (error) {
    console.error('Mark all read error:', error.message);
    return res.status(500).json({ message: 'Server error' });
  }
});

// POST /notifications/:id/read
router.post('/:id/read', verifyToken, async (req, res) => {
  const { uid } = req.user;
  const { id } = req.params;
  try {
    const result = await pool.query(
      `UPDATE notifications SET is_read = TRUE
       WHERE id = $1 AND user_id = $2 RETURNING id`,
      [id, uid]
    );
    if (result.rows.length === 0) {
      return res.status(404).json({ message: 'Notification not found' });
    }
    return res.status(200).json({ success: true });
  } catch (error) {
    console.error('Mark read error:', error.message);
    return res.status(500).json({ message: 'Server error' });
  }
});

// DELETE /notifications/:id
router.delete('/:id', verifyToken, async (req, res) => {
  const { uid } = req.user;
  const { id } = req.params;
  try {
    const result = await pool.query(
      'DELETE FROM notifications WHERE id = $1 AND user_id = $2 RETURNING id',
      [id, uid]
    );
    if (result.rowCount === 0) {
      return res.status(404).json({ message: 'Notification not found' });
    }
    return res.status(200).json({ deleted: true });
  } catch (error) {
    console.error('Delete notification error:', error.message);
    return res.status(500).json({ message: 'Server error' });
  }
});

module.exports = router;
