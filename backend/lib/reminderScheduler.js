const cron = require('node-cron');
const pool = require('../db/index');
const { checkReminders } = require('./reminders');
const { sendPushToUser } = require('./push');

// The only path that actually sends a push. The on-demand checks in
// routes/notifications.js (GET / and GET /unread-count) still write the same
// notification rows for the in-app bell, but a user with the app open
// already sees it there — pushing on top would just double-notify them.
// This runs regardless of whether anyone has the app open, which is the
// whole point of a real push.
async function tick() {
  try {
    const users = await pool.query('SELECT id FROM users');
    for (const { id } of users.rows) {
      const created = await checkReminders(id);
      if (created.length === 0) continue;

      // One push per user per tick, however many reminder types fired —
      // several system notifications landing back-to-back reads as spam.
      // Every individual reminder still has its own row for the in-app bell;
      // only the push itself gets bundled.
      const body = created.length === 1
        ? created[0].message
        : `You have ${created.length} new reminders — tap to see what's new.`;
      await sendPushToUser(id, { title: 'Loadout', body });
    }
  } catch (error) {
    console.error('[reminderScheduler] tick failed:', error.message);
  }
}

function start() {
  cron.schedule('*/30 * * * *', tick);
  console.log('[reminderScheduler] started — checking every 30 minutes');
}

module.exports = { start, tick };
