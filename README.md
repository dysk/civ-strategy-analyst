# Civ Strategy Analyst

Analyzes Civilization 5 + LEKMOD game logs (JSONL events from the sibling
`civ-narrative-logger` project) to explain why a strategy won or lost, and to
surface the key turning points of a game. See `docs/plan.md` for the full
design.

## Requirements

- Ruby 4.0.6 (pinned in `.ruby-version` / `mise.toml` — `mise install` picks it
  up automatically if you use [mise](https://mise.jdx.dev/), and `rbenv
  install` picks it up from `.ruby-version` if you use
  [rbenv](https://github.com/rbenv/rbenv))
- PostgreSQL (any recent version; developed against 17)
- An API key for at least one LLM provider if you want to actually run
  `analyze` against a real model (OpenAI and/or Anthropic — see Configuration)

## Setup

```sh
bundle install
bin/rails db:create db:migrate
```

## Configuration

The LLM provider/model is configurable via environment variables, read in
`config/initializers/ruby_llm.rb`:

- `OPENAI_API_KEY`, `ANTHROPIC_API_KEY` — provider credentials (set whichever
  you plan to use)
- `CIV_ANALYST_MODEL` — default model id (falls back to `claude-opus-5`); can
  also be overridden per run with `bin/civ analyze --model ...`

The model list lives in `config/models.json` rather than in the gem, whose
own copy ages with the gem — ids released after it was published are
unknown, and an unknown id loses both the run and the price it would have
been recorded at. Refresh it when a new model appears:

```sh
bin/rails runner 'RubyLLM.models.refresh!; RubyLLM.models.save_to_json(Rails.root.join("config/models.json"))'
```

The file is committed, so its diff shows when prices moved. `bin/rails test`
checks that the default model resolves and carries pricing, which is what
makes `analyses.cost_usd` trustworthy.

An analysis of a full game runs around 55k input tokens today, so it costs
roughly $0.39 on `claude-opus-5` and $0.15 on `claude-sonnet-5` — cheap
enough that the model is chosen on the quality of the report, not the bill.

Without an API key, everything except actually calling an LLM works fine
(import, the projections, the CLI, the UI) — `AnalyzeGame`'s test suite stubs
the LLM client, so `bin/rails test` never needs network access either.

## Running the test suite

```sh
bin/rails test
```

TDD workflow for this project: red tests first, reviewed, then the smallest
implementation that turns them green. See `docs/plan.md` for the iteration
history.

## CLI (`bin/civ`)

The CLI is the primary interface. Each subcommand is a thin wrapper around a
service object (`ImportGame`, `AnalyzeGame`, `Game`).

**Import a game log:**

```sh
bin/civ import path/to/events.jsonl [--name "My Game"]
```

Streams the file line by line, builds the game + player roster from the first
`session_started` event, and deduplicates events that got replayed by a
pitboss restart (see `docs/plan.md` for the exact dedup rule). Prints the
imported/deduped event counts and the roster.

Don't have a `civ-narrative-logger` log of your own yet? `examples/` has real
single-human-player game logs to import and poke around with. Best starting
point is `babylon-domination.jsonl` — a finished domination game, richer in
events than the others:

```sh
bin/civ import examples/babylon-domination.jsonl
```

`chile-vs-vietnam.jsonl` is also there, though it's an in-progress game with
fewer events.

`india-diplo.jsonl` is the largest of the three — six majors, per-city
snapshots, spies and trade routes — and the one to reach for when a projection
needs testing against volume.

### Feed it raw logs

The importer takes whatever the logger wrote, and that is what it should be
given. The logger repo ships `tools/pipeline.sh`, which chains
`reconcile-unit-lost.jq` (annotates each `unit_lost` with a `cause`) and
`filter-major.sh` (drops lines naming no major nation). Both exist to squeeze a
game into an LLM's context window when you hand it the log directly. This app
has no such limit — it imports to Postgres and puts questions to it through
projections — and the prep costs it information it can use:

- `filter-major.sh` removes every unit event owned by a city-state or by the
  barbarians. Measured on one raw log: 5999 lines in, 4514 out, 197
  `unit_created` and 140 `unit_lost` gone. Majors' rosters survive intact, but
  a minor's army can never be counted afterwards.
- `reconcile-unit-lost.jq` labels a captured worker `cause: "killed"`,
  collapsing the capture-versus-kill distinction `WarCasualties` is built on.
  Nothing here reads `cause` at all; what the projections use is the raw
  `killed_by` field, which the script leaves alone.

The jq script does infer one thing the raw log cannot state — that an otherwise
unexplained combat loss was a barbarian kill. That inference belongs in a
projection, where it can be tested and changed, rather than in a filter that
runs before the import.

The three files in `examples/` predate this decision and are pipeline output:
they carry `cause` fields no projection reads. Harmless, but don't take them as
a model for what an import should look like.

**Analyze a game:**

```sh
bin/civ analyze GAME_ID [--winner Chile] [--victory-type domination] [--model gpt-4o-mini]
```

Builds a compact JSON digest of the game (roster, settings, per-civ metric
checkpoints, timelines, detected key moments), sends it to the configured LLM
with the prompt in `app/prompts/analyze_game.md` (see `AnalyzeGame::PROMPT_PATH`),
and saves the result both as an `Analysis` record and as
`reports/<game>-<timestamp>.md`.

`--winner`/`--victory-type` are optional: without them, the outcome is
inferred from the last score snapshot and flagged as "in progress" if the
game hasn't reached its recorded `max_turns` yet — there's no explicit
victory event in the log to confirm a result either way.

**Write a chronicle of a game:**

```sh
bin/civ chronicle GAME_ID [--lang en|pl] [--model claude-opus-5]
```

Retells the game as a historical chronicle rather than an analysis. It sends
the analysis digest plus two things only the chronicle needs — a `calendar`
mapping every turn to its in-game year (`db/civ5_turn_years.csv`, read through
the game's speed) and a `chronicle` spine of the moments worth an entry — to
the prompt in `app/prompts/chronicle_game.md`.

The spine is what sets the pacing: almost every turn of a game carries
something, so entries are anchored on moments heavy enough to be remembered
(wars, cities taken, capitals changing hands, religions founded, an era
reached first), lighter moments only join an entry that already exists, and
stretches with nothing heavy become `quiet_spans` the chronicle jumps over in
a sentence. Each entry also carries the era the most advanced civilization had
reached by then, and the prompt shifts the chronicler's voice era by era —
stone-cut annals early, a newsreel by the modern age.

The chronicle is a piece of writing, not a record of the game, so it is
written to `reports/chronicle-<game>-<timestamp>.md` and nothing is saved to
the database.

**List imported games:**

```sh
bin/civ list
```

Shows each game's id, name, and whether it's been analyzed yet.

## Web UI

```sh
bin/rails server
```

Then visit `http://localhost:3000` for the games list, or a game's page for
its standings, all detected key moments, and the latest analysis report
(rendered from Markdown) if one exists. Read-only skeleton, no charts yet.

## Project structure

- `app/services/` — `ImportGame`, `DigestBuilder`, `AnalyzeGame`, `ChronicleDigest`,
  `ChronicleGame`, `TurnCalendar`, `LlmClient`, `CivCli`
- `app/projections/` — pure, deterministic Ruby classes that read events from
  the DB: `MetricSeries`, `PlayerTimeline`, `KeyMomentDetector`,
  `OutcomeResolver`
- `app/prompts/` — the LLM prompt templates (`analyze_game.md`,
  `chronicle_game.md`); history lives in git log
- `examples/` — sample `civ-narrative-logger` JSONL logs (single human
  player) to import if you don't have a game of your own yet: a finished
  domination game (`babylon-domination.jsonl`) and an in-progress game
  (`chile-vs-vietnam.jsonl`)
- `app/controllers` / `app/views/games/` — the UI skeleton
- `bin/civ` — the CLI entry point
