const express = require('express');
const router = express.Router();
const pool = require('../db/index');
const verifyToken = require('../middleware/verifyToken');
const { notify, getFriendIds } = require('../lib/activity');

// A friendship is one row, stored from the requester's side. There is no
// mirrored row, so "the other person" is always a CASE on which column holds
// the signed-in user.
const OTHER_USER = `
  CASE WHEN f.requester_id = $1 THEN f.addressee_id ELSE f.requester_id END
`;

// GET /friends — accepted friends, alphabetical
router.get('/', verifyToken, async (req, res) => {
  const { uid } = req.user;
  try {
    const result = await pool.query(
      `SELECT u.id, u.username, u.avatar_url, u.bio, f.updated_at AS friends_since
       FROM friendships f
       JOIN users u ON u.id = ${OTHER_USER}
       WHERE (f.requester_id = $1 OR f.addressee_id = $1)
         AND f.status = 'accepted'
       ORDER BY lower(u.username)`,
      [uid]
    );
    return res.status(200).json({ friends: result.rows });
  } catch (error) {
    console.error('Get friends error:', error.message);
    return res.status(500).json({ message: 'Server error' });
  }
});

// GET /friends/requests — requests waiting on the signed-in user, plus the
// ones they sent. The Requests tab shows both, so one round trip covers it.
router.get('/requests', verifyToken, async (req, res) => {
  const { uid } = req.user;
  try {
    const incoming = await pool.query(
      `SELECT f.id, u.id AS user_id, u.username, u.avatar_url, u.bio, f.created_at
       FROM friendships f
       JOIN users u ON u.id = f.requester_id
       WHERE f.addressee_id = $1 AND f.status = 'pending'
       ORDER BY f.created_at DESC`,
      [uid]
    );
    const outgoing = await pool.query(
      `SELECT f.id, u.id AS user_id, u.username, u.avatar_url, u.bio, f.created_at
       FROM friendships f
       JOIN users u ON u.id = f.addressee_id
       WHERE f.requester_id = $1 AND f.status = 'pending'
       ORDER BY f.created_at DESC`,
      [uid]
    );
    return res.status(200).json({
      incoming: incoming.rows,
      outgoing: outgoing.rows,
    });
  } catch (error) {
    console.error('Get friend requests error:', error.message);
    return res.status(500).json({ message: 'Server error' });
  }
});

// GET /friends/feed — the friend activity feed, newest first.
router.get('/feed', verifyToken, async (req, res) => {
  const { uid } = req.user;
  const limit = Math.min(parseInt(req.query.limit, 10) || 30, 100);
  const offset = Math.max(parseInt(req.query.offset, 10) || 0, 0);

  try {
    const friendIds = await getFriendIds(uid);
    if (friendIds.length === 0) {
      return res.status(200).json({ activities: [], hasMore: false });
    }

    const result = await pool.query(
      `SELECT af.id, af.type, af.payload, af.created_at,
              u.id AS user_id, u.username, u.avatar_url,
              g.rawg_id, g.name AS game_name,
              COALESCE(g.cover_image, g.background_image) AS cover_image
       FROM activity_feed af
       JOIN users u ON u.id = af.user_id
       LEFT JOIN games g ON g.id = af.game_id
       WHERE af.user_id = ANY($1::text[])
       ORDER BY af.created_at DESC
       LIMIT $2 OFFSET $3`,
      [friendIds, limit + 1, offset]
    );

    // Asking for one extra row is how we know whether another page exists
    // without a second COUNT query over the whole feed.
    const hasMore = result.rows.length > limit;
    return res.status(200).json({
      activities: hasMore ? result.rows.slice(0, limit) : result.rows,
      hasMore,
    });
  } catch (error) {
    console.error('Get friend feed error:', error.message);
    return res.status(500).json({ message: 'Server error' });
  }
});

// GET /friends/status/:userId — what the "Add friend" button should say.
router.get('/status/:userId', verifyToken, async (req, res) => {
  const { uid } = req.user;
  const { userId } = req.params;

  if (userId === uid) return res.status(200).json({ status: 'self' });

  try {
    const result = await pool.query(
      `SELECT id, requester_id, status FROM friendships
       WHERE (requester_id = $1 AND addressee_id = $2)
          OR (requester_id = $2 AND addressee_id = $1)`,
      [uid, userId]
    );

    const row = result.rows[0];
    // A declined request is kept as a row so the decline sticks, but to both
    // users it should look like no relationship — either side can ask again.
    if (!row || row.status === 'declined') {
      return res.status(200).json({ status: 'none' });
    }
    if (row.status === 'accepted') {
      return res.status(200).json({ status: 'friends', requestId: row.id });
    }
    return res.status(200).json({
      status: row.requester_id === uid ? 'pending_outgoing' : 'pending_incoming',
      requestId: row.id,
    });
  } catch (error) {
    console.error('Friend status error:', error.message);
    return res.status(500).json({ message: 'Server error' });
  }
});

