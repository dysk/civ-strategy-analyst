# Civ Strategy Analyst — application plan

## Context

The application analyzes Civilization 5 + LEKMOD games based on event logs
(JSONL) produced by the neighboring project `civ-narrative-logger`. Goal: determine
why a given player's strategy won/lost, and identify key moments
and decisions. Input data: a JSONL file (example: `filtered.jsonl`, 4580 events,
36 types), eventually files up to a few MB.

User decisions (confirmed):
- **Multi-game database** in Postgres (eventually cross-game analysis).
- **Game outcome**: entered manually at analysis time + fallback inference from snapshots
  (there's no victory event in the data; the game may still be in progress).
- **Interface**: CLI as the main one + a simple Rails UI skeleton (game list, report view).
- **LLM**: configurable from the start (RubyLLM), reports **in English**.
- **Storage**: a plain `game_events` table with jsonb (NOT Rails Event Store).
- **Tests**: Minitest. TDD: failing tests first → user review → implementation.

## Key facts about the data (from exploring `filtered.jsonl` and the logger's docs)

- One line = one JSON event; common fields: `event`, `turn`; most have `civ`.
- **Duplicates after session restart**: `session_started` appears every time
  the logger attaches (new game, reload, pitboss restart) — the sample file has sessions
  starting at turn 0 and 149, so events from turns 149–150 are duplicated. Dedup is the
  consumer's responsibility (confirmed in `civ-narrative-logger/docs/design-decisions.md`).
- **Team events**: `tech_researched`, `era_entered`, `war_declared`, `peace_made`,
  `teams_met` have `team`/`team_a`/`team_b` + `*_civs` arrays instead of a single `civ`.
- `snapshot` per civilization per turn: `score`, `science`, `culture`, `gold`,
  `gold_per_turn`, `faith`, `happiness`, `military_might`, `military_units`,
  `population`, `cities`, `techs` — the basis for metric curves.
- `unit_lost` has `cause` + `confidence`; `improvement_built` is sometimes nameless;
  some names are raw keys (`TXT_KEY_...`).
- `session_started` carries the roster: `players[{civ, name, human, handicap}]` + map settings.

## Stack

Rails (latest) + Postgres + Minitest + the `ruby_llm` gem (provider configurable via
ENV/parameter). Application lives in the current `civ-strategy-analyst/` directory (git init, frequent
small commits, no mentions of Claude, no push).

## Database schema

- `games` — name, map_script, map_size, game_speed, max_turns, start_era,
  winner_civ (nullable), victory_type (nullable), completed (bool, default false)
- `players` — game_id, civ, leader_name, human, handicap
- `game_events` — game_id, seq (order within the file), session_index, turn, event_type,
  civ (nullable — denormalized for queries), payload (jsonb);
  indexes: (game_id, turn), (game_id, event_type), (game_id, civ)
- `analyses` — game_id, model, report (markdown), digest (jsonb — the package sent to the LLM),
  created_at

## Architecture (3 layers)

### 1. Import (`ImportGame`)
A streaming JSONL parser (line by line — files up to a few MB, without loading everything
into memory). Creates `Game` + `players` from the first `session_started`. Tracks session
boundaries (`session_index++` on every `session_started`). **Dedup**: discards an event if
an identical one (turn, event_type, payload) occurred in a *different* session (a restart replays
the tail end); duplicates within a single session are legitimate and are kept.

### 2. Deterministic projections (pure Ruby classes, read events from the database)
- `MetricSeries` — per-civ curves from snapshots: values, deltas, ranking over time,
  crossover points (lead changes).
- `PlayerTimeline` — per civ: cities (founded/captured/lost), techs (resolving
  team→civs), policies/branches, religion (pantheon→founded→enhanced), wars (aggressor/
  defender, loss/gain balance), great people, eras, golden ages, city-states.
- `KeyMomentDetector` — key-moment heuristics: war declarations and their
  balance (cities captured, `unit_lost` spikes), score/science lead changes, order of
  era entries (tech lead), religion founding, `military_might` collapses
  (drop above a threshold), sustained score-slope divergence ("snowball"
  moment), nuclear detonations, city-state alliance takeovers.
- `OutcomeResolver` — winner/victory_type from user parameters, otherwise the
  leader of the latest snapshots + a "game in progress" flag (turn < max_turns, no result).

### 3. LLM layer (`AnalyzeGame`)
Builds a **compact digest** (JSON, on the order of 10–20 kB — not the raw 500 kB): roster,
settings, outcome/game state, per-civ metric summaries at checkpoints (every ~25 turns),
timelines, list of key moments from the heuristics. Sends it via RubyLLM (model
configurable, per-run override) with a "Civ 5 strategy analyst" prompt. Report in
English, sections: final standings, per-player strategic verdict (why winning/losing),
key moments, decisive decisions, counterfactuals. Saved to `analyses` + a file
`reports/<game>-<timestamp>.md`. Tests with the LLM client stubbed (no network).

### Interfaces
- CLI: `bin/civ import path.jsonl [--name ...]`,
  `bin/civ analyze GAME_ID [--winner Chile] [--victory-type domination] [--model ...]`,
  `bin/civ list` (thin wrappers around the services).
- UI skeleton: `GamesController#index` (game list + analysis status), `#show`
  (standings, key moments, markdown report via `redcarpet`/`commonmarker`).
  No charts for now.

## Iteration order (each: failing tests → review → implementation → commit)

1. **Skeleton**: `rails new` (Postgres, Minitest), migrations for `games`/`players`/
   `game_events`/`analyses`, models with validations.
2. **Import + dedup**: tests for line parsing, roster from `session_started`,
   session boundaries, cross-session dedup (fixture from a real file fragment),
   resilience to unknown event types (log and continue).
3. **MetricSeries** (snapshots → curves, ranking, lead changes).
4. **PlayerTimeline** (including resolving team events team→civ).
5. **KeyMomentDetector** (heuristics one at a time — each its own small TDD cycle).
6. **OutcomeResolver** + **DigestBuilder** (digest as a pure structure — easy assertions).
7. **AnalyzeGame + RubyLLM** (stubbed client; prompt as a versioned template in the repo).
8. **CLI** (`bin/civ`).
9. **UI skeleton** (2 views).

Import of the sample `filtered.jsonl` as a smoke test starting from iteration 2.

## End-to-end verification

- `bin/rails test` — green after every iteration.
- After iteration 2: `bin/civ import filtered.jsonl` → check the event count after dedup
  (< 4580, exact number to be pinned down by a test) and the 4-player roster.
- After iteration 7: `bin/civ analyze 1 --model <cheap model>` on the real file →
  report in `reports/`, manually assess the quality of the digested prompt.
- After iteration 9: `bin/rails server` → game list and report in the browser.

## Out of scope (deliberately, for later)

An API for ingesting events, charts in the UI, cross-game analyses (the schema allows for it),
an automatic file watcher, comparisons across multiple LLM analyses.

## Implementation status

All 9 iterations implemented (TDD, failing tests → review → implementation,
commit per iteration/heuristic). 89 tests, green. See `README.md` for run
instructions.

## Unimplemented ideas / for the future

- **Correlating pantheons/beliefs with victory (cross-game)** — an idea raised by
  the user while working on `KeyMomentDetector#religion_foundings`: track which
  beliefs (pantheon and founded religion) players choose across many games, and assess
  which of them correlate more often with victory. Requires a cross-game analysis
  layer (see "Out of scope" above) — per-game data is already available via
  `PlayerTimeline#religion` + `OutcomeResolver`, only cross-game aggregation is missing.
  Also recorded in Claude's memory (`idea-belief-winrate-analysis`).
- **LLM digest size** — `DigestBuilder` produces ~52 kB on `filtered.jsonl` instead of
  the assumed 10–20 kB (dominated by `timelines.city_states` and `timelines.techs/policies`).
  Deliberately left untrimmed until prompt quality is assessed against a real
  LLM (iteration 7) — if the size/cost/quality actually becomes a problem,
  first shorten `city_states` to a summary (last alliance status per city-state
  instead of the full list of friendship changes), then possibly `techs`/`policies` down to counts only.
- **Other metrics in `MetricSeries`/`KeyMomentDetector#snowballs`** — both classes are already
  generic with respect to metric name (any key from the `snapshot` payload: `culture`,
  `gold`, `faith`, `happiness`, `military_units`, `population`, `cities`, `techs`...),
  so adding a new metric to the analysis requires no code changes — just calling
  with a different string name.

## Plan: injecting LEKMOD data into the digest (fully realized)

Status: iterations 1–4 implemented (commits `86c5b05`…`c04c3ae`: columns
`lekmod_version`, `LekmodReference`, the `lekmod` key in the digest, prompt v7),
the `ids.yml` plan below closed (prompt v8), iteration 5 (A/B) carried out
2026-08-16 on v8: cost +50% ($0.15, acceptable), Counterfactuals and
Conclusion good, but 5 defects in the report (contradictory claims about
tech leadership between sections, both multipliers merged into one,
downplayed sustained -6 happiness, Aristocracy's production bonus described
as a cost, a repeated false "tech lead").
Fixed in prompt v9 (+ a new heuristic from the user: when evaluating
war gains, account for kill-triggered yields from Honor policies /
Autocracy tenets, not just the unit trade).

Context: LLM models know the base game rules (BNW), not LEKMOD — they don't know
the civilizations added by the mod (Chile, Vietnam, Bolivia...) or the changed effects.
Reference data per mod version already lives normalized in `db/lekmod/<version>/`
(see `db/lekmod/README.md`; procedure for adding a new version: `script/normalize_lekmod`).
Key pitfall: game logs identify policies/tenets/beliefs by internal
vanilla IDs, which LEKMOD keeps despite changing the display name
(`POLICY_MERCHANT_NAVY` → "Colonialism", `BELIEF_WALLS` → "Goddess of Protection") —
the reference files have these IDs inline and matching must be done by ID, not by name.

Iterations (each: failing tests → review → implementation → commit):

1. **`lekmod_version` on `games`** — migration (string, nullable — old imports without
   a version), `bin/civ import --lekmod-version 34.15` flag, stored in `ImportGame`;
   `bin/civ analyze --lekmod-version` override for already-imported games.
   `session_started` currently doesn't carry the mod version ("Lekmap v5.2" in `map_script` is
   the map version, not the mod's) — see the "outside this repo" note below.
2. **`LekmodReference`** — a pure class reading `db/lekmod/<version>/`:
   - version resolution: exact → nearest snapshot from the same major line, either side,
     ties to the older (minor versions are hotfixes) → nearest older line (with a note that
     newer civs and mechanics are missing) → none (with a note that ruleset details
     are unavailable);
   - per-entity extraction: `## Civ (Leader)` section from `civilizations.md` by civ name
     from the roster; entries from `policies.md`/`ideologies.md`/`religion.md` by ID
     (`POLICY_*`/`BELIEF_*`) appearing in the game's timelines; `general.md` in full
     or by section (decision at implementation time — see the digest-size note above).
3. **Extending `DigestBuilder`** — a new `lekmod` key in the digest:
   `{version, resolution_note, civilizations, beliefs, policies, general_rules}`.
   Only inject entities present in this game (roster/timeline), not entire files.
4. **Prompt v7** — a note: the ruleset is LEKMOD; wherever the digest provides
   descriptions of tenets/beliefs/policies, rely on them rather than knowledge of the base game;
   when reference data is missing, flag uncertainty instead of filling in with vanilla.
5. **End-to-end verification** — run `bin/civ analyze` on chile-vs-vietnam with v7+digest
   and compare A/B against v5/v6 reports in `reports/` (same game, successive prompt versions).

Outside this repo: a patch to `civ-narrative-logger` so that `session_started` emits the
active mod's version (Lua `Modding.GetActivatedMods()` gives ID + version) — then the
flag from iteration 1 becomes a fallback for old logs.

## Plan: `ids.yml` — authoritative ID→name mapping from mod sources (planned)

Context (from reviewing the v7 prompt on the real chile-vs-vietnam digest): 8 of 17
belief IDs in that game have no entry in `lekmod.beliefs`, because LEKMOD assigns
its own beliefs IDs with distorted spelling (`BELIEF_ZAKATT`→"Zakat",
`BELIEF_PEACE_GARDENZ`→"Peace Gardens", `BELIEF_DISCIPLEZ`→"Disciples"...) and
deriving the name from the ID in `LekmodReference` misses these. Instead of fuzzy matching
(rejected: with short names a silent bad match would hand the model WRONG rules
as authoritative — worse than no entry), we use the mod's sources as ground truth:
the repo `/Users/dysk/projects/Lekmod` contains the full chain
`<Type>BELIEF_ZAKATT` + `<ShortDescription>TXT_KEY_...` (Beliefs/Policies tables)
→ `<Replace Tag="TXT_KEY_..."><Text>Zakat` (language tables). Also verified
for the vanilla rename `TXT_KEY_POLICY_MERCHANT_NAVY`→"Colonialism", so a single
mechanism covers both new mod IDs and renames. Note: definitions are scattered across
files with misleading names (beliefs live partly in `CIV5Units.xml`, texts in
`CIV5Units_Mongol.xml`) — all XMLs need to be parsed, not just the "proper" files.

Iterations (each: failing tests → review → implementation → commit):

1. **`script/extract_lekmod_ids`** — argument: path to the mod checkout; parses
   all XML files, builds `Type→TXT_KEY` (Beliefs: `ShortDescription`, Policies:
   `Description`) and `TXT_KEY→Text` (both forms: `<Row Tag=...>` and `<Replace
   Tag=...>` — Replace wins, since it overwrites earlier texts), assembles and
   writes `db/lekmod/<version>/ids.yml` (`POLICY_*/BELIEF_*` → display
   name). Failing tests on minimal XML fixtures with both forms.
   `ids.yml` is committed to the repo — generation is a dev-time step when adding
   a version; runtime never touches the mod repo.
2. **Lookup layer in `LekmodReference`** — priority: inline annotation in the md
   (manual override) → `ids.yml` → the existing ID-based derivation. The result
   also gets `unmatched_ids` — IDs from the game with no entry found — so gaps are
   an explicit signal in the digest and surface during verification, not in the report.
3. **Prompt v8** — three additions from the v7 review: (a) IDs listed in
   `lekmod.unmatched_ids` (or with no entry in `lekmod.*`) = unknown effect, flag
   uncertainty instead of guessing from the ID's wording or vanilla knowledge; (b) in
   the Per-Player Strategic Verdict, consider how a civilization's `lekmod.civilizations`
   uniques supported/conflicted with the chosen strategy, when the timeline
   confirms it; (c) "(unchanged)" in the data = effect as in BNW — there, knowledge
   of the base game is appropriate.
4. **Procedure in `db/lekmod/README.md`** — a new step when adding a version:
   check out the mod tag/commit matching the version → `script/extract_lekmod_ids`
   → commit `ids.yml` alongside the md files.
5. **Only then, iteration 5 from the plan above** (A/B on chile-vs-vietnam) — with
   the complete mapping, prompt v8, and the `unmatched_ids` field (ideally empty
   for this game).

Noted during the v7 review, out of scope for this plan: `general_rules` goes in
full (digest 58→95 kB) — the first candidate to trim if A/B shows a
quality/cost problem.

## Plan: demographics + tourism analysis (implemented; A/B pending a real log)

Status: iterations 1–5 implemented 2026-08-16 (commits `a23797d`…`cd79745`),
against the snapshot shape confirmed in `civ-narrative-logger` commits
`f837f71`/`ef745e4`. Prompt v17 teaches the model to read `tourism`,
`civs_influential_on` and the new `cultural` digest key. Iteration 5's A/B
against v16 is still pending an actual game logged with the extended
snapshot — nothing in this repo's fixtures exercises real LEKMOD tourism
numbers yet.

Context: the logger's plan (`civ-narrative-logger/docs/planned-changes.md`) now
includes two snapshot extensions, both verified against the Lekmod DLL sources:
the Demographics screen's raw inputs (`production`, `food`, `gross_gold`,
`plots`) and cultural data (`tourism`, `civs_influential_on`, plus an
`influence` list per opponent — `{civ, points, level, trend}`). Until a game is
logged with the extended snapshot there is nothing to build against; the
iterations below start when such a log exists. Import needs no changes — the
jsonb payload absorbs new snapshot fields as-is, and dedup is unaffected.

