# Player Archetypes: merge plan and deployment checklist

**Status:** nothing is merged yet. One pull request is open for review: `feature/archetype-sim-v2` → `main`.

**Pre-merge cleanup (2026-11-25):** the experiment notebooks, reports and tables were removed from
`feature/archetype-sim-v2`. They are archived in `archetypes dataset/archive_2026-11-25` (with a README index) and at
the Git tag `archetypes-experiments-archive`; `feature/archetype-v3-real` and `feature/archetype-v2-2` are pushed.

## Branches

| Branch | What it holds | Merge? |
|---|---|---|
| `feature/archetype-sim-v2` | everything in `feature/player-archetypes` (v1, `/archetype`, the app card), plus sim v2, model 2.0.1 (v2-core, k = 6, atypical check), family and blend, the IGDB enrichment fix, the Flutter card states, the model card | **Yes: the only PR** |
| `feature/player-archetypes` | v1 only; every one of its commits is in `sim-v2` (checked with `git merge-base --is-ancestor`) | **No separate PR** (it arrives with `sim-v2`) |
| `feature/archetype-v3-real` | the real-Steam-players experiment (analysis only, `notebooks/v3_real/` on that branch) | **No.** Keep it as a reference branch |
| `feature/archetype-v2-2` | the v2.2 recalibration experiment (analysis only, `notebooks/v2_2/` on that branch); not adopted | **No.** Keep it as a reference branch |

**Merge sim-v2 only:** one PR, `feature/archetype-sim-v2` → `main`. Don't merge the experiment branches; both are
summarised in the model card under "Experiments not adopted".

**Checked against the teammates' work (2026-11-25):**
- `main` is at `809858d` (Wrapped cache, Endgame cards, notifications). `git merge-tree` reports no conflicts for
  `sim-v2` → `main`.
- Only two files are changed on both sides: `backend/recommender/main.py` and `backend/routes/users.js`. The hunks
  are separate.
- No Wrapped file, router, `main.dart`, `home_screen.dart`, `constants.dart` or `pubspec` change comes from this
  branch.
- **Migration renamed to `015_games_achievements_count.sql`.** The teammates added `013_wrapped_ready_notification`
  and `014_wrapped_cache`. `run_migrations.js` re-runs every file in name order, and this migration is idempotent,
  so the rename doesn't affect the database.
- **The local `wrapped.py` edits were discarded** in favour of the teammates' version. They're saved as
  `archetypes dataset/archive_2026-11-25/wrapped_py_local_edits.patch`. The working tree is clean.

## Deployment checklist

**Database**
- [ ] **Run the RAWG achievements_count backfill if RAWG is reachable, dry-run first:**
  `node scripts/backfill_achievements_count.js --dry-run`, check the report, then run it without `--dry-run`.
  RAWG responded on 2026-11-25 (HTTP 200, with `achievements_count` in the game details). The backfill has not run
  yet: on 2026-11-24, 0 of 1,195 games had `achievements_count`. Until it runs, every real user's trophy rate uses the
  achievements-table fallback (see the model card's limitations). New games get the count from `saveGameToDB`.
- [ ] Optionally run `node scripts/backfill_igdb_enrichment.js --dry-run`, then without `--dry-run`, to fill
  `game_modes` for the 692 games (58%) still without them. All 50 games in manual logs already have modes.
- [ ] Migration `015_games_achievements_count.sql` (was `013_…` before the rename) is applied (already done). Confirm with
  `SELECT column_name FROM information_schema.columns WHERE table_name = 'games' AND column_name = 'achievements_count';`.
  No other migration is needed.

**Python recommender** (`backend/recommender`)
- [ ] It's bound to localhost only: `uvicorn main:app --host 127.0.0.1 --port 8000`. Don't use `0.0.0.0`.
  `/archetype` trusts the `uid` it's given and has no auth of its own, so only Node may reach it.
- [ ] `models/archetype_model.json` is **version 2.0.1**: `python -c "import json;print(json.load(open('models/archetype_model.json'))['version'])"`.
- [ ] `ARCHETYPE_MODEL_PATH` is unset, or points at that file.
- [ ] The startup log shows `[recommender] archetype model 2.0.1 loaded`.
- [ ] `pip install -r requirements.txt` (no new packages for 2.0.1).
- [ ] Tests: `cd backend/recommender && pytest` (261 passing on 2026-11-24).

**Node**
- [ ] `RECOMMENDER_URL=http://127.0.0.1:8000`.
- [ ] `node --test tests/archetype.test.js tests/igdb.test.js` (21 passing).
- [ ] Smoke test: `GET /users/me/archetype` with a test user's token returns `archetype`, `scores` (summing to 100),
  `family`, `blend` and `atypical`. `GET /users/:id/archetype` for a friend returns only `archetype` and
  `description`.

**Flutter**
- [ ] `flutter test test/archetype_test.dart test/archetype_golden_test.dart` (48 passing).
- [ ] The build points at the deployed Node URL.

**Monitoring after release**
- [ ] Check `/archetype` 5xx rates and the 503 "model not loaded" path.
- [ ] Expect many users to be flagged atypical: 17 of 20 survey respondents and 3 of 5 current app users were. That's
  expected for this prototype.

## Rollback

**Model only** (keeps the code; the app keeps working):
1. `cp models/archetype_model_v1.json models/archetype_model.json`, or set
   `ARCHETYPE_MODEL_PATH=.../archetype_model_v1.json`.
2. Restart the Python service. The log should say `archetype model 1.0.0 loaded`.
3. With 1.0.0, `family` is `null`, `atypical` is `false`, and `blend` still follows the 10-point rule. The Flutter badge
   and sheet handle all three: no family label, no "Closest match".

**Back to 2.0.1:** restore the file (`git checkout models/archetype_model.json`) and restart.

**Code:** revert the merge commit (`git revert -m 1 <merge>`). This removes archetypes from `main` entirely. The routes are additive, so no data migration is needed either
way: migration 015 only adds a nullable column.
