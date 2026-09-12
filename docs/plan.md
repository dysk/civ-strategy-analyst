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
- **Tile→city resolution** — raised while reviewing great people: no projection
  resolves a bare `x`/`y` (as `improvement_built`, `unit_lost`, `unit_created` carry)
  to the city that owns the tile; the nearest precedent, `PlayerTimeline#valuation`,
  matches by city *name* already present in the event payload, never by geometry.
  A civ's founded/captured plots plus `HexGrid#distance` would give a
  nearest-owned-city-to-a-tile lookup as a small, reusable primitive. Two known
  users if it's ever built: naming the city for a targeted great-person expend
  (`PlayerTimeline#great_people`, currently left nil), and giving `ChronicleSpine`
  a place name for a battle death (`unit_killed`/`unit_lost` carry `x`/`y` but no
  city) instead of narrating combat with no location at all.

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

## Plan: espionage — the primitive four features share (complete)

Status: tranche 2 point 4 of `docs/reading-the-new-log.md`, **finished
2026-09-11**. `applicable?`, `#tenures`, `#missions`, `#losses`,
`#capacity`, `#counterspies`, `#coups` and `#observers_of` in
`app/projections/espionage.rb`; the observation fields on every
`WonderRaces` contender and the acceleration on every builder; the
observation carried onto `wonder_race_lost`; an `espionage` digest section;
and both prompts. Measured against `india-diplo` (game 32, 24 located
spies, 46 tenures, 30 missions after filtering, 9 losses, 3 garrisons, 0
coups) and `espionage-test` (game 37, 13 spies, 37 tenures, 24 missions, 1
loss, 6 garrisons, 1 failed coup). `WonderRaces#rival_observed` is filled, and carries nil only where the log
holds no spy record at all. The design is in `docs/espionage.md` (the game
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
- `spy_moved` fires on the transition into `counter_intel`, and
  `spy_created` now carries `state` — a garrison is read from the log both
  when the spy is posted in place and when it settled in before the session
  started, and `#counterspies`' three-signal inference drops to a fallback
  chosen per civ.
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

Iteration 3 found the "india-diplo mentions no counterspy" claim wrong.
England pulled `ENGLAND_1` home to London on turn 156, and because that
spy moved to get there the ordinary branch fired and carried the state,
so the log records it. The read and the inference are therefore chosen
per civ: India's garrison in the same log is invisible and inferred at
confidence 3. Six garrisons are read across the two logs and three
inferred, and `#counterspies` leaves a death at a city-state out of its
evidence, since a failed coup is the one way a spy dies with no
counterspy near it.

The `spy_created` gap came out of the same iteration and was fixed
upstream first, the way the eviction gap was. A counterspy that settled
in before a session reload makes its `counter_intel` transition once and
never again, so the creation record was the only thing that could carry
it. Mysore's `MC_MUGHAL_0` on turn 151 is the near miss — announced in
Mysuru with no state, and visible only because the player re-ordered it
on 152.

Iteration 4 found the documented coup formula pointing the wrong way. It
added the decay instead of undoing it, which put Arabia at Valletta on
−6.75 rather than −9.25. The detector reconstructs the penalty at the turn
of the kill and tests it near −10 with a margin of 2, since the DLL's flat
−10 reaches the log as the integer −8 after one turn of recovery and the
0.75 that leaves over is unexplained.

The successful-coup branch fires on nothing, which is the documented
expectation, and two of the 68 ally changes in the two logs reach the swap
test with snapshots on both sides and are rejected on their numbers rather
than for want of data.

Iteration 5 replaced the planned rate threshold twice. The estimate looked
like the threshold-free answer - `production_turns_left` falls by one a
turn under a steady build - and measurement killed it: across both logs it
fell faster than the clock on 23 turns, 20 of which brought no extra
production and four of which came with less. The ceiling amplifies a small
rate rise at distance, and London's Louvre gained two turns on its estimate
while producing an ordinary 44 hammers.

The test is the production gain instead. A turn standing at least twice
clear of the build's own typical turn is a Great Engineer, a chop or an
overflow, which is the same trio `:ahead_of_estimate` cannot separate. The
factor sits in a gap the data has - three survivors at 2.09, 2.28 and 2.29
against a next-highest of 1.50.

Acceleration is recorded for every builder with or without a spy, because a
wonder under construction shows on the map and its unfinished form names it.
Line of sight tells a player *what* a rival is building; the spy tells it
*how close*. So `response` says what a contender did and `observed_from_turn`
says what it knew, and the two are never folded together.

Running the join over both games found three errors no fixture showed. The
decision window must end at `completed_turn − 1`, or Mysore reads as having
seen Mecca finish Pisa on the turn its own surveillance went live. A tenure
whose `visible_from_turn` falls after its `until_turn` granted nothing —
`MUGHAL_5` was sent to Brussels on 152 and pulled home on 155, a turn short.
And a civ sitting in its own city is not an observer of it, which was
putting Arabia in the list of civs watching Mecca.

The one human contender row in either game is India abandoning Machu Picchu
on turn 110 with no vision of Great Zimbabwe, which comes out `:cut_losses`.
Zimbabwe put 57 hammers into the same wonder the turn before, which is an
adjacency and not a cause - India could not see a hammer of it. Every other
contender row is an AI and ships unlabelled.

Iteration 6 added no new moment type. The design called for
`wonder_race_lost_while_watching` and the honest form of it is the
observation travelling on the existing `wonder_race_lost`, since
`ChronicleSpine` must not anchor a second entry on one event. One race in
each log is lost in full view - England's Louvre from turn 152, Belgium's
Pisa from 156 - and both contenders are an AI, so `response` is nil on both
and the moment ships with no exercised instance of the sentence it exists
for.

The digest section runs 19KB of india-diplo's 184KB and 15KB of
espionage-test's 119KB, roughly a tenth in both. Tenures are carried whole
at 46 and 37; the cross-cutting rule applies if a longer game produces
hundreds.

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

All six iterations landed: `5b0ff3e`, `e7f3742`, `17f497b`, `d150abe`,
`efc4702`, `8dfa0fe`, `f0c098e`, `607595d`, `760fb70`, with `8bd4804` and
`74d13d5` upstream in `civ-narrative-logger`.

## Plan: espionage on the page (implemented)

Status: **Implemented 2026-09-11** (commits `abd7664`, `6d86f39`,
`b5df27c`, `92d6be5`). Espionage now has both a summary row on `games#show`
and its own page, `EspionageOperationsController#show`, matching every
other substantial projection.

One departure from the plan below, found while implementing: "capacity and
losses per civ" as a single table would have flattened `city_inferred` and
`turns_since_last_seen` into a bare count, which is exactly the distinction
the page exists to preserve (see the "three things" list). Losses got their
own table instead — one row per death, civ across the whole game rather
than folded per civ, since a handful of losses does not need the fold a
zero of thousands of tenures does. Capacity stayed a single per-civ table
with `killed` as its loss count, unchanged from the plan.

What follows is the plan as written.

Status (as planned): Espionage reaches the digest and both prompts
and stops there. `games#show` has no espionage section and there is no
espionage page, so the only way a reader sees any of it is by reading an
LLM report. Every other substantial projection has both — `geometry`,
`army`, `cultural`, `congress`, `victory_progress` — and this one has
neither.

Context: the projection is done and none of this adds a line of analysis.
`Espionage` already answers `tenures`, `missions`, `losses`, `capacity`,
`counterspies`, `coups` and `observers_of`, and the house pattern for a
feature page is a controller that only arranges what a projection returns —
`ArmyCompositionsController` samples every tenth turn,
`CulturalStandingsController` merges two series, and neither computes
anything. So this is presentation work, and any calculation that appears in
a controller here is a sign it belongs in the projection instead.

**Three things the page must show differently from a column of numbers**,
because a table that flattens them lies exactly the way a prompt without the
rules would:

- `visible_from_turn` next to `from_turn`, never instead of it. The gap is
  usually four turns and it is the whole content of the two Mysore
  near-misses — a spy that arrived and a spy that could see are different
  facts, and the second is the one a join uses.
- `visible_from_turn_bounded` and `city_inferred` have to read as "no later
  than" and "reconstructed". As bare numbers they pass for measurements.
- A garrison read from the log and one inferred at confidence 1 are two
  different claims and cannot share a column unmarked. `inferred` and
  `confidence` are on the record for this reason.

Sizes to design against, from the two imported games: 46 and 37 tenures, 30
and 24 missions, 9 and 1 losses, 3 and 6 garrisons, 0 and 1 coups, over 6
civs each. Tenures are the only table that grows badly — a longer game with
six civs running five spies each will produce hundreds — so it is the one
that needs a per-civ fold, the way `ArmyComposition` needed sampling.

Iterations (each: failing tests → review → implementation):

1. **`EspionageOperationsController#show`** + `app/views/espionage_operations/
   show.html.erb`, routed as `resource :espionage, only: [ :show ]` beside
   the other five. Four tables: capacity and losses per civ; tenures folded
   per civ with `from_turn`, `visible_from_turn`, `until_turn`, `ended_by`
   and the bounded flag; missions split by kind with `anchored: false`
   marked as uncertain rather than counted in; garrisons and coups together,
   each carrying how it was known. `applicable?` false renders the same
   empty state the other pages use. A controller test per table, in
   `test/controllers/espionage_operations_controller_test.rb`.
2. **The `games#show` section and its link.** A summary table per civ —
   spies made, spies lost, missions, garrison — and "See how the spies
   moved" pointing at the page, matching the five sections already there.
   `GamesController#show` gains one assembler alongside `army_rows` and
   `cultural_rows`.
3. **`key_moments_helper`'s `wonder_race_lost` line gains the full-view
   clause.** This is where espionage reaches a reader who never opens the
   page, and it is the one sentence the whole feature was built for. It must
   not overstate: name the years of vision, never a decision, and never at
   all where `contender_human` is false. Both live instances in the example
   logs are an AI, so the clause ships with no exercised instance and the
   test for it is a constructed human contender.

Not in scope: charts of any kind — the app renders tables and one small
capital layout, and a spy tenure is a span best read as a row. No new
projection code; if a view wants a number `Espionage` does not answer, the
answer is a method on the projection with its own test, not arithmetic in a
controller. `DigestBuilderCostTest::PROJECTIONS` needs nothing: it covers
`DigestBuilder.new.call` and these pages are not on that path.

## Plan: spy names (implemented)

Status: **Implemented 2026-09-11** (commits `2ae4f82`, `766d9e6`,
`b5b1422`, `3c9ce6b`, `e71e564`). Two departures from the plan below,
found while implementing:

- `db/lekmod/35.3/spy_names.yml` was generated by archiving the mod
  repo's commit `70aa6ad5` ("v35.3 installer push") rather than its
  working tree — the working tree had since moved to a later commit —
  following the pinning procedure `db/lekmod/README.md` already documents
  for `ids.yml`/`units.yml`/`buildings.yml`, which the plan below did not
  call out explicitly.
- Iteration 5 dropped the tooltip: nothing else in the app uses a `title`
  attribute, and the espionage page's garrisons and coups tables were
  found to carry no spy id in a cell at all (only tenures, losses and
  missions do), so there was no raw id anywhere on the page left to cross-
  reference against by the time the resolved name replaced it outright.

What follows is the plan as written.

Status (as planned): Every spy reaches the UI and the digest as its
raw id — `TXT_KEY_SPY_NAME_INDIA_7` in a table cell, the same string in the
`espionage` section an LLM reads. Raised by the user while reviewing the
espionage page just shipped.

Context: checked against the mod's own XML in `/Users/dysk/projects/Lekmod`.
A spy's id is not an indirect reference the way a policy's is — it is
**already** the `Language_en_US` text key, with no `Type` table in between:
`CIV5Units.xml`'s `Civilization_SpyNames` table lists `TXT_KEY_SPY_NAME_*`
per civilization, and `CIV5Units_Mongol.xml` carries the flavour name
directly against that same key —
`<Replace Tag="TXT_KEY_SPY_NAME_INDIA_7"><Text>Mukta</Text></Replace>`,
`TXT_KEY_SPY_NAME_ARABIA_4` → "Abyadh". `LekmodIdsExtractor` already builds
the whole `TXT_KEY → Text` map internally (`texts`, from every
`Language_en_US Row`/`Replace` in the source tree) to resolve
policies/beliefs/resolutions/units; it is just never exposed for this
prefix. So resolving a spy name costs one filter over data the extractor
already parses — cheaper than every other entry in `ids.yml`, which all
pay for the `Type → TXT_KEY` step this one skips entirely.

The bridge is the same one `unit_names` already is: the digest speaks in
ids, `lekmod.*` and the report speak in names, and `UnitNames` /
`DigestBuilder#unit_names` are the existing pattern to copy rather than
invent — a glossary keyed to only the ids this game actually logged,
version-resolved the loose way (`exact → newest snapshot that names any`),
falling back to a legible reading of the id itself rather than nothing.

Iterations (each: failing tests → review → implementation → commit):

1. **`LekmodIdsExtractor#spy_names`** — `texts.select` filtered to the
   `TXT_KEY_SPY_NAME_` prefix. No new XML table to parse; `Civilization_SpyNames`
   itself is not read, since the log's `spy` field already is the text key
   `Civilization_SpyNames` merely enumerates. Fixture rows added to
   `test/support/lekmod_source/text.xml` / `text_override.xml` covering the
   same two cases every other entity in that fixture covers: a plain `Row`,
   and a `Replace` that wins over the `Row` it overrides.
2. **`script/extract_lekmod_spy_names`** — same shape as
   `script/extract_lekmod_unit_names`, writing `db/lekmod/<version>/spy_names.yml`.
   `db/lekmod/README.md` gains a section beside "Unit names".
3. **`SpyNames`** (`app/services/spy_names.rb`) — `UnitNames` with the
   fallback changed: a spy's flavour name is never guessable from its id
   the way a unit's usually is (a unit id is mostly English with the odd
   LEKMOD rename; a spy id is a civ code and an ordinal), so the fallback
   only makes the id legible — `TXT_KEY_SPY_NAME_MC_MUGHAL_5` → "Mc Mughal
   5" — never invents a name. `.for(version, root:)`, `#call(spy)`,
   `#glossary(spies)`, same version-resolution test shape as
   `test/services/unit_names_test.rb`.