What the new data buys: the demographics scalars are the trend-of-potential
indicators players actually watch in-game (production above all), and the
influence data is the only way to see cultural-victory pressure. LEKMOD builds
tourism output somewhat differently than BNW, but the victory rule itself is
unchanged — and since we log resulting influence, not its sources, the
difference doesn't matter for the analysis.

Iterations (each: failing tests → review → implementation → commit):

1. **New scalar metrics ride for free** — `MetricSeries` and
   `KeyMomentDetector#snowballs` are metric-name generic, so `production`,
   `food`, `gross_gold`, `plots`, `tourism` and `civs_influential_on` work by
   passing the name. The only code change: add the chosen ones to the digest's
   checkpoint metrics in `DigestBuilder` (production and tourism at minimum;
   decide the rest by digest-size impact).
2. **`InfluenceTimeline` projection** — a pure class over the nested
   `influence` list (the one snapshot field `MetricSeries` can't handle):
   per pair (civ → opponent) the level over time, level-transition events,
   and points-delta as the current tourism-vs-culture rate.
3. **`KeyMomentDetector` heuristics** (one per TDD cycle, as before):
   influence level transitions reaching Influential or Dominant; a civ's
   `civs_influential_on` reaching all-but-one of living majors (cultural
   victory imminent); production-rank changes (the demographics trend signal).
4. **`OutcomeResolver`** — infer cultural victory when the final snapshot
   shows `civs_influential_on` == living majors − 1.
5. **Digest + prompt vNext** — a cultural-standing section in the digest
   (per-civ tourism at checkpoints, the influence matrix at the last
   checkpoint, key influence transitions); prompt addition: assess cultural
   win chances from influence levels and trends. A/B against the previous
   prompt version on the first game logged with the new snapshot.

## Plan: World Congress / diplomatic victory analysis (implemented; A/B pending a real log)

Status: iterations 1–5 implemented 2026-08-16 (commits `478392c`…`dc4d277`),
against the event shapes confirmed in `civ-narrative-logger` commit `e7f5cd1`.
Two deviations from the plan below, found while implementing:

- Fixed a real bug on the way: `tools/filter-major.sh` in the logger repo
  silently dropped `united_nations_formed` and `resolution_passed/failed/
  repealed` (no civ-name string anywhere in those records) before this work
  started - patched there first (`civ-narrative-logger` commit `51449b5`).
- **Dropped "resolutions targeting a specific civ"** (iteration 3): the
  league API's `GetEnactProposals`/`GetRepealProposals` expose no target-civ
  field at all - a documented limit, not a logger gap - so `resolution_proposed/
  passed/failed/repealed` never carry one. Substituted a plain
  `resolutions_passed` key moment (type/proposer/turn, no target) instead.
- Iteration 2 ("resolution names via ids.yml") turned out feasible as
  planned, but only after finding the real source: `CIV5Resolutions.xml` in
  the mod's `Override` is an empty stub, and the actual `<Resolutions>`
  table lives, unmodified from vanilla BNW bar a few tweaked fields, in the
  misleadingly-named `CIV5Units.xml` (its text in `CIV5Units_Mongol.xml`) -
  exactly the pitfall `db/lekmod/README.md` already warns about for other
  tables. `lekmod.resolutions` is therefore a display-name-only map (no
  per-resolution effect prose exists to extract, unlike policies/beliefs).

Prompt v18 teaches the model to read `congress.*` and is explicit that
individual member votes are never available. Iteration 5's A/B against v17
is still pending an actual game logged with Congress data.

## Plan: World Congress / diplomatic victory analysis (original plan text)

Context: the logger's plan now includes polling the World Congress once per
turn (no DLL hook covers it — verified in `CvVotingClasses.cpp`): a per-turn
`congress_snapshot` record (host, delegates per civ, votes needed for
diplomatic victory) plus diffed events — `congress_founded`,
`congress_host_changed`, `resolution_proposed`, `resolution_passed` /
`resolution_failed` / `resolution_repealed`, `united_nations_formed`. Known
limit inherited from the game's Lua API: individual votes on Congress
resolutions are not available, only proposals, proposers, delegate counts and
outcomes. Important disambiguation: the `mp_vote` / `mp_proposal_result`
events already in the data are LEKMOD's multiplayer voting (remap/irr among
the human players), not the Congress — nothing currently in the log describes
the Congress at all.

