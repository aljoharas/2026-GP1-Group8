-- game_achievements: per-game achievement cache, one row per game.
--
-- Steam and RAWG achievement data are never merged for the same title --
-- different schemas, incompatible rarity bases (Steam = % of owners,
-- RAWG = PSN-derived). lib/achievements.js picks exactly one source per game
-- and this table caches that resolved, normalized result as jsonb.
-- Achievement lists change rarely, so this is a long-TTL cache: one fetch
-- serves every user.
--
-- This is separate from the existing `achievements` table, which stores one
-- row per achievement and backs per-user unlock tracking via
-- user_achievements -- that table is untouched by this migration.
--
-- Safe to re-run.

CREATE TABLE IF NOT EXISTS game_achievements (
  game_id      INTEGER     PRIMARY KEY REFERENCES games(id) ON DELETE CASCADE,
  source       TEXT        NOT NULL,
  payload      JSONB       NOT NULL,
  availability TEXT        NOT NULL,
  fetched_at   TIMESTAMPTZ NOT NULL DEFAULT now()
);

DO $$
BEGIN
  ALTER TABLE game_achievements
    ADD CONSTRAINT game_achievements_source_check
    CHECK (source IN ('steam', 'rawg'));
EXCEPTION
  WHEN duplicate_object THEN NULL;
END $$;

DO $$
BEGIN
  ALTER TABLE game_achievements
    ADD CONSTRAINT game_achievements_availability_check
    CHECK (availability IN ('available', 'none', 'unsupported_platform', 'no_data'));
EXCEPTION
  WHEN duplicate_object THEN NULL;
END $$;