4. **`DigestBuilder#spy_names`** — a glossary key beside `unit_names`, over
   every id `Espionage#tenures` returns (a tenure exists for every spy that
   was ever located, so it is the whole roster; `applicable?` false yields
   an empty glossary rather than skipping the key). Reaches both prompts for
   free through `ChronicleDigest`, which wraps `DigestBuilder#call`. A
   paragraph in `analyze_game.md` beside the existing `espionage` paragraph,
   and in `chronicle_game.md` beside its `unit_names` paragraph, both saying
   what the `unit_names` paragraphs already say for units: resolve the id
   through the glossary, never read a name out of the id itself.
5. **The espionage page** — the `spy` cell in the tenures, losses and
   missions tables (the only three that carry one at all — garrisons and
   coups never did) reads as the resolved name. `EspionageOperationsController`
   gains `SpyNames.for(@game.lekmod_version)` alongside `Espionage.for(@game)`,
   the same way `key_moments_helper` already holds a `UnitNames` instance.

Not in scope: the games#show espionage summary is civ-level counts, no
spy identity in it, so it needs no change. Non-English name text does not
exist for spies any more than it does for units — `db/lekmod/README.md`'s
"Only English is available" note already covers this.

## Plan: espionage in the chronicle (implemented)

Status: **Implemented 2026-09-11.** `chronicle_game.md` had never
mentioned espionage at all — confirmed by grep before this work, zero
hits for "spy"/"espionage"/"tenure". Raised by the user while discussing
`spy_names`: `analyze_game.md` already reads the full `espionage` digest
section, but the chronicle read none of it.

Deliberately narrow: of `tenures`, `missions`, `losses`, `counterspies`
and `coups`, only the two that happen rarely enough to be worth a reader's
attention went in — a spy's death and a coup's outcome. `tenures` is
vision, not an event; `missions` and `counterspies` are routine enough on
a long game to flood the chronicle with texture the reader has no reason
to want. Explicitly out of scope for now, not forgotten.

The other constraint the user set: neither may ever open an entry of its
own. `ChronicleSpine` already had the mechanism for this — light moments
(weight below `ANCHOR_WEIGHT`) join the nearest chosen cluster within
`CLUSTER_GAP` turns, or fall to `background` if nothing is near, the same
path `golden_age_started` and the rest of `logged_moments`' lighter
entries already take. So `spy_killed` (weight 1) and `coup` (weight 2)
needed no new attachment logic, just two new moment builders reading
`Espionage#losses` / `Espionage#coups` into `ChronicleSpine#moments`,
proven by tests asserting each joins a nearby entry and earns none on its
own when isolated.

`chronicle_game.md` gained one short section, "Espionage as texture, not
an entry", placed beside the other event-shaped sections and instructing
the model to fold each into whichever passage it already lands in rather
than give it a scene, name the spy from `spy_names` (already reaching the
chronicle digest for free through `ChronicleDigest` wrapping
`DigestBuilder#call`), and read a coup's `outcome` as a seizure rather
than an election.

## Plan: great people — appearance, use, and death (implemented)

Status: **Implemented 2026-09-11.** `PlayerTimeline#great_people(civ)` now
returns one row per departure — expended, killed, or disbanded — and a new
`PlayerTimeline#great_people_born(civ)` returns the births timeline
separately. Both reach the digest (`great_people:`, `great_people_born:`).
Verified against `india-diplo` (game 32, 6-civ roster): 87 imported
`great_person_expended` records (the file's raw 88 minus one session-restart
duplicate `ImportGame`'s dedup already discards — not a gap in this work), 1
enemy kill (an Iroquois `UNIT_PROPHET` to India, turn 144, the same record
the original plan text used as its worked example), 0 disbandments. Expend
actions split `{religious_action: 17, academy: 6, manufactory: 7, treatise:
8, concert_tour: 8, great_work: 13, bulb: 17, holy_site: 2, trade_mission: 5,
hurry: 3, customs_house: 1}` — every kind classified, no unmatched action.

Two calls made beyond the plan text, both open to revisiting:

- **`city` stays nil for a targeted expend** (Academy/Manufactory/Customs
  House/Citadel/Holy Site/Landmark). `great_person_expended` carries no
  location at all; only the matched `improvement_built` has x/y, and nothing
  in the codebase resolves a tile to its owning city yet (`PlayerTimeline#valuation`
  matches by city *name* from event payloads, never by geometry) — the
  plan's claim that this join is "the projection's job, from `city_snapshot`
  the way `PlayerTimeline#valuation` already does it" doesn't hold; that
  method never touches x/y. Building a nearest-owned-city lookup
  (`HexGrid#distance` against a civ's `city_founded`/`city_captured` plots)
  is a real option for later if a report actually wants the city. `city` is
  populated today only for `:killed`/`:disbanded`, straight from
  `unit_lost`'s own `city` field (present on 489 of 1041 rows in
  india-diplo; nil otherwise).
- **Birth and fate are two separate methods, not merged rows.** The plan's
  "Shape" line specs only `{turn, great_person, fate, action, city,
  killed_by}` — no birth field — and the log carries no per-unit identity to
  pair a specific birth to a specific fate beyond turn coincidence, which is
  already the least certain part of the targeted-action pairing (see below).
  Layering a second turn-coincidence guess on top felt like more inference
  than the plan asked for, so births and fates stand as two independent
  signals a report can correlate loosely rather than one the code claims to
  have resolved. india-diplo: 98 births across the six civs, none of them
  `UNIT_GREAT_GENERAL`/`UNIT_GREAT_ADMIRAL`-adjacent surprises (2 each, in
  line with a war-heavy log).

Action classification pairs each expend's kind against a same-turn
`improvement_built` filtered to the improvement *that kind* can plant
(`TARGETED_ACTIONS`), which is what resolves the plan's own ambiguous
example cleanly: India turn 122 has three expends (Engineer/Scientist/
Musician) and three improvements finished that turn (Manufactory/Academy/a
third, unrelated one) — kind-filtering pairs Engineer→Manufactory and
Scientist→Academy correctly and leaves Musician untargeted (Musician has no
plantable form at all), with no risk of a false cross-match. The mod's
civ-unique Prophet reskins (`UNIT_DALAILAMA`, `UNIT_MABA`,
`UNIT_FAKEPROPHET`) are classified as prophets on the strength of sitting
alongside `UNIT_PROPHET` in `WarCasualties::CIVILIAN_UNITS` — not confirmed
against the mod's own unit table the way that list itself is.

Not done, left for later: the tile→city lookup above; relabelling a
`:disbanded` fate that's actually an unobserved coup-adjacent death (no such
case in either example log); pairing a specific birth to a specific fate
when the log someday carries per-unit identity.

## Plan: great people in ChronicleSpine and KeyMomentDetector (implemented)

Status: **Implemented 2026-09-12.** Raised by the user after the section
above shipped, with a specific shape in mind: who started producing a kind
earliest, who produced the most of it, how it was used (infrastructure vs.
consumption), and losses — generals especially. The first and the last have
a turn to anchor on and became `KeyMomentDetector` moments; volume and the
infrastructure/consumption split have no turn and went into the digest
directly instead.

`KeyMomentDetector#great_people_first_of_kind` mirrors `era_leads` exactly —
grouped straight off `unit_created`, not through a per-civ roster join —
and reports the earliest civ (ties included) to produce each kind.
`ChronicleSpine::WEIGHTS[:great_person_first_of_kind] = 1` keeps it as light
texture that only ever joins a nearby entry, the same tier as `wonder_race`.
`KeyMomentDetector#great_people_lost` reads the `:killed` fate `PlayerTimeline#great_people`
already classifies (an expended or disbanded great person is not a loss to
weigh) and carries `kind`. `ChronicleSpine::GREAT_PERSON_LOST_WEIGHTS` gives
a general `ANCHOR_WEIGHT` (3) — a battle loss and a spent investment at
once — and every other kind `1`, level with `spy_killed`. Verified on
india-diplo: nine `great_person_first_of_kind` moments (one per kind, turns
61–151) and the same single Iroquois `UNIT_PROPHET` kill the section above
already found, correctly at weight 1 (a prophet, not a general).