Iterations (each: failing tests → review → implementation → commit):

1. **`CongressTimeline` projection** — a pure class over `congress_snapshot`
   and the resolution events: host over time, delegates per civ over time,
   and each resolution's life (proposed by whom → outcome → repealed?).
   `congress_snapshot` is a per-game record, not per-civ, so `MetricSeries`
   doesn't apply directly; delegates-per-civ comes out of this class in the
   same `{turn, value}` shape so downstream code can treat it like a metric.
2. **Resolution names via the LEKMOD reference** — resolutions arrive as
   `RESOLUTION_*` types; extend the `ids.yml` extraction to cover them (same
   mechanism, same Type→TXT_KEY→Text chain) so the digest shows display
   names, with unmatched IDs surfacing in `unmatched_ids` as before.
3. **`KeyMomentDetector` heuristics** (one per TDD cycle): host changes,
   United Nations formed, a civ's delegates crossing within reach of
   `votes_needed` (diplomatic victory imminent), and passed resolutions that
   target a specific civ (embargoes, ideology/religion picks) as key moments
   for that civ.
4. **`OutcomeResolver`** — infer diplomatic victory when the final snapshots
   show a civ at or above `votes_needed` around a victory session.
5. **Digest + prompt vNext** — a Congress section: host history, delegate
   counts at checkpoints, passed resolutions with proposer and display name,
   votes needed vs. best delegate count; prompt addition: weigh Congress
   control (host, delegate lead, targeted resolutions) as a strategic lever
   and assess diplomatic win chances; note explicitly that individual votes
   are unknown, so voting intent must not be invented. A/B on the first game
   logged with Congress data.

