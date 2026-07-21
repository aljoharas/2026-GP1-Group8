const express = require('express');
const router = express.Router();
const pool = require('../db/index');
const verifyToken = require('../middleware/verifyToken');

// Every list row we send back carries its games inline. json_agg keeps this to
// one round trip instead of a query per list.
const LIST_SELECT = `
  SELECT l.id, l.name, l.emoji, l.is_public, l.created_at,
         COALESCE(
           json_agg(
             json_build_object(
               'rawg_id',          g.rawg_id,
               'name',             g.name,
               'background_image', g.background_image,
               'cover_image',      g.cover_image
             ) ORDER BY lg.position, lg.added_at
           -- rawg_id is nullable and the app keys every game row off it, so
           -- skip any game that somehow lacks one rather than send a null.
           ) FILTER (WHERE g.rawg_id IS NOT NULL),
           '[]'
         ) AS games
  FROM lists l
  LEFT JOIN list_games lg ON lg.list_id = l.id
  LEFT JOIN games g       ON g.id = lg.game_id
`;

// Confirms the list exists and belongs to this user before any write.
// Returns the row, or null so the caller can 404.
async function findOwnedList(listId, uid) {
  const result = await pool.query(
    'SELECT id FROM lists WHERE id = $1 AND user_id = $2',
    [listId, uid]
  );
  return result.rows[0] || null;
}

// GET /lists — the signed-in user's lists
router.get('/', verifyToken, async (req, res) => {
  const { uid } = req.user;
  try {
    const result = await pool.query(
      `${LIST_SELECT} WHERE l.user_id = $1 GROUP BY l.id ORDER BY l.created_at`,
      [uid]
    );
    return res.status(200).json({ lists: result.rows });
  } catch (error) {
    console.error('Get lists error:', error.message);
    return res.status(500).json({ message: 'Server error' });
  }
});

// GET /lists/user/:userId — another user's public lists only
router.get('/user/:userId', verifyToken, async (req, res) => {
  const { userId } = req.params;
  try {
    const result = await pool.query(
      `${LIST_SELECT}
       WHERE l.user_id = $1 AND l.is_public = TRUE
       GROUP BY l.id ORDER BY l.created_at`,
      [userId]
    );
    return res.status(200).json({ lists: result.rows });
  } catch (error) {
    console.error('Get public lists error:', error.message);
    return res.status(500).json({ message: 'Server error' });
  }
});

// POST /lists — create a list
router.post('/', verifyToken, async (req, res) => {
  const { uid } = req.user;
  const name = (req.body.name || '').trim();
  const emoji = (req.body.emoji || '🎮').trim();
  const isPublic = req.body.isPublic === true;

  if (!name) return res.status(400).json({ message: 'List name is required' });
  if (name.length > 50) return res.status(400).json({ message: 'List name is too long' });

  try {
    const result = await pool.query(
      `INSERT INTO lists (user_id, name, emoji, is_public)
       VALUES ($1, $2, $3, $4)
       RETURNING id, name, emoji, is_public, created_at`,
      [uid, name, emoji, isPublic]
    );
    return res.status(201).json({ list: { ...result.rows[0], games: [] } });
  } catch (error) {
    // 23505 = unique violation on lists_user_name_key
    if (error.code === '23505') {
      return res.status(409).json({ message: 'You already have a list with that name' });
    }
    console.error('Create list error:', error.message);
    return res.status(500).json({ message: 'Server error' });
  }
});

