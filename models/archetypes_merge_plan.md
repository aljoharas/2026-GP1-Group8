# Player Archetypes: merge plan and deployment checklist

**Status:** nothing is merged yet. This plan is for review.

## Branches

| Branch | What it holds | Relation to `main` | Merge? |
|---|---|---|---|
| `feature/player-archetypes` | v1: features, simulator, model 1.0.0, `/archetype`, app card | 5 commits ahead; `main` is an ancestor; pushed | **Yes**, first |
| `feature/archetype-sim-v2` | everything in `player-archetypes`, plus: sim v2, model 2.0.1 (v2-core, k = 6, atypical check), family and blend, survey validation, Flutter card states, model card | branched from `player-archetypes`; merges into `main` with no conflicts (checked with `git merge-tree`); **local is ahead of `origin`**, the latest commits aren't pushed | **Yes**, second |
| `feature/archetype-v3-real` | the real-Steam-players experiment (analysis only, `notebooks/v3_real/`) | branched from `sim-v2` at `f9250fa` | **No.** Keep it as a reference branch. Its notebooks aren't needed in `main`. |
| `feature/archetype-v2-2` | the v2.2 recalibration experiment (analysis only, `notebooks/v2_2/`); not adopted | branched from `sim-v2` | **No.** Keep it as a reference branch. |

**Order:**
1. **PR 1: `feature/player-archetypes` → `main`.** Reviewing v1 on its own keeps the diff readable.
2. **PR 2: `feature/archetype-sim-v2` → `main`.** It now contains only the v2 work on top of PR 1.

   Push it first (`git push origin feature/archetype-sim-v2`): `origin` is several commits behind.

   *Alternative:* if one PR is preferred, merge `sim-v2` alone. It contains every `player-archetypes` commit.
3. Don't merge `feature/archetype-v3-real` or `feature/archetype-v2-2`. Both experiments are summarised in the
   model card under "Experiments not adopted".

**Before opening the PRs:** the working tree has your own uncommitted, unrelated changes. Keep them out of both PRs,
or commit them on their own branch first:
- modified: `backend/recommender/wrapped.py`
- untracked: `flutter/test/failures/`

The IGDB enrichment fix (`routes/games.js`, `lib/igdb.js`, `scripts/backfill_igdb_enrichment.js`,
`tests/igdb.test.js`) is now committed on `feature/archetype-sim-v2` (`18a09bf`). Only `wrapped.py` (comment edits)
and `flutter/test/failures/` stay uncommitted.

## Deployment checklist

**Database**
- [ ] **Run the RAWG achievements_count backfill: `node scripts/backfill_achievements_count.js`. It has not run yet:
  on 2026-11-24, 0 of 1,195 games had `achievements_count`.** Until it runs, every real user's trophy rate uses the
  achievements-table fallback (see the model card's limitations). New games get the count from `saveGameToDB`.
- [ ] Optionally run `node scripts/backfill_igdb_enrichment.js --dry-run`, then without `--dry-run`, to fill
  `game_modes` for the 692 games (58%) still without them. All 50 games in manual logs already have modes.
- [ ] Migration `013_games_achievements_count.sql` is applied (already done). Confirm with
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
- [ ] `flutter test test/archetype_test.dart test/archetype_golden_test.dart` (36 passing).
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
3. With 1.0.0, `family` is `null`, `atypical` is `false`, and `blend` still follows the 10-point rule. The Flutter card
   handles all three: no family label, no "Closest match".

**Back to 2.0.1:** restore the file (`git checkout models/archetype_model.json`) and restart.

**Code:** revert the PR 2 merge commit (`git revert -m 1 <merge>`). This takes `main` back to v1 (PR 1).
Reverting PR 1 as well removes archetypes entirely. The routes are additive, so no data migration is needed either
way: migration 013 only adds a nullable column.