## Plan: domination + science victory progress (implemented; A/B pending a real log)

Status: iterations 1–4 implemented 2026-08-16 (commits `713557f`…`fea0005`),
against the snapshot shape confirmed in `civ-narrative-logger` commit
`cc08df4`. Confirmed the exact spaceship completion count against the mod's
own XML (`Project_VictoryThresholds`/`MaxTeamInstances`, not just the
`{apollo, booster, cockpit, stasis_chamber, engine}` field list): 6 physical
parts (3 booster + 1 each of cockpit/stasis_chamber/engine), apollo being a
prerequisite unlock rather than a counted part - this is what "5 of 6"
below actually means. `capitals_timeline`/`spaceship_timeline` ended up as
two separate classes rather than one combined one. Domination is checked
against the whole original roster (`@game.players`), not just
currently-living majors, since an eliminated rival's capital still counts
once captured. Prompt v19 teaches the model to read `victory_progress.*`
and to distinguish a part *built* (`unit_trained`) from one *assembled*
(`victory_progress.spaceship`). Iteration 4's A/B against v18 is still
pending an actual game logged with these snapshot fields.

## Plan: domination + science victory progress (original plan text)

Context: the logger's plan now adds two snapshot fields, both mirroring what
LEKMOD's own `VictoryProgress.lua` reads: `capitals` (original owners of the
major capitals a player controls, own included) and `spaceship`
(`{apollo, booster, cockpit, stasis_chamber, engine}` — parts counted only
once assembled at the capital, which no event carries). Partly covered
already: `project_completed` catches Apollo Program (space race unlocked) and
Manhattan Project, `city_captured` has a `capital` flag, and `unit_trained`
shows spaceship parts being built — but building ≠ assembling, and capital
control from events alone means replaying every capture.

Iterations (each: failing tests → review → implementation → commit):

1. **Capital-count metric** — capitals-held count derived from the `capitals`
   list in the same `{turn, value}` shape `MetricSeries` uses; the list
   itself (who holds whose capital) goes to the timeline.
2. **`KeyMomentDetector` heuristics** (one per TDD cycle): a civ taking or
   losing an original capital (cross-check with the existing `city_captured`
   flag), Apollo completion as space-race start, each spaceship-part
   assembly (diff of the `spaceship` field), and assembly reaching 5 of 6
   parts (science victory imminent).
3. **`OutcomeResolver`** — infer domination victory when one civ's `capitals`
   covers every living major's original capital, and science victory when
   `spaceship` reaches all six parts.
4. **Digest + prompt vNext** — victory-progress section: capitals held per
   civ at checkpoints, spaceship state per civ, Apollo timing order; prompt
   addition: distinguish parts built (`unit_trained`) from parts assembled
   (`spaceship`) — a built part in transit is a target, not progress.

## Plan: per-player early game boundary (implemented; A/B pending a real log)

Status: steps 1–5 implemented 2026-08-20 (commits `776bb03`…), planned in
detail in `docs/early-game-boundary.md`. Each civilization gets the turn its
opening ended: the first turn it holds both `TECH_EDUCATION` and
`TECH_METAL_CASTING` with one of the two buildings they unlock standing
(`BUILDING_WORKSHOP` for A, `BUILDING_UNIVERSITY` for B — the pairing is
crossed deliberately, since each building already requires the other
technology), or the deadline of turn 150 standard / 100 quick, whichever comes
first. When the log stops before the deadline and no milestone fired, the
boundary is the game's last turn (`reason: :game_end`) — we never report a
boundary past the end of the data.

`GameSpeed` (`app/models/game_speed.rb`) now owns the standard→speed turn
conversion and `KeyMomentDetector`'s grace period reads through it;
`PlayerTimeline#buildings` was extracted from `wonders` so ordinary buildings
are readable at all. `EarlyGame#series` feeds both the digest (`early_game`,
plus `game.early_game_deadline_turn`) and the game page's "Early Game" table.

Verified against the imported games, no re-import needed:

| Game | Civ | milestone | early game ends |
|---|---|---|---|
| #21 | Babylon (human) | 77 | 77 (milestone) |
| #21 | Arabia / Philippines / Austria | 111 / 139 / 146 | 100 (deadline) |
| #15 | Chile / Vietnam / Iroquois | 101 / 104 / 122 | 100 (deadline) |
| #15 | Bolivia | — | 100 (deadline) |
| #20 | all six (log ends turn 20) | — | 20 (`:game_end`) |

Game #20 is the regression a naive `min(milestone, deadline)` would fail.

**The threshold is not calibrated.** All three games pit one human against
`HANDICAP_AI_DEFAULT` bots, so the spread between 77 and 111/139/146 measures
the human-versus-bot gap, not the pace of real multiplayer. Treat 150/100 as a
first hypothesis to revise against the first human-multiplayer log.

The prompt now teaches the model to read `early_game.*` and to judge each
civilization's opening separately: a paragraph in "How to weigh the signals"
on what the boundary means and that its turns are speed-scaled (the prompt's
first mention of `game_speed` at all), and a requirement in "Per-Player
Strategic Verdict" that each verdict open with an early game assessment
restricted to `turn <= early_game.<civ>.end_turn`. The A/B is pending a fresh
`bin/civ analyze` run — `analyses.digest` is a frozen snapshot, so old
analyses do not gain `early_game` retroactively.

## Plan: buffer cities on Pangaea (implemented; A/B pending a real log)

Status: steps 1–4 implemented 2026-08-22, planned in detail in
`docs/buffer-city.md`. For every pair of capitals close enough to threaten each
other, the analysis now says who settled the ground between them. `BufferCities`
(`app/projections/buffer_cities.rb`) is the new projection; it feeds the digest
(`buffer_cities`, next to `capital_proximity`), the game page, and one key
moment, `KeyMomentDetector#buffer_city_losses`.

On the page the buffer cities live inside the "Capital Distances" section, not
their own. The capital layout diagram draws them: each civ takes a colour slot
from the data-viz reference palette, its capital keeps the bold marker, and its
buffer cities are plotted small in the same colour, with a thin line down each
contested corridor. Colour is redundant here - every mark is labelled and
joined to its capital - so the all-pairs CVD floor is carried by the labels,
not the hues (the eight-slot palette does not clear it alone). The full table
and the corridor thresholds sit below the map behind a collapsed disclosure,
next to the ones for the capital-distance table and — since it reads the same
city coordinates — the empire-geometry table, which lost its own `<h2>` in the
same pass. "Wonder Races" moved down below "Early Game".

The rule:

- **neighbours** — a pair of capitals at hex distance **≤ 17**
- **corridor** — a city that lies **≤ 3 hexes off the line between the two
  capitals** (`HexGrid#offset_from_line`, perpendicular distance in hexspace)
  and strictly between them (`d(A,C) < d(A,B)` and `d(C,B) < d(A,B)`) — the
  betweenness test separates a buffer from a back city on the same line.
  Recalibrated 2026-09-08 from an earlier `detour <= 6` rule (`detour =
  d(A,C) + d(C,B) − d(A,B)`): on a diagonal pair the zero-detour band is a
  wide rhombus, so a flank city scored a low detour and counted wrongly —
  `examples/india-diplo.jsonl`, Buffalo Creek. `detour` is still reported
  per city as texture (`0` = squarely on a shortest path); it no longer
  filters
- **window** — founded on or before the game-wide `EarlyGame#deadline_turn`,
  capped at the last logged turn. One clock for both sides: a per-civ boundary
  would give the faster developer the shorter window to claim contested ground