// PATCH /lists/:id — rename, change emoji, or flip public/private
router.patch('/:id', verifyToken, async (req, res) => {
  const { uid } = req.user;
  const { id } = req.params;

  const fields = [];
  const values = [];

  if (req.body.name !== undefined) {
    const name = String(req.body.name).trim();
    if (!name) return res.status(400).json({ message: 'List name is required' });
    if (name.length > 50) return res.status(400).json({ message: 'List name is too long' });
    values.push(name);
    fields.push(`name = $${values.length}`);
  }
  if (req.body.emoji !== undefined) {
    values.push(String(req.body.emoji).trim() || '🎮');
    fields.push(`emoji = $${values.length}`);
  }
  if (req.body.isPublic !== undefined) {
    values.push(req.body.isPublic === true);
    fields.push(`is_public = $${values.length}`);
  }

  if (fields.length === 0) {
    return res.status(400).json({ message: 'Nothing to update' });
  }

  try {
    if (!(await findOwnedList(id, uid))) {
      return res.status(404).json({ message: 'List not found' });
    }

    values.push(id, uid);
    const result = await pool.query(
      `UPDATE lists SET ${fields.join(', ')}, updated_at = now()
       WHERE id = $${values.length - 1} AND user_id = $${values.length}
       RETURNING id, name, emoji, is_public, created_at`,
      values
    );
    return res.status(200).json({ list: result.rows[0] });
  } catch (error) {
    if (error.code === '23505') {
      return res.status(409).json({ message: 'You already have a list with that name' });
    }
    console.error('Update list error:', error.message);
    return res.status(500).json({ message: 'Server error' });
  }
});

// DELETE /lists/:id
// list_games.list_id has a plain foreign key with no ON DELETE CASCADE, so the
// child rows have to go first or Postgres rejects the delete. Both statements
// run in one transaction so a failure can't leave orphaned rows behind.
router.delete('/:id', verifyToken, async (req, res) => {
  const { uid } = req.user;
  const { id } = req.params;

  const client = await pool.connect();
  try {
    await client.query('BEGIN');

    const owned = await client.query(
      'SELECT id FROM lists WHERE id = $1 AND user_id = $2',
      [id, uid]
    );
    if (owned.rows.length === 0) {
      await client.query('ROLLBACK');
      return res.status(404).json({ message: 'List not found' });
    }

    await client.query('DELETE FROM list_games WHERE list_id = $1', [id]);
    await client.query('DELETE FROM lists WHERE id = $1 AND user_id = $2', [id, uid]);

    await client.query('COMMIT');
    return res.status(200).json({ deleted: true });
  } catch (error) {
    await client.query('ROLLBACK');
    console.error('Delete list error:', error.message);
    return res.status(500).json({ message: 'Server error' });
  } finally {
    client.release();
  }
});

// POST /lists/:id/games — add a game by its RAWG id
router.post('/:id/games', verifyToken, async (req, res) => {
  const { uid } = req.user;
  const { id } = req.params;
  const { rawgId } = req.body;

  if (!rawgId) return res.status(400).json({ message: 'rawgId is required' });

  try {
    if (!(await findOwnedList(id, uid))) {
      return res.status(404).json({ message: 'List not found' });
    }

    const game = await pool.query('SELECT id FROM games WHERE rawg_id = $1', [rawgId]);
    if (game.rows.length === 0) {
      return res.status(404).json({ message: 'Game not found' });
    }

    // New games land at the end. Re-adding an existing game is a no-op rather
    // than an error, so the toggle in the app stays idempotent.
    await pool.query(
      `INSERT INTO list_games (list_id, game_id, position)
       VALUES ($1, $2, COALESCE((SELECT MAX(position) + 1 FROM list_games WHERE list_id = $1), 0))
       ON CONFLICT (list_id, game_id) DO NOTHING`,
      [id, game.rows[0].id]
    );
    return res.status(200).json({ added: true });
  } catch (error) {
    console.error('Add game to list error:', error.message);
    return res.status(500).json({ message: 'Server error' });
  }
});

// DELETE /lists/:id/games/:rawgId — remove a game from a list
router.delete('/:id/games/:rawgId', verifyToken, async (req, res) => {
  const { uid } = req.user;
  const { id, rawgId } = req.params;
  try {
    if (!(await findOwnedList(id, uid))) {
      return res.status(404).json({ message: 'List not found' });
    }

    await pool.query(
      `DELETE FROM list_games
       WHERE list_id = $1
         AND game_id = (SELECT id FROM games WHERE rawg_id = $2)`,
      [id, rawgId]
    );
    return res.status(200).json({ removed: true });
  } catch (error) {
    console.error('Remove game from list error:', error.message);
    return res.status(500).json({ message: 'Server error' });
  }
});

module.exports = router;
