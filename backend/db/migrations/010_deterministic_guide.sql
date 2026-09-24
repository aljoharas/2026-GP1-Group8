-- Deterministic trophy guide (v2): ordering is computed by code, the LLM only
-- enriches individual trophies. Guides now record which prompt/algorithm
-- version produced them so stale cache rows can be regenerated, and keep the
-- audit logs (ladders, classification, contradictions) alongside the nodes.
--
-- achievement_category_overrides is the manual "fix it once, permanently"
-- table: a row keyed on (Steam appid, internal achievement key) forces a
-- category and is checked before every heuristic.
--
-- Safe to re-run.

ALTER TABLE achievement_guides ADD COLUMN IF NOT EXISTS prompt_version TEXT;
ALTER TABLE achievement_guides ADD COLUMN IF NOT EXISTS meta JSONB;

CREATE TABLE IF NOT EXISTS achievement_category_overrides (
  appid           TEXT        NOT NULL,
  achievement_key TEXT        NOT NULL,
  category        TEXT        NOT NULL,
  note            TEXT,
  created_at      TIMESTAMPTZ NOT NULL DEFAULT now(),
  PRIMARY KEY (appid, achievement_key)
);

DO $$
BEGIN
  ALTER TABLE achievement_category_overrides
    ADD CONSTRAINT achievement_category_overrides_category_check
    CHECK (category IN ('base', 'dlc', 'online'));
EXCEPTION
  WHEN duplicate_object THEN NULL;
END $$;