- **map** — Pangaea only, decided by `map_script`, on an **unwrapped** grid
  (`HexGrid.new(width: nil)`) — the map's ocean edges are not a route anyone can
  march, so this is the one place in the codebase that turns wrapping off
- **buffer** — of the corridor cities a civilization owns, the one closest to
  the rival capital

Foundings only, cities matched by plot rather than name (game #21 holds two
distinct cities called "Cavite El Viejo"). `applicable: false` with
`reason: :map_not_pangaea` says the map was never examined, which is a different
fact from an empty `pairs` list.

Verified against the imported games, no re-import needed:

| Game | Pair | d | first | buffers (`detour`, own/rival) |
|---|---|---|---|---|
| #21 | Arabia – Babylon | 13 | — | Arabia **none**; Babylon Dur-Kurigalzu t92 #3 pop 18 (0, 7/6) |
| #21 | Austria – Babylon | 13 | — | Austria **none**; Babylon Akkad t50 #2 pop 7 (5, 8/10) |
| #21 | Philippines – Arabia | 16 | Philippines | Cavite El Viejo t23 #2 pop 4 (3, 4/15); Damascus t65 #3 pop 12 (3, 12/7) |
| #15 | Bolivia – Iroquois | 13 | Bolivia | La Paz t25 #2 pop 4 (0, 6/7); Buffalo Creek t57 #5 pop 8 (2, 5/10) |
| #15 | Vietnam – Chile | 14 | Vietnam | Hai Phòng t31 #3 pop 4 (0, 5/9); Concepción t34 #2 pop 6 (4, 8/10) |
| #15 | Vietnam – Iroquois | 16 | Iroquois | Thành Pho Hue t75 #4 pop 8 (1, 4/13); Grand River t43 #3 pop 6 (0, 4/12) |
| #20 | six pairs (log ends turn 20) | 13–17 | — | none on either side; `window_turn` 20 |

**The absence predicts the conquest.** The two civilizations with no buffer
against Babylon are exactly the two whose capitals it took — Mecca on turn 144,
Vienna on turn 192. Game #20 is the regression an uncapped window would fail.

The race fields separate cases the turn alone confuses. The Philippines' turn-23
corridor city came five turns after `POLICY_COLLECTIVE_RULE`, so it is fast *and*
cheap; Vietnam's Hai Phòng (t31, city #3, capital pop 4) had Collective Rule 39
turns away and was genuinely paid for; Babylon's Dur-Kurigalzu (t92, capital pop
18) is a late filler into uncontested ground. `reach_before` — the furthest that
civilization had already settled before founding the corridor city — is what
makes "it could have gone earlier" measurable without terrain.

`buffer_city_losses` fires at any point in the game, not only the early one:
that is the premise, a debt incurred in the opening and called in later. It
names `captured_by` and `against` separately because they are frequently
different civilizations. On #21 it reports one loss, Cavite El Viejo falling to
Arabia on turn 87. Medina (t152) is **not** one: it is a corridor city for
Arabia against the Philippines, but Damascus sits further forward, and the rule
takes only the forward-most city as the buffer.

**Neither threshold is calibrated.** All three example games are
`WORLDSIZE_TINY` with one human against `HANDICAP_AI_DEFAULT` bots, and every
pair lands at 13–17, so the 17 has never had to decide a close case; it is an
absolute hex count that does not scale with map size. The lateral tolerance of
3 is likewise a first hypothesis — it started life as `detour <= 6` and was
retightened once a fourth game (`india-diplo`) showed detour passing a flank
city on a diagonal pair. The verification tables above were computed under the
old rule; `detour` values in them are still correct as reported figures, but
whether each flank-ish city still counts as a buffer needs the pending fresh
`bin/civ analyze` run to confirm. Revisit both thresholds against the first
larger map and the first human-multiplayer log.

The prompt now teaches three things in "How to weigh the signals": what a
missing buffer means for a war on that front and how `from_own_capital`,
`from_rival_capital` and `detour` place the city; the race — `settled_first`,
`order`, `capital_population`, and the instruction to check
`POLICY_COLLECTIVE_RULE` before reading an early corridor city as a sacrifice;
and restraint — that `reach_before >= from_own_capital` is a fact about
priorities only, that an agreement between neighbours is unverifiable from a log
carrying no diplomacy beyond `war_declared` and `peace_made` and no terrain at
all, and that `priority` names a sequence and never an intended target. The
Per-Player verdict now covers whether a civilization secured its corridors, and
Counterfactuals read the gap between a `buffer_city_lost` and a capital falling
as the warning the defender actually had. The A/B is pending a fresh
`bin/civ analyze` run — `analyses.digest` is a frozen snapshot.

