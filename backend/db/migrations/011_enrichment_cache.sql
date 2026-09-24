-- achievement_enrichment: per-trophy LLM enrichment, cached independently of
-- the guide so the two pipeline stages version separately:
--   * bumping the ORDERING version (ALGO_VERSION) recomputes ordering and
--     reuses every row here -- zero OpenAI calls;
--   * bumping the ENRICHMENT version (enrich.js PROMPT_VERSION) invalidates
--     these rows only (the PK includes enrich_version) -- ordering is untouched.
-- input_hash covers the exact text sent to the model (name + description), so a
-- trophy whose text changed is re-enriched alone.
--
-- Safe to re-run.

CREATE TABLE IF NOT EXISTS achievement_enrichment (
  game_id        INTEGER     NOT NULL REFERENCES games(id) ON DELETE CASCADE,
  trophy_id      TEXT        NOT NULL,
  enrich_version TEXT        NOT NULL,
  input_hash     TEXT        NOT NULL,
  steps          JSONB       NOT NULL,
  category_vote  TEXT        NOT NULL,
  confidence     TEXT        NOT NULL,
  model          TEXT        NOT NULL,
  created_at     TIMESTAMPTZ NOT NULL DEFAULT now(),
  PRIMARY KEY (game_id, trophy_id, enrich_version)
);
