const { Pool } = require('pg');
require('dotenv').config();

const pool = new Pool({
  connectionString: process.env.DATABASE_URL,
  ssl: { rejectUnauthorized: false },
});

pool.connect((err) => {
  if (err) {
    console.error('PostgreSQL connection failed:', err.message);
  } else {
    console.log('PostgreSQL connected');
  }
});

module.exports = pool;