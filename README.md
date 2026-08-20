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
- `CIV_ANALYST_MODEL` — default model id (falls back to `gpt-4o-mini`); can
  also be overridden per run with `bin/civ analyze --model ...`

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
events than the other example:

```sh
bin/civ import examples/babylon-domination.jsonl
```

`chile-vs-vietnam.jsonl` is also there, though it's an in-progress game with
fewer events.

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

- `app/services/` — `ImportGame`, `DigestBuilder`, `AnalyzeGame`, `CivCli`
- `app/projections/` — pure, deterministic Ruby classes that read events from
  the DB: `MetricSeries`, `PlayerTimeline`, `KeyMomentDetector`,
  `OutcomeResolver`
- `app/prompts/` — the LLM prompt template (`analyze_game.md`); history lives in git log
- `examples/` — sample `civ-narrative-logger` JSONL logs (single human
  player) to import if you don't have a game of your own yet: a finished
  domination game (`babylon-domination.jsonl`) and an in-progress game
  (`chile-vs-vietnam.jsonl`)
- `app/controllers` / `app/views/games/` — the UI skeleton
- `bin/civ` — the CLI entry point