// POST /friends/requests — send a friend request. Body: { userId }
router.post('/requests', verifyToken, async (req, res) => {
  const { uid } = req.user;
  const targetId = req.body.userId;

  if (!targetId) return res.status(400).json({ message: 'userId is required' });
  if (targetId === uid) {
    return res.status(400).json({ message: "You can't add yourself" });
  }

  const client = await pool.connect();
  try {
    await client.query('BEGIN');

    const target = await client.query(
      'SELECT id, username FROM users WHERE id = $1',
      [targetId]
    );
    if (target.rows.length === 0) {
      await client.query('ROLLBACK');
      return res.status(404).json({ message: 'User not found' });
    }

    // Lock the pair so two simultaneous taps can't both insert.
    const existing = await client.query(
      `SELECT id, status, requester_id FROM friendships
       WHERE (requester_id = $1 AND addressee_id = $2)
          OR (requester_id = $2 AND addressee_id = $1)
       FOR UPDATE`,
      [uid, targetId]
    );

    const row = existing.rows[0];
    if (row && row.status === 'accepted') {
      await client.query('ROLLBACK');
      return res.status(409).json({ message: 'You are already friends' });
    }
    if (row && row.status === 'pending') {
      await client.query('ROLLBACK');
      return res.status(409).json({
        message: row.requester_id === uid
          ? 'Request already sent'
          : 'This user already sent you a request',
      });
    }

    // A previously declined row is dropped rather than flipped, because the
    // new request may run the opposite direction and requester_id has to match
    // whoever is asking this time.
    if (row) {
      await client.query('DELETE FROM friendships WHERE id = $1', [row.id]);
    }

    const inserted = await client.query(
      `INSERT INTO friendships (requester_id, addressee_id, status)
       VALUES ($1, $2, 'pending')
       RETURNING id, created_at`,
      [uid, targetId]
    );

    const me = await client.query(
      'SELECT username FROM users WHERE id = $1',
      [uid]
    );

    await client.query('COMMIT');

    await notify({
      userId: targetId,
      actorId: uid,
      type: 'friend_request',
      message: `@${me.rows[0]?.username ?? 'Someone'} wants to be your friend`,
    });

    return res.status(201).json({
      request: { id: inserted.rows[0].id, status: 'pending_outgoing' },
    });
  } catch (error) {
    await client.query('ROLLBACK');
    console.error('Send friend request error:', error.message);
    return res.status(500).json({ message: 'Server error' });
  } finally {
    client.release();
  }
});

// POST /friends/requests/:id/accept — only the addressee may accept.
router.post('/requests/:id/accept', verifyToken, async (req, res) => {
  const { uid } = req.user;
  const { id } = req.params;

  try {
    const result = await pool.query(
      `UPDATE friendships SET status = 'accepted', updated_at = now()
       WHERE id = $1 AND addressee_id = $2 AND status = 'pending'
       RETURNING requester_id`,
      [id, uid]
    );

    if (result.rows.length === 0) {
      return res.status(404).json({ message: 'Request not found' });
    }

    const requesterId = result.rows[0].requester_id;

    // The request itself is no longer actionable, so it stops being a
    // notification. The requester gets a new one telling them it was accepted.
    await pool.query(
      `DELETE FROM notifications
       WHERE user_id = $1 AND related_user_id = $2 AND type = 'friend_request'`,
      [uid, requesterId]
    );

    const me = await pool.query(
      'SELECT username FROM users WHERE id = $1',
      [uid]
    );
    await notify({
      userId: requesterId,
      actorId: uid,
      type: 'friend_accepted',
      message: `@${me.rows[0]?.username ?? 'Someone'} accepted your friend request`,
    });

    return res.status(200).json({ status: 'friends' });
  } catch (error) {
    console.error('Accept friend request error:', error.message);
    return res.status(500).json({ message: 'Server error' });
  }
});

// POST /friends/requests/:id/decline
router.post('/requests/:id/decline', verifyToken, async (req, res) => {
  const { uid } = req.user;
  const { id } = req.params;

  try {
    const result = await pool.query(
      `UPDATE friendships SET status = 'declined', updated_at = now()
       WHERE id = $1 AND addressee_id = $2 AND status = 'pending'
       RETURNING requester_id`,
      [id, uid]
    );

    if (result.rows.length === 0) {
      return res.status(404).json({ message: 'Request not found' });
    }

    // Silently — the requester is not told they were declined.
    await pool.query(
      `DELETE FROM notifications
       WHERE user_id = $1 AND related_user_id = $2 AND type = 'friend_request'`,
      [uid, result.rows[0].requester_id]
    );

    return res.status(200).json({ status: 'none' });
  } catch (error) {
    console.error('Decline friend request error:', error.message);
    return res.status(500).json({ message: 'Server error' });
  }
});

// DELETE /friends/:userId — unfriend, or cancel a request you sent.
// Both collapse to "remove the row between us", so one endpoint covers them.
router.delete('/:userId', verifyToken, async (req, res) => {
  const { uid } = req.user;
  const { userId } = req.params;

  try {
    const result = await pool.query(
      `DELETE FROM friendships
       WHERE (requester_id = $1 AND addressee_id = $2)
          OR (requester_id = $2 AND addressee_id = $1)
       RETURNING id`,
      [uid, userId]
    );

    if (result.rowCount === 0) {
      return res.status(404).json({ message: 'Not friends with this user' });
    }

    // Drop any dangling request notification in either direction.
    await pool.query(
      `DELETE FROM notifications
       WHERE type = 'friend_request'
         AND ((user_id = $1 AND related_user_id = $2)
           OR (user_id = $2 AND related_user_id = $1))`,
      [uid, userId]
    );

    return res.status(200).json({ status: 'none' });
  } catch (error) {
    console.error('Remove friend error:', error.message);
    return res.status(500).json({ message: 'Server error' });
  }
});

module.exports = router;