`DigestBuilder#great_people_profile(civ)` carries `by_kind` (expend counts)
and an `infrastructure`/`consumption` split, each further split `early`/`late`
at a boundary — the piece that took two iterations to land right. The first
attempt reused `EarlyGame#end_turn` (Education/Metal Casting), on the
reasoning the user gave directly: infrastructure pays out over the turns
left in the game, so it matters when in the game it was planted. That
reasoning is right but the reference was wrong — checked against
india-diplo before it shipped: every civ's early-game boundary sits at
turn 81–100, while expends run turns 61–183, so all but three of ~130
expends across the roster would have landed in "late" regardless of when
they actually happened. A great person is the product of policies and
culture that arrive well past the opening, so the opening's own boundary
carries no signal here. The fix, chosen over dropping the split entirely:
the midpoint of the game's own last logged turn, computed once per game
(not per civ — every civ shares the same clock, the reason buffer-city
keeps its own window shared rather than per-civ). Self-scales across game
speeds and games that end early via a victory condition, at the cost of
being a flat 50/50 split with no calibration behind it yet — a first
hypothesis, per docs/plan.md's usual practice for an unchecked threshold.
On india-diplo (midpoint turn 92) the split reads `India: infrastructure
{early: 2, late: 8}, consumption {early: 2, late: 27}` down to `Zimbabwe:
infrastructure {early: 0, late: 1}, consumption {early: 0, late: 7}` — still
late-heavy across the board, which matches the same fact that broke the
first attempt (great people arrive late), just no longer swamping the
signal entirely.

## Plan: great people — appearance, use, and death (original plan text)

`PlayerTimeline#great_people`
previously read only `great_person_expended` and returned `{turn, great_person}`,
surfaced in the digest as `great_people:`. It showed a bare list of "civ
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

## Plan: diplomatic ties (implemented)

Status: **Implemented 2026-09-11.** `docs/reading-the-new-log.md` §6 as
written, plus a correction found by inspecting the real output: a span
open when war is declared between the same pair is cut to the declaration
turn, never to whatever turn its own close event happens to log.

`DiplomaticTies` (`app/projections/diplomatic_ties.rb`) reads the five
tie types the log records as fact - embassy, open borders, friendship,
defensive pact, trade agreement - and pairs each type's own open/close
events into spans. `friendship_*` fires once per pair as a `civs` array;
the other four fire once per side, both directions the same turn, and
matching by the unordered pair rather than direction collapses the
mirrored record into the one span it is instead of two.

India's embassy with the Iroquois (open since turn 86) is still standing
when India declares war on them turn 144, and the pair's own
`embassy_ended` does not fire until 145 - the engine's bookkeeping
catching up, not a second turn of real diplomatic contact, since
declaring war cancels every standing agreement with the target
immediately. `spans_for` checks every open span against `war_declared`
records naming that exact pair and cuts `to_turn` to the earliest such
declaration inside it, ahead of whatever the type's own close event says.
`defensive_pact` and `trade_agreement` never fire in any of the five
example logs and ship exercised only by hand-built fixtures.

`PlayerTimeline#wars` gains `ties_at_declaration` - the join the plan
named by hand, needing no new data since a war record already carries its
opponents: `DiplomaticTies#spans(civ, opponent)` filtered to what stood on
`turn_declared`. The one exercised instance in either example log is the
India-Iroquois pair above. `DigestBuilder#diplomatic_ties` adds one entry
per roster pair that ever held a tie, omitting the rest rather than
listing them empty, and reaches the chronicle digest for free through
`ChronicleDigest` wrapping `DigestBuilder#call`. `analyze_game.md` gains
the digest paragraph and corrects a buffer-city paragraph that claimed
`war_declared`/`peace_made` were the only diplomatic events logged - no
longer true, though a logged tie still cannot confirm or rule out the
unspoken settling agreement between neighbours that paragraph is actually
about.

Raised by the user after the first pass shipped: `chronicle_game.md` had
no mention of ties at all, the same gap espionage once had there. Since a
war already anchors its own entry, a tie broken by one needs no spine
wiring of its own - `chronicle_game.md` gained a short section instructing
the chronicler to fold both a standing tie and a `ties_at_declaration`
clause into a passage that already exists, never a scene of its own.

## Plan: first contact between majors (implemented)

Status: **Implemented 2026-09-11.** Raised by the user while discussing
diplomatic ties: `teams_met` (`team_a`/`team_a_civs`, `team_b`/
`team_b_civs`, `turn`) is imported (`ImportGame::KNOWN_EVENT_TYPES`) and
read by nothing - not even named in `docs/reading-the-new-log.md`'s survey
of unread fields, an omission in that pass rather than a deliberate
exclusion. In india-diplo it fires 88 times, 15 of them between a pair of
majors (one per `C(6,2)` pair, as the rule demands) and the rest first
contact with a city-state - scoped to majors only, on the
`CapitalProximity` precedent that a city-state "plays no part in the game
these distances describe."

`CapitalProximity#distances` gains `met_turn` per pair, read from
`teams_met` cross-joining each side's `*_civs` against the other's
(defensive against a log where a team carries more than one civ, though
none of the five example logs exercises that branch) and taking the
earliest turn for a pair matched from either side. `distance` is geometry
fixed at founding; `met_turn` is exploration, and india-diplo shows them
disagreeing in both directions: Tibet-India sit 18 hexes apart, the 8th
closest of 15 pairs, and do not meet until turn 64 - far later than every
other pair within ten hexes of that rank; England-India sit 21 apart,
solidly mid-table, and meet turn 10, the second-earliest contact in the
game. Neither the table (`docs/plan.md`) nor `analyze_game.md` invents a
terrain explanation for either - the digest carries no terrain at all -
but both are named as the kind of mismatch worth a sentence.

`analyze_game.md` gains the `met_turn` paragraph beside the existing
`distance`/`bearing` one. `chronicle_game.md` folds it into the
diplomatic-ties section already added for feature 6, as the natural
opening line for a passage about a pair rather than a moment of its own -
no `ChronicleSpine` weight, the same as `distance` and `bearing` carry
none. Not built: a UI column. `games#show`'s capital-distances table
shows only civs and hex count today, bearing included nowhere on the
page, so `met_turn` stays digest/chronicle-only rather than breaking that
precedent unasked.

## Plan: trade routes (implemented)

Status: **Implemented 2026-09-11.** `docs/reading-the-new-log.md` §7 as
written, with one number corrected against the real log - see that
section's status note.

