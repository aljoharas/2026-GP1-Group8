-- Push notification device tokens, one row per device.
--
-- token is the primary key rather than a surrogate id: re-registering the
-- same token (app reinstall, token refresh) is then a plain upsert, and a
-- token that moves to a different account (new user on a shared/reinstalled
-- device) can be reassigned instead of rejected. A separate table (not a
-- column on users) lets one account get pushed on every device it's signed
-- into.
--
-- Safe to re-run.

CREATE TABLE IF NOT EXISTS device_tokens (
  token      TEXT PRIMARY KEY,
  user_id    TEXT NOT NULL REFERENCES users(id) ON DELETE CASCADE,
  created_at TIMESTAMPTZ NOT NULL DEFAULT now(),
  updated_at TIMESTAMPTZ NOT NULL DEFAULT now()
);

CREATE INDEX IF NOT EXISTS device_tokens_user_idx ON device_tokens (user_id);
