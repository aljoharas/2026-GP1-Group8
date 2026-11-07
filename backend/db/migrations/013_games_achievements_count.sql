-- games.achievements_count: RAWG's achievement count for the game, from the
-- game details endpoint (GET /games/{id} -> achievements_count).
--
-- The Python service's Player Archetypes use it as the denominator of
-- trophy_rate (recommender/archetypes.py). NULL means not fetched yet or RAWG
-- gave no count. RAWG counts mostly come from PC (Steam) achievement lists, so
-- they can differ from a PlayStation trophy list.
--
-- Filled by saveGameToDB (routes/games.js) on every RAWG details fetch;
-- existing games are backfilled by scripts/backfill_achievements_count.js.
--
-- Safe to re-run.

ALTER TABLE games ADD COLUMN IF NOT EXISTS achievements_count INTEGER;

DO $$
BEGIN
  ALTER TABLE games
    ADD CONSTRAINT games_achievements_count_check
    CHECK (achievements_count IS NULL OR achievements_count >= 0);
EXCEPTION
  WHEN duplicate_object THEN NULL;
END $$;