`TradeRoutes` (`app/projections/trade_routes.rb`) reads
`trade_route_established`/`trade_route_ended`. A route carries no id, so
its lifetime is reconstructed by pairing each establishment with the next
end sharing its `(civ, from_city, to_city, to_civ)` key, chronologically,
one end consumed per start - a greedy match the spec already names as
sometimes wrong, since a re-established pair can steal another instance's
end. The reconstruction never trusts a matched end past the route's own
`turns_left` estimate: live-until is `min(matched_end, turn + turns_left)`,
and `#concurrency(civ)` emits a point at every turn a route starts or
stops being live, each one flagged where any contributing route fell back
to the estimate rather than a trusted match.

`#by_destination(civ)` splits established routes into `own` (food or
production, grouped by type), `city_state` and `major`, reading
`Game#city_state_civs` rather than re-deriving the roster split.
`#one_sided` is whole-game rather than per-civ: every established
major-to-major route where one side's `gold`/`science`/`tourism` is zero
and the other's is not - the shipped example is Delhi feeding Amsterdam
13 science a turn for nothing back, which reproduces exactly against
india-diplo.

`DigestBuilder#trade_routes` degrades to
`{ applicable: false, reason: :no_trade_route_events }` on a log with
none, otherwise carries `by_civ.<civ>.{by_destination, concurrency}` (the
last downsampled through `sample_checkpoints`, the same ~25-turn grid
every other per-turn series uses) and a whole-game `one_sided` list.
`analyze_game.md` gains the digest paragraph; `chronicle_game.md` gains a
short section treating the destination split as characterisation, a
one-sided route as a clause worth naming outright, and the concurrency
curve as backdrop the chronicler mostly leaves unnarrated - the same
texture-not-entry treatment feature 6 established for diplomatic ties.

## Plan: yield attribution (implemented)

Status: **Implemented 2026-09-11.** `docs/reading-the-new-log.md` §9 as
written, two TDD cycles (the projection, then the digest section).

`YieldAttribution` (`app/projections/yield_attribution.rb`) reads
`snapshot.yield_sources`, the one field carrying the mechanism rather
than just the curve, and which nothing read before this. `series(civ,
yield_name)` returns `{turn, total, sources, shortfall}` per turn;
`shortfall` is `total` minus the sum of the named parts, never folded
into `cities` or hidden behind a normalised percentage, per the doc's own
rule. `applicable?` is false when a log predates the field entirely -
`babylon-domination` and `chile-vs-vietnam` both do.

Checked against the real log rather than assumed: `india-diplo`'s
Netherlands at turn 25 reports `culture: 7` against a `sources: {cities:
6}` - a golden age's flat bonus, unattributed to any source - giving
`shortfall: 1`, which the projection reproduces exactly. The vocabulary
disagreement the doc flagged is real too: `science` calls the same
city-state contribution `city_states`, `culture`/`faith` call it
`minor_civs`; this version passes both through unnormalised rather than
unifying them, a follow-up if it turns out to matter in practice.

`DigestBuilder#yield_attribution` degrades to `{applicable: false,
reason: :no_yield_sources}` on an old log, otherwise
`by_civ.<civ>.<yield>` at ~25-turn checkpoints, the same grid
`trade_routes`/`victory_progress` sample at - listing only the yields a
civilization actually has source data for, not all four unconditionally.
`YieldAttribution` joins `DigestBuilderCostTest::PROJECTIONS`.
`analyze_game.md` gains the digest paragraph: what `shortfall` means, the
`city_states`/`minor_civs` naming split, and a pointer to cross-reference
`sources.city_states`/`minor_civs` against
`city_states.by_civ.<civ>.attribution` as the second, independent check
on feature 5's residual the doc called for.

Not done, left for later: `chronicle_game.md` - the feature is
attribution for analysis, not narrative texture, and the design doc named
no chronicle role for it, unlike trade routes' concurrency curve; the
`city_states`/`minor_civs` vocabulary unification; and an end-to-end
`bin/civ analyze` A/B, which is pending the way several tranche 2 and 3
features' A/Bs already are.

## Plan: research beelines (implemented)

Status: **Implemented 2026-09-12.** `docs/reading-the-new-log.md` §8, all
three "settle before implementing" points resolved against
`examples/india-diplo.jsonl` rather than left as assumptions -
`docs/research-beelines.md` records the reasoning.

`ResearchBeelines` (`app/projections/research_beelines.rb`) hardcodes the
eleven marker technologies as `MARKERS` (`marker`, `tech`, `band`), each
resolved against a checkout of the LEKMOD mod source rather than guessed -
confirming `TECH_PLASTIC` not `TECH_PLASTICS`, and that `TECH_STEALTH`
exists in the ruleset even though india-diplo's 184 turns never reach it.
`#markers_reached(civ)` reports every marker a civ ever hit, not just the
first, each carrying `tech_count`, `band`, a signed `distance_to_band`
(zero inside the band, negative early, positive late) and `rush`
(`distance_to_band.zero?`) - a near-miss stays visible data instead of an
invented tolerance threshold.