Sketched, not started: **city-states as buffers**. A city-state in the corridor
blocks expansion, absorbs the first strike, and — allied — fights alongside its
patron, so a corridor city-state graded by control (unowned / your ally / third
party's ally / conquered) is worth a row and its gain or loss a key moment. The
log already carries it (`city_state_snapshot.ally` + `relations[]`,
`city_state_ally_changed`, `city_captured`). Full design, the Ljubljana example
from `india-diplo`, and the three open questions (annex boundary, third-party
ally, what makes a control change a moment rather than churn) are in the
"Proposed extension" section of `docs/buffer-city.md`.

## Plan: import at the logger's new volume (implemented)

`civ-narrative-logger` is adding stock fields to `snapshot` and a
per-city, per-turn `city_snapshot` record before the first human
multiplayer game. That takes a full game from ~6k rows and ~1 MB to
~40k rows and ~20 MB. The format does not change and Postgres does not
care; `ImportGame` does, in three places: cross-session dedup retains
every parsed payload in a Set and deep-hashes each line against it, the
import runs one `create!` per line, and `KNOWN_EVENT_TYPES` has drifted
so far that eight already-emitted types are missing from it — which
would turn into ~29k warning lines the moment city snapshots arrive.

All three are done, and the file now carries what the change actually
cost and what it turned up on the way — including a dedup that had
stopped working the moment the logger started stamping records with the
engine clock: `docs/import-volume.md`.

## Plan: the game's outcome, read rather than inferred (implemented)

Status: tranche 1 point 0 of `docs/reading-the-new-log.md`, implemented
2026-09-07 (commits `415faa7`, `3d61926`, `0b71022`). Three TDD cycles,
one commit each. Untested against a real log: none of the three example
games carries `game_ended` or any `mp_*` record — all are effectively
one human against bots.

Context: `OutcomeResolver` inferred the winner from the last score
snapshot and `civ analyze` took `--winner` / `--victory-type` by hand,
because the plan predates any victory event in the data. The logger now
emits `game_ended` (`victory`, `winner_civs`, `winner_team`,
`winning_turn`), and LEKMOD's own multiplayer vote system emits
`mp_proposal_result` for irrelevance / concede / scrap / remap proposals.

What the log turned out to carry, checked against `civ-narrative-logger`
`src/victory.lua`, `src/extractors.lua` and LEKMOD's
`ProposalChartPopup.lua` `onProposalResult`:

- **concede** passing calls `Game.SetWinner(subject.team, VICTORY_DIPLOMATIC)`,
  so it already arrives as `game_ended` — labelled a diplomatic win. No
  outcome work needed; relabelling it from a genuine delegate win is a
  follow-up, not a correctness gap.
- **scrap** passing calls `Game.SetWinner(activePlayer.team, VICTORY_SCRAP)` —
  the winner is only the client that resolved the vote. `game_ended` fires
  with a meaningless `winner_civs`. Inference would either store that
  garbage or fall through and invent a score-leader winner for a game
  nobody won. Handled here.
- **irrelevance** passing kicks the subject and does *not* call
  `SetWinner`, so `game_ended` never fires; the game continues one major
  short. Not an outcome — a `KeyMomentDetector` moment.
- **remap** is a lobby mechanic with no game meaning; ignored.

Iterations (each: failing tests → review → implementation → commit):

1. **`ImportGame` reads `game_ended`** — writes `completed`, `victory_type`
   and the winning roster beside `apply_game_settings`. `victory_type` is
   mapped onto the words `OutcomeResolver#inferred_result` already uses
   (`VICTORY_SPACE_RACE` → `science`), unknown ids fall back to the
   prefix-stripped downcase. `VICTORY_SCRAP` → `scrapped`, both winner
   columns nil. `winner_civs` is a Postgres string array (migration
   `20260907125123`) so a team win keeps every member; `winner_civ` stays
   as the first for the views and CLI that show one name. The `game_ended`
   event is still stored — the key moment detector and chronicle spine
   read it too.
2. **`OutcomeResolver` gains `source: :logged`** — between `:declared` and
   `:inferred`: a hand-given `--winner` still wins, but a finished game is
   no longer re-derived from its last snapshot. Reads the persisted
   columns (`@game.completed?`), not the event, to avoid duplicating the
   `VICTORY_TYPES` map. A scrapped game returns no winner and does not fall
   through to inference.
3. **`KeyMomentDetector#players_declared_irrelevant`** — off
   `mp_proposal_result` where `type == "irrelevance"` and
   `status == "passed"`. `ChronicleSpine` weights it 3 (anchors its own
   entry — a contender leaving reshapes every standing that follows).
   `PlayerTimeline#irrelevance(civ)` records the vote against the civ it
   removed, so the digest can say why that civ stopped mattering. Both
   reach the digest via `DigestBuilder`.

Not done, left for later: relabelling a concede-driven `VICTORY_DIPLOMATIC`
in the digest when an `mp_proposal_result type: "concede" status: "passed"`
sits within a turn or two of `winning_turn`; a `PlayerTimeline` departure
marker unifying irrelevance with `player_eliminated` (which nothing reads
yet); and the note in tranche 2 feature 4 that irrelevance shrinks the
diplomatic-victory vote pool the way conquering a city-state does.

## Plan: population counted per city (implemented)

Status: tranche 1 point 1 of `docs/reading-the-new-log.md`, implemented
2026-09-07. Four TDD cycles. Verified against `india-diplo` (game 32) and
the `babylon-domination` fallback; no A/B pending — the change corrects a
figure rather than adding a judgement.

Context: `Demographics` spread an empire's population points evenly over its
cities before applying the `x**2.8` soul curve, because per-city sizes were
not in the log. `city_snapshot` now carries `population` per city per turn,
and because the curve is convex the even spread is a systematic
understatement that varies with the shape of the empire — 1.19×–2.66× across
india-diplo, and enough to reorder the standings (counted city by city Tibet
out-populates the Iroquois at turn 180; by the average it was the reverse).

The `sum(city_snapshot.population) == snapshot.population` join holds on
1,082 of 1,104 `(turn, civ)` pairs in india-diplo; the 22 misses are the
four reload turns and are off by exactly 2×, i.e. duplication, so the
projection groups defensively by `(turn, civ, city)` and keeps the later
payload — the convention `CongressTimeline` already uses.

Iterations (each: failing tests → review → implementation):

1. **`CityCensus`** (`app/projections/city_census.rb`, `extend Projection`) —
   `sizes(civ, turn)` returns the deduplicated city populations at the last
   `city_snapshot` turn `<= turn`, largest first; `applicable?` is false when
   the log carries no `city_snapshot` at all. Reads through `game.event_log`.
2. **`Demographics.new(city_sizes:)`** — a second constructor path that
   applies the curve to each real city size and sums. The
   `population:`/`cities:` path stays as the documented fallback. `#source`
   returns `:cities` or `:average`; `#per_city` breaks the soul count out
   city by city. `population: 42, cities: 3 → 4_856_000` still holds, and
   `city_sizes: [14, 14, 14]` agrees with it — equal cities make the paths
   equal.
3. **`ChronicleDigest#with_souls`** asks `CityCensus` first and falls back to
   the average second, recording `souls_source` (`"cities"` | `"average"`)
   on every checkpoint so the chronicler never mistakes a spread figure for
   a counted one.
4. **`city_souls`** on each checkpoint, present only when `souls_source` is
   `"cities"`: the souls of each city on its own, largest first. The
   `chronicle_game.md` figures section gains a paragraph on reading both —
   it is what lets the chronicle write "a city of some tens of thousands"
   about a named place and mean it.

Not done, left for later: `CityCensus` is used only in the `ChronicleDigest`
path, never during `DigestBuilder.new.call`, so it is not in
`DigestBuilderCostTest::PROJECTIONS` — there is no cost test over the
chronicle digest to add it to. The digest **size** assertion the
cross-cutting section calls for is a tranche-wide guardrail, still pending.
Per-city detail reaches the digest at checkpoints only, per that section.

## Plan: the wonder race (implemented)

Status: tranche 1 point 2 of `docs/reading-the-new-log.md`, implemented
2026-09-07. Five TDD cycles (iteration 2 gained an amendment cycle for the
Great Engineer question). Verified against `india-diplo` (game 32) and the
`babylon-domination` inapplicable path. Detailed rules and calibration in
`docs/wonder-race.md`.

Context: 42 world wonders were completed in india-diplo and ten of them
were contested — the log says by whom, for how long, and for how much
production — but nothing read `city_snapshot.producing`, so a race like
England sinking 425 hammers into the Louvre and losing it to Amsterdam was
invisible. There is no "wonder started" event and no gold-refund record;
the race is reconstructed by scanning `producing` up to the completion
turn, and the refund is a rule reported to the model, never a number.

Iterations (each: failing tests → review → implementation):

1. **`LekmodIdsExtractor#buildings`** + **`Wonders`** — a wonder nobody
   completes never reaches a `building_constructed` record, so a
   `db/lekmod/<version>/buildings.yml` carries every `BUILDING_*`'s display
   name and its `wonder` scope (`world`/`team`/`national`), read from the
   cap on its *class* the way `adapter.lua` does. `Wonders.for(version,
   observed:)` resolves it the loose way `UnitNames` does and falls back to
   the wonders a game was seen to complete when no catalogue is present.
   The `<Buildings>`/`<BuildingClasses>` tables sit in `CIV5Units.xml` —
   the misfiled-table trap the README already notes for Resolutions.
2. **`WonderRaces`** (`app/projections/wonder_races.rb`, `extend
   Projection`) — one record per contested completed world wonder:
   `winner`, `contended_from_turn`, `winner_finish`, and a `contenders`
   list carrying `production_invested` (last observed `production_stored`),
   `turns_left_when_last_seen`, `turns_building`, and `outcome` (`:lost`
   when still building it on the completion turn or the one before,
   `:abandoned` earlier). `rival_observed` is left nil for tranche 2 to
   fill from `spy_moved`. `applicable?` false with no `city_snapshot`.
   Amendment: `winner_finish` is `:hard_built` when the winner's last
   snapshot still estimated ≤ 1 turn, `:ahead_of_estimate` when more (a
   Great Engineer, an overflow, a chop or a grant — the log cannot tell
   which; 0 of india-diplo's 42 exercised it), `:unobserved` when the
   winner was never seen building it.
3. **`KeyMomentDetector#wonder_races_lost`** — one moment per contender
   that `:lost` with `production_invested > 0`, carrying a `scale` of
   `:close` (`turns_left ≤ 4` or `production_invested ≥ 200`) or
   `:distant`. **`#wonder_races`** — the light race-start moment at
   `contended_from_turn`. Both reach the digest via
   `DigestBuilder#key_moments`; `WonderRaces` joins the digest cost test.
4. **`ChronicleSpine`** — `wonder_race_lost` weighted `4` when `:close`
   (above `world_wonder`'s 3 — the win already has a moment), `2` when
   `:distant` (texture, below the anchor threshold); `wonder_race` weight
   1. **`DigestBuilder#wonder_races`** carries every contested race in full
   at its conclusion, degrading to `{applicable: false, reason:
   :no_city_snapshots}`. Both prompts gain a paragraph: `analyze_game.md`
   on reading a race and never inventing the refund gold, `chronicle_game.md`
   on weighing a lost wonder by how close it was.

Not done, left for later: `rival_observed` (tranche 2, from `spy_moved`);
relabelling a same-turn tied loss, which reads as an ordinary `:lost`; the
`WONDER_RACE_MIN_INVESTED` floor and the `:close`/`:distant` cut are the
user's calibration, not a measurement, and are declared uncalibrated in
`docs/wonder-race.md`. `WonderRaces` hardcodes `Rails.root.join("db/lekmod")`
rather than taking the root `DigestBuilder` threads for `UnitNames` — it
uses the catalogue for display names only, so this has not mattered yet.

## Plan: what a city was worth when it changed hands (implemented)

Status: tranche 1 point 3 of `docs/reading-the-new-log.md`, implemented
2026-09-09. Four TDD cycles. Verified against `india-diplo` (game 32) and
the `babylon-domination` inapplicable path. Detailed rules and calibration
in `docs/city-value.md`.

Context: `ChronicleSpine` gave `city_captured` a flat weight of 4, rating
the Iroquois capital (a fifth of their potential, a third of their
science) and a border town alike. `city_snapshot` now carries per-city
population, buildings and yields, so a capture can be priced as a share of
the owner's empire rather than read off a bend in the empire-wide
`population` line — a workaround the analyze prompt no longer needs.

Iterations (each: failing tests → review → implementation):

1. **`CityValue`** (`app/projections/city_value.rb`, `extend Projection`)
   — `at(city, turn)` reads the last `city_snapshot` of the city on or
   before `turn`, takes the owner from that row, and reports
   `<metric>_share` and `<metric>_rank` for population, buildings and the
   five per-city yields, each over the owner's own cities at that turn —
   never over the empire-wide `snapshot`. Nil share for a yield the empire
   earns nothing of; reload dedup keeps the later payload. `applicable?`
   false with no `city_snapshot`.
2. **`PlayerTimeline#cities`** — every `:captured` / `:lost` entry gains a
   `valuation`: `value` (`CityValue#at(city, capture_turn - 1)`, the
   losing empire's share), `before` / `after` population and buildings
   (last snapshot under the old owner, first under the new), `resistance`
   (the captor's snapshots from the capture turn to the first with
   `resistance_turns` zero, each with `occupied` / `puppet` / `razing`),
   and `captor_influence` (the new owner's influence over the old on the
   capture turn). Nil entirely with no `city_snapshot`. `CityValue` joins
   the digest cost test.
3. **`ChronicleSpine`** — the `city_captured` moment gains a `scale`:
   `:major` (weight 4) when the payload has `capital: true` or the city's
   `population_share` the turn before was ≥ `0.20`
   (`MAJOR_POPULATION_SHARE`), `:minor` (weight 3, `ANCHOR_WEIGHT` — the
   lightest entry, a sentence) otherwise, absent when no `city_snapshot`
   places the city and then the weight stays flat at 4. Every capture
   still anchors: a small city changing hands is a shorter passage, never
   a dropped one. (First shipped with `:minor` at 2, below the anchor
   line, which let small captures fall into `background`; corrected on
   user feedback.)
4. Digest + both prompts + docs. The `valuation` reaches the digest for
   free through `timelines.<civ>.cities`; captures are one of the
   checkpoints the cross-cutting rule allows per-city detail at.
   `analyze_game.md`: the "read the bend in the `population` line"
   paragraph is replaced with the `valuation` fields, the
   gain-is-less-than-loss rule kept, the cession exception and the
   resistance/`captor_influence` mechanism added. `chronicle_game.md`
   gains a "When a city changes hands" section on weighing the moment by
   `scale` and drawing the sacking from the `valuation`.

Not done, left for later: razing (`city_destroyed` with no matching
capture) is not valued — only captures are. `MAJOR_POPULATION_SHARE` and
the population-only choice of metric are the user's calibration, declared
uncalibrated in `docs/city-value.md`; `babylon-domination`'s eight
captures carry no `city_snapshot` and exercise only the flat fallback.
`rival_observed`-style "did the captor have a spy in the city" is a
tranche 2 join, not attempted here.

## Plan: espionage — the primitive four features share (iterations 1-2 of 6)

Status: tranche 2 point 4 of `docs/reading-the-new-log.md`. **Iterations 1
and 2 implemented 2026-09-11** — `applicable?`, `#tenures`, `#missions`,
`#losses` and `#capacity` in `app/projections/espionage.rb`, 40 tests,
measured against `india-diplo` (game 32, 24 located spies, 46 tenures) and
`espionage-test` (game 37, 13 spies, 37 tenures). Iterations 3–6 are not
built: `#counterspies`, `#coups`, the `WonderRaces` join and the digest
section. `WonderRaces#rival_observed` still carries nil and still
waits for `observers_of`. The design is in `docs/espionage.md` (the game
rules and the honest limits) and `docs/reading-the-new-log.md` (§4).

Context: a spy is a position held over a span of turns, and four questions
join against it — did a wonder-race loser see the winner's build, what
moved a city-state's influence, was an empire garrisoned against theft,
did a paradrop have a spotter. The primitive is `Espionage#tenures`; the
rest of the projection hangs off it.

The reason this section exists before the projection does: **the espionage
half of the log was mostly reconstruction, and a run of `civ-narrative-logger`
fixes has since turned much of it into fact.** As of those commits:

- `spy_surveillance_established` — `visible_from_turn` is a logged event,
  not `posting + 1 + surveillance_time` arithmetic.
- `completed()` requires an unchanged state — the "23 of 53 completions
  are state-transition artifacts" filter is no longer needed on new logs;
  `missions(civ)` can count `spy_mission_completed` straight.
- `spy_created` and `spy_killed` carry a `city`/`city_civ` — `losses`
  reads the death site off the record rather than the last known tenure.
- `spy_moved` fires after a revival into a city — the revival half of the
  missed-posting gap is closed.
- `spy_moved` fires on the transition into `counter_intel` — a counterspy
  garrison is read from the event, and `#counterspies`' three-signal
  inference drops to a fallback.
- every spy record carries `agent`, the `AgentID` a revival cannot change —
  `tenures` keys on `(civ, agent)` where the field exists, and only older
  logs need the "a revival names a spy that never existed" fallback.
- the `CityX == -1` half of the missed-`spy_moved` gap turned out not to
  exist: run B (`examples/run-b-test.jsonl`) logged every spy every poll
  across 26 reassignments and all 26 were announced.

Still owed upstream, so the projection keeps the older logs' fallbacks:
`known` persisting across a session reload — which is all that is left of
the missed-`spy_moved` gap, and the reason `ENGLAND_6`'s re-posting is
absent — and the successful coup (needs its own `CanStageCoup` read).
Tracked in `civ-narrative-logger/docs/planned-changes.md`.

`examples/india-diplo.jsonl` (game 32), the log every number in the design
docs is measured against, **predates all of these fixes**. So iteration 1
must ship the fallbacks — the arithmetic dating, the completion filter,
the tenure-inferred death site, the counterspy inference — and the
event-reading paths stay unexercised until a post-fix log is imported,
declared unexercised the way `winner_finish`'s `:ahead_of_estimate` is.

Iteration 1 shipped both paths, and a post-fix log exercises the
event-reading half: 16 of `espionage-test.jsonl`'s 37 tenures are dated off
`spy_surveillance_established`, 15 of those at exactly +4 and one at +0
where the event was itself the first sighting. India-diplo carries no such
event and falls back to the arithmetic for 33 tenures and to the bounded
floor for 12. The `agent` key is the one path still unexercised at volume — only
`run-b-test.jsonl` carries the field, and it logs no `spy_created` at all.

The run measured one correction to the design. A counterspy's state arrives
a turn behind its order, in a second `spy_moved` in the same city, so the
garrison has to be read off the whole tenure; reading only the posting dated
4 of `espionage-test`'s 5 garrisons at +4, as if they were waiting for a
city screen to open. Recorded in `docs/espionage.md`.

Building it turned up three more, all about where a tenure **ends**, and one
of them was a hole in the log rather than in the reading:

- **A spy thrown out of a captured city was invisible.** Taking a city or
  razing one evicts every major's spy that sat in it, the captor's own
  included, and no branch of the logger's diff could see it — an unassigned
  spy has no destination and no progress. The posting just stopped being
  mentioned, which reads as a spy still watching. Fixed in the logger
  (`spy_evicted`, commit `8bd4804`) rather than inferred here from
  `city_captured`: the logged fact covers conquest, razing, liberation and a
  gifted city in one branch, and no example log carries an instance for an
  inference to be exercised against. The analyst also breaks a run when the
  city's owner changes between two sightings, which is the one case the
  event misses — a spy sent back in on the turn it was thrown out.
- **A kill the logger could not place left a tenure open to the end of the
  game.** All nine of india-diplo's deaths carry no city, so none of them
  was a sighting and none closed anything: nine spies read as watching
  Delhi through turn 184. A kill now closes the tenure it falls in without
  extending `to_turn`, and the nine land where the ledger says they should.
- **A span has two ends worth reporting.** `to_turn` is what the log proves
  and `until_turn` is when the spy left by the best evidence, which for a
  quiet tenure is the last turn logged. Zimbabwe's spy in London was sighted
  95–136 and watched for 48 more turns nothing records. `observers_of` will
  join against `until_turn`; the digest reports `to_turn`.

Iteration 2 is the ledger in `docs/espionage.md`, and it reproduces both
tables cell for cell: 23 artifacts, 21 real completions and 9 unanchored in
india-diplo with the same split across all six civs, 24 real completions and
no filtering at all in espionage-test, nine deaths in Delhi and Arabia's one
at Valletta. Two anchoring rules decide those numbers and both are written
down where the tables are. A completion's kind comes off the record's own
`state` rather than from whose city it was, which the design had proposed —
every completion in both logs carries one, so the join and the city-state
list it needed are unnecessary.

When iterations 3–6 land, this becomes an `(implemented)` section with the
commit range and the per-iteration notes, like the tranche-1 features above.

## Plan: great people — appearance, use, and death (planned)

Status: **Not implemented as its own reading.** `PlayerTimeline#great_people`
today reads only `great_person_expended` and returns `{turn, great_person}`,
surfaced in the digest as `great_people:`. It shows a bare list of "civ
expended a Great X on turn N" — no birth, no what the expend was *for*, no
death.

Everything below is already in the log and already in
`ImportGame::KNOWN_EVENT_TYPES`. This is analyst logic only; no
`civ-narrative-logger` change is needed.

**Appearance.** `unit_created` carries `unit` (the unit *type* name, e.g.
`Great Scientist`), `civ`, `city`, `x`, `y`, `turn` — for every unit,
great people included. Filtered to the great-person unit types it is a
births timeline: which great person, on what turn, in which city. The one
appearance signal used now is the per-turn `great_people` /
`great_generals` counter in the player stats snapshot, which carries no
type and no name.

**Use, with a target.** A great person that plants an improvement fires
`BuildFinished` before it is expended, so the log holds, same civ same
turn, both an `improvement_built` (`improvement` type, `x`, `y`) and a
`great_person_expended`. Pair them and the expend has a target: Academy,
Manufactory, Customs House, Citadel, Holy Site, Landmark.

**Use, without a target.** A `great_person_expended` with no same-turn
`improvement_built` for that civ is an instant use — bulb (Scientist),
hurry production (Engineer), trade mission (Merchant), Great Work /
treatise / concert tour (Artist / Writer / Musician), a religious action
(Prophet). The great-person type narrows it to one or two; nearby context
(a wonder in progress in one of the civ's cities) separates Engineer hurry
from Engineer manufactory.

**Death by an enemy.** `unit_lost` (from `UnitPrekill`) carries `civ`
(owner), `unit` (type), `city`, `x`, `y`, and `killed_by` (the killer's
civ, nil when there is none). A Great General destroyed in a raid is here
with `killed_by` set. Combat deaths also emit `unit_killed`
(`killer` / `victim` / `unit`).

**Telling the three fates apart** for a great-person unit that leaves play:

- `killed_by` set, no same-turn `great_person_expended` → killed by an enemy.
- `killed_by` nil *and* a same-turn `great_person_expended` for that civ →
  expended (the expend path also fires `UnitPrekill`, with no killer).
- `killed_by` nil, no `great_person_expended` → disbanded by the owner
  (rare for a great person).

Limits:

- `unit` / `great_person` are unit *type* names, never the individual's
  flavour name. Two great people of one type expended by one civ on one
  turn cannot be told apart, and an improvement cannot be matched to a
  specific one. Uncommon.
- The great-person ↔ improvement pairing is `(turn, civ)` coincidence, not
  an id. On a turn a civ finishes a worker farm and an Academy there are
  two `improvement_built` rows; take the great-person-improvement type. Two
  great-person improvements, same civ, same turn is possible but rare.
- `improvement_built` carries only `x` / `y` and `great_person_expended`
  carries no location; tile→city is the projection's job, from
  `city_snapshot` the way `PlayerTimeline#valuation` already does it.
- The great-person unit-type list is mod-defined and belongs in `ids.yml`
  (its own planned section above), not hard-coded here.

Shape: extend `PlayerTimeline#great_people(civ)` to return
`{turn, great_person, fate: :expended|:killed|:disbanded,
action: :academy|:manufactory|:bulb|:hurry|…, city, killed_by}`, or split
a `GreatPeople` projection off if the joins grow. The digest already wires
`great_people:`, so a richer row is backward compatible.

A/B: `india-diplo.jsonl` (game 32) is a usable target — it carries
`unit_created` (1402), `unit_lost` (1041), `improvement_built` (985),
`unit_killed` (194) and `great_person_expended` (88), all at volume, and
none of these events changed in the recent logger work (that was
espionage and congress only). The regression signal is the classification
split: how many great people bulbed versus planted, how many Great
Generals died to raids.
