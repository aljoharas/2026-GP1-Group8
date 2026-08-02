// Applies every .sql file in db/migrations in filename order.
//
// Usage:  node scripts/run_migrations.js
//
// Each file runs inside a transaction, so a failure halfway through leaves the
// database untouched rather than half-migrated. The migration SQL is written to
// be idempotent, so re-running this is safe.

const fs = require('fs');
const path = require('path');
const pool = require('../db/index');

const MIGRATIONS_DIR = path.join(__dirname, '..', 'db', 'migrations');

async function main() {
  const files = fs
    .readdirSync(MIGRATIONS_DIR)
    .filter((f) => f.endsWith('.sql'))
    .sort();

  if (files.length === 0) {
    console.log('No migrations found.');
    return;
  }

  for (const file of files) {
    const sql = fs.readFileSync(path.join(MIGRATIONS_DIR, file), 'utf8');
    const client = await pool.connect();
    try {
      await client.query('BEGIN');
      await client.query(sql);
      await client.query('COMMIT');
      console.log(`✓ ${file}`);
    } catch (error) {
      await client.query('ROLLBACK');
      console.error(`✗ ${file}: ${error.message}`);
      throw error;
    } finally {
      client.release();
    }
  }

  console.log(`\nApplied ${files.length} migration(s).`);
}

main()
  .then(() => pool.end())
  .catch((error) => {
    console.error('\nMigration failed:', error.message);
    pool.end();
    process.exit(1);
  });