The doc's first open question - `tech_researched` plus `tech_from_ruins`
disagreeing with `snapshot.techs` by one or two - resolved to a bug, not a
close call: `tech_from_ruins` fires *alongside* `tech_researched` for a
tech a civ already got that way (England's Mining at turn 9), so treating
it as a second acquisition double-counts. The tech count basis is
`tech_researched` events alone, up to and including the marker turn,
restricted to civs present in that event's `civs` array - which
reproduces the doc's validated numbers exactly (India Education #18 turn
74, England Navigation #27 turn 118) where the additive count did not.
`snapshot.techs` on the marker turn is still carried alongside as
`snapshot_tech_count`, via `MetricSeries`, for comparison - never as the
band's basis.

The second question - city-states appearing in `tech_researched.civs` -
is handled at the roster layer rather than inside the projection:
`KeyMomentDetector#research_rushes` loops `game.players.pluck(:civ)`,
matching how `TradeRoutes`/`YieldAttribution` take an explicit civ
argument and stay safe by construction. `research_rushes` emits a
`:research_marker_reached` moment per marker a player civ reached,
sorted by turn, and joins `DigestBuilder#key_moments` under
`research_rushes` - no dedicated top-level digest key, the same
key-moments-only treatment as `wonder_races_lost`/`capital_control_changes`.

The third question - resolving the marker ids rather than guessing -
added `LekmodIdsExtractor#technologies` and `script/extract_lekmod_technologies`,
following the `#buildings` precedent exactly: the `<Technologies>` table
sits unmodified inside `Override/CIV5Units.xml`, not a file named for it,
the same misfiled-table trap already documented for Resolutions and
Buildings. `db/lekmod/35.3/technologies.yml` exists for that audit trail;
`ResearchBeelines::MARKERS` itself stays hardcoded, matching
`KeyMomentDetector::BRANCH_POLICIES` rather than adding a new
runtime-reading service for a table this small.

`ResearchBeelines` joins `DigestBuilderCostTest::PROJECTIONS`.
`analyze_game.md` gains a `research_marker_reached` paragraph beside
`yield_attribution`'s. Not done: `chronicle_game.md` - the doc names no
narrative role for this feature, and tranche 3's own discipline ("specified
more lightly on purpose... re-measured against a second real log before
it is designed in full") argues against inventing one unasked.

## Plan: strategic resource shortages — combat penalty (implemented)

Status: **Implemented 2026-09-12.** Two TDD cycles (the data extraction,
then the projection and its digest section), re-verified against the real
mod checkout rather than the citations below alone.

Context: a player who runs a strategic resource (horse, iron, coal, oil,
aluminum...) below zero doesn't just lose the ability to build more units
that need it — every unit it already owns that needs that resource fights
weaker. Checked against the rule rather than assumed, since every other
feature in this file is:

- `CvUnit::GetStrategicResourceCombatPenalty()`
  (`LEKMOD_DLL/CvGameCoreDLL_Expansion2/CvUnit.cpp:12631`) loops every
  resource; for one the unit requires
  (`m_pUnitInfo->GetResourceQuantityRequirement(eResource) > 0`) and the
  owner is short of (`getNumResourceAvailable(eResource) < 0`), it adds
  `floor((iMissing / iUsed) * STRATEGIC_RESOURCE_EXHAUSTED_PENALTY())` —
  `iMissing = iUsed - iTotal` — then clamps the **combined** total at
  `STRATEGIC_RESOURCE_EXHAUSTED_PENALTY()`, never worse.
- That constant is **`-50`** in this mod
  (`LEKMOD/Override/CIV5Units.xml:92502`, the same table
  `VERY_UNHAPPY_MAX_COMBAT_PENALTY` sits in). So the penalty scales with
  how deep the deficit runs — a resource short by its full requirement
  (deficit fraction 1.0) costs the full −50% combat strength — and needing
  two resources at once is never worse than −50% total, not additive
  beyond that floor.
- The requirement side — which `UNIT_*` needs which `RESOURCE_*` and how
  many — is `Unit_ResourceQuantityRequirements` in
  `LEKMOD/Override/CIV5Units.xml:262725` (`UnitType`, `ResourceType`,
  `Cost`). Same table shape as `Building_ResourceQuantityRequirements`,
  which tranche 1's `buildings.yml` pass already has a pattern for.

What's already logged, checked against the real example files rather than
assumed: `snapshot.resources[]` carries `total`/`used`/`import`/`export`
per resource per civ per turn (table in `docs/reading-the-new-log.md`,
"read by nothing"). Scanning all five example logs for
`total < used` (the deficit `getNumResourceAvailable` tests):

| log | snapshots with a `resources[]` list | deficit rows |
|---|---|---|
| babylon-domination | 0 | — |
| chile-vs-vietnam | 0 | — |
| espionage-test | 619 | 0 |
| **india-diplo** | 1,014 | **7** |
| run-b-test | 104 | 0 |

The seven are two real cases: **Netherlands ran `RESOURCE_HORSE` at
`total: 0, used: 1` for six straight turns, 81–86** — a deficit fraction
of 1.0, which by the formula above is a flat −50% on any horse-requiring
unit it owned over that span. The DLL formula would apply this the moment
the deficit exists, per-turn, not just at a threshold crossing. The
seventh, Iroquois `RESOURCE_COCONUT` at turn 153 (`total: -1, used: 0`),
is a **luxury**, not strategic — no unit has a
`ResourceQuantityRequirement` on it, so `GetStrategicResourceCombatPenalty`
never reaches it regardless of the negative total; worth naming so the
projection doesn't mistake every negative `total` for a combat-relevant
one.

**Resolved during implementation:** re-running `ResourceShortages` directly
against `india-diplo` (not just re-scanning `snapshot.resources[]`) shows
Netherlands had `UNIT_CHARIOT_ARCHER` in the field for the whole six-turn
Horse deficit, turns 81–86 — the exposed unit this doc's first pass could
not confirm.

One correction against the citations above, caught by checking the real
mod checkout rather than trusting a plan doc's own citation: `ResourceUsage`
is an **integer** column (`LEKMOD/Override/CIV5Units.xml:192705`), not a
string enum. `RESOURCEUSAGE_BONUS` / `_STRATEGIC` / `_LUXURY` are `0` / `1`
/ `2` in that order
(`LEKMOD_DLL/.../CvGameCoreDLLUtil/include/CvEnums.h:1194`) — verified
against real rows: Horse/Iron/Coal/Oil/Aluminum/Uranium all carry `1`, every
luxury carries `2`. `Unit_ResourceQuantityRequirements`'s `UnitType`/
`ResourceType`/`Cost` shape was exactly as cited.

`LekmodIdsExtractor#resource_usages` and `#unit_resource_requirements`
(`app/services/lekmod_ids_extractor.rb`) extract the two tables;
`script/extract_lekmod_resource_usages` and
`script/extract_lekmod_unit_resource_requirements` write
`db/lekmod/<version>/resource_usages.yml` and
`unit_resource_requirements.yml`, generated for 35.3 against the real
checkout (57 resources, 6 of them strategic; 65 units with a requirement).
`ResourceRequirements` (`app/services/resource_requirements.rb`) resolves a
game's version against them the same loose way `Wonders` resolves
`buildings.yml`.

`ResourceShortages` (`app/projections/resource_shortages.rb`) reports,
per `(civ, turn)`, every strategic resource where `total < used`, the
deficit fraction, the derived penalty (`floor(deficit_fraction * -50)`),
and `exposed_units` — the civ's own units still in the field that turn
(via `unit_created`/`unit_lost`) that actually require the short resource.
`applicable?` is false when a log predates `resources[]` entirely
(`babylon-domination`, `chile-vs-vietnam`). Labelled throughout — the
projection's own comment, the digest paragraph, `analyze_game.md` — as a
**computed mechanical fact, never an observed one**: no event logs a
unit's actual combat strength, so this never claims a fight was lost to
it, only that a unit was exposed. `ResourceShortages` joins
`DigestBuilderCostTest::PROJECTIONS`; `DigestBuilder#resource_shortages`
degrades to `{applicable: false, reason: :no_resource_data}` on an old log,
otherwise `by_civ.<civ>` lists every deficit in full (no checkpoint
sampling — deficits are rare and short-lived per the survey above, not a
per-turn-per-city section the digest budget needs guarding against).
`analyze_game.md` gains the digest paragraph, including the
"say exposed, never say it lost" rule.

Not done, left for later — the same discipline
`docs/reading-the-new-log.md`'s tranche 3 preamble asks of research
beelines, yield attribution, religion and deal reconstruction, specified
lightly on purpose and re-measured before being designed in full: a
`KeyMomentDetector` moment for entering/leaving a deficit (one six-turn
Horse dip in one game is not enough to calibrate a weight); the DLL's
per-unit combined-penalty summation across more than one simultaneously
short resource (unobserved in any example log so far — every case found
was a single resource); and `chronicle_game.md` (no narrative role named
for this feature, matching research beelines' own omission).

## Plan: deal reconstruction (implemented)

Status: **Implemented 2026-09-12.** `docs/reading-the-new-log.md` §11, with
two corrections found re-measuring against three logs that carry
`resources[]` (india-diplo, espionage-test, run-b-test) rather than just
the one the doc was written against.

`CvDeal` is unreachable from Lua, so no event names a gold trade, a
gold-per-turn trade or a city trade — none of it is ever visible. What is:
`snapshot.resources[]`, each civ's own import/export of a resource per
turn, and the only usable signal is two civs' flows lining up on the same
turn. The doc's own rule bolds "a **luxury** appearing in one import and
another's export is a deal" — measured against the real logs, roughly a
quarter of matched flows are strategic resources, not luxuries (Netherlands
ran Horse for Wine with Tibet for over a hundred turns in india-diplo), so
the restriction is dropped: either kind of resource counts.

The second correction is one the doc doesn't anticipate at all: one
exporter can serve two importers of the same resource at once, and the
split can't be recovered from a stock total. Netherlands fed both
Zimbabwe (3/turn) and Tibet (4/turn) Horse simultaneously for a long
stretch in india-diplo — the real trigger for this. `Deals#matches`
reports nothing for a turn where more than one civ exports or more than
one imports the same resource, rather than guess a pairing; it confirms
only turns with exactly one of each, collapsed into `{resource, exporter,
importer, from_turn, to_turn}` spans across consecutive turns.

`Deals#unattributed_imports` (`app/projections/deals.rb`) lists `{civ,
resource, turn, amount}` for every import with no major exporting that
resource the same turn — city-states never appear in `resources[]` at
all (confirmed against the log: zero snapshot rows for any of india-diplo's
eleven city-states), so this is very likely an ally's gift. Not certain,
though: the same shape appears for exactly one turn at the start of a real
major-to-major swap when one side's snapshot updates a turn ahead of the
other's — the india-diplo Netherlands/Tibet Wine swap does this on its own
first turn. `matches` picking up the same civ and resource the very next
turn is the tell that separates a lagging swap from an actual gift; the
doc, the digest paragraph and both prompts say so rather than guessing.

`applicable?` is false on a log with no `resources[]` at all
(`babylon-domination`, `chile-vs-vietnam`), the same predicate
`ResourceShortages` uses. `Deals` joins
`DigestBuilderCostTest::PROJECTIONS`; `DigestBuilder#deals` degrades to
`{applicable: false, reason: :no_resource_data}`, otherwise carries
`matches` and `unattributed_imports` as whole-game lists, uncheckpointed —
the same rule `trade_routes.one_sided` and `espionage`'s tenures and coups
already follow, since neither is a per-turn-per-civ series the digest
budget needs guarding against.

`analyze_game.md` gains the digest paragraph, including the "reconstructed,
not observed" framing and the lagging-swap-vs-gift tell.
`chronicle_game.md` gains a "Deals, as texture, not an entry" section
alongside trade routes and city-state loyalty — a long-running match is a
bond worth a clause where a passage already covers the two civs, and an
unattributed import is treated exactly as city-state loyalty already is,
never a figure, never written as certain when the record itself is not.

Not done, left for later: a `KeyMomentDetector` moment (a deal's start or
end is not currently a moment, unlike a war or a wonder race); and an
end-to-end `bin/civ analyze` A/B, pending the way several tranche 2 and 3
features' A/Bs already are.
