-- achievement_guides: cached AI-generated suggested completion order for a
-- game's achievements, one row per game. Generating a guide costs an OpenAI
-- call, so this is a long-TTL cache keyed by game_id and only regenerated
-- on explicit request (?refresh=true) -- one generation serves every user.
--
-- Safe to re-run.

CREATE TABLE IF NOT EXISTS achievement_guides (
  game_id      INTEGER     PRIMARY KEY REFERENCES games(id) ON DELETE CASCADE,
  nodes        JSONB       NOT NULL,
  model        TEXT        NOT NULL,
  generated_at TIMESTAMPTZ NOT NULL DEFAULT now()
);
