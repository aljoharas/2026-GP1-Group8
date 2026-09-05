const { Pool } = require('pg');
require('dotenv').config();

const pool = new Pool({
  connectionString: process.env.DATABASE_URL,
  ssl: { rejectUnauthorized: false },
});

pool.connect((err, client, release) => {
  if (err) {
    console.error('PostgreSQL connection failed:', err.message);
    return;
  }
  console.log('PostgreSQL connected');
  // The pool.connect(callback) form checks a client out and hands it here —
  // without releasing it, this connection sits held for the process's whole
  // lifetime instead of going back into the pool for reuse, which matters on
  // a pooler with a low total session cap (e.g. Supabase's session-mode
  // pooler defaults to 15).
  release();
});

module.exports = pool;