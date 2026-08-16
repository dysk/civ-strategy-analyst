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
   - version resolution: exact → nearest older (with a note about the mismatch) →
     none (with a note that ruleset details are unavailable);
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

## Plan: demographics + tourism analysis (blocked on logger data)

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

## Plan: World Congress / diplomatic victory analysis (blocked on logger data)

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

## Plan: domination + science victory progress (blocked on logger data)

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
