# Early game boundary per player

Execution plan for one feature. `docs/plan.md` keeps the project-wide
iteration history; this file is the detailed plan for this change alone.

## Context

The analysis currently judges a game as one block. To assess each player's
opening on its own terms, we need a **per-player early game boundary** — the
turn at which a civilization leaves the development phase.

The rule (settled, but expected to change later): early game ends at the
first of these moments.

- **A** — `TECH_EDUCATION` researched **and** at least one `BUILDING_WORKSHOP`
  standing
- **B** — `TECH_METAL_CASTING` researched **and** at least one
  `BUILDING_UNIVERSITY` standing
- **deadline** — turn 150 on standard speed / 100 on quick, if neither A nor B
  happened

The pairing is deliberately crossed. A Workshop requires Metal Casting and a
University requires Education, so either condition amounts to "I hold both
technologies and have built one of the two buildings" — a stricter and more
consistent threshold than pairing each technology with the building it unlocks.

Scope: stages 1–3 (detection, algorithmic analysis + UI, prompt). Stage 4 (a
reference model of an ideal opening) is out of scope; the appendix records
what the logs can and cannot answer, so that decision can be made later on
evidence.

### How the rule behaves on games already imported

All three are `GAMESPEED_QUICK`, so the deadline is turn 100. This verifies
the **mechanics**, not the threshold — see the caveat below.

| Game | Civ | A (Edu+Workshop) | B (MC+Univ) | milestone | early game ends |
|---|---|---|---|---|---|
| #15 Chile vs Vietnam | Chile (human) | 105 | 101 | 101 | 100 (deadline) |
| #15 | Vietnam | 104 | 107 | 104 | 100 (deadline) |
| #15 | Iroquois | — | 122 | 122 | 100 (deadline) |
| #15 | Bolivia | — | — | — | 100 (deadline) |
| #21 ame | **Babylon (human)** | 78 | **77** | **77** | **77 (milestone)** |
| #21 | Arabia | 111 | 116 | 111 | 100 (deadline) |
| #21 | Philippines | 145 | 139 | 139 | 100 (deadline) |
| #21 | Austria | 146 | 149 | 146 | 100 (deadline) |
| #20 Czechia 6p | all (log ends turn 20) | — | — | — | **20 (`:game_end`)** |

**Caveat: this does not calibrate the threshold.** All three games pit one
human on Prince against `HANDICAP_AI_DEFAULT` bots. The spread between 77 and
111/139/146 measures the gap between a human and a bot, not the pace of real
multiplayer. The apparent conclusion — "the deadline fires for most players" —
is an artifact of weak opponents. In a human game the opposite is likely:
everyone lands near 77, the deadline fires rarely, and hitting it becomes the
exceptional signal rather than the rule. Treat 150/100 as a first hypothesis
to revise against the first human-multiplayer log; the rule was always meant
to be changeable.

What the table does establish: the events are present in the data, both
branches of the condition fire, a milestone reached *after* the deadline
occurs (139, 146) and must still be reported even though it did not set the
boundary, and a civilization reaching neither condition occurs for real
(Bolivia). That is why `reason` and `milestone_turn` go into the digest and
the UI alongside `end_turn`.

Game **#20 is a free regression fixture for the `:game_end` branch**: its log
stops at turn 20, so a naive `min(milestone, deadline)` would hand six players
a boundary of 100 — eighty turns past the end of the data.

---

## 1. `GameSpeed` — a turn conversion between game speeds

New file `app/models/game_speed.rb`, a plain value object (not ActiveRecord):

```ruby
class GameSpeed
  FACTORS = { "QUICK" => Rational(2, 3) }.freeze
  STANDARD_FACTOR = 1

  def self.for(game) = new(game.game_speed)

  def initialize(raw)
    @raw = raw.to_s.upcase
  end

  def turns(standard_turns)
    (standard_turns * factor).round
  end

  private

  def factor
    FACTORS.find { |name, _| @raw.include?(name) }&.last || STANDARD_FACTOR
  end
end
```

Substring matching preserves the current behaviour of
`key_moment_detector.rb:454` — `"GAMESPEED_QUICK"`, `"Quick"` and `"QUICK"`
all hit, while `"GAMESPEED_STANDARD"` and `nil` fall through to standard.
Adding Epic or Marathon later is one line in `FACTORS`.

**Rewiring `KeyMomentDetector`** (`app/projections/key_moment_detector.rb`):
drop `EARLY_GAME_GRACE_PERIOD_QUICK` / `_DEFAULT` (lines 5–6), introduce
`EARLY_GAME_GRACE_PERIOD_STANDARD_TURNS = 100`, and have the private
`early_game_grace_period` (lines 453–455) return
`GameSpeed.for(@game).turns(EARLY_GAME_GRACE_PERIOD_STANDARD_TURNS)`.

The numbers come out identical: `(100 * 2/3r).round == 67` on quick, `100` on
standard. The four existing boundary tests
(`test/projections/key_moment_detector_test.rb:84`, `:101`, `:369`, `:384`)
must stay **green without modification** — that is the regression test for
this step. The three filter call sites (lines 40, 150, 171) are untouched.

## 2. `PlayerTimeline#buildings` — extracted from `wonders`

`app/projections/player_timeline.rb:91-98` reads `building_constructed` today
only to filter for wonders. Ordinary buildings (Workshop, University) are
imported but **no projection reads them**. Extract the general method and make
`wonders` a filter over it:

```ruby
def buildings(civ)
  sort_events(
    of_type("building_constructed").select { |e| e.civ == civ }.map do |e|
      { turn: e.turn, building: e.payload["building"], city: e.payload["city"],
        class: e.payload["wonder"]&.to_sym }
    end
  )
end

def wonders(civ)
  buildings(civ).select { |building| building[:class].in?(%i[world national]) }
end
```

`buildings` **does not go into the digest** — that is hundreds of events per
game; it exists to serve `EarlyGame`. `wonders` gains sorting by turn, which
it lacked; check `test/projections/player_timeline_test.rb:101-104`, the
resulting order does not change.

## 3. `EarlyGame` — a new projection

New file `app/projections/early_game.rb`, following `CapitalsTimeline` /
`SpaceshipTimeline`: the constructor takes a `Game`, methods are read-only,
and there is no base class or registry.

```ruby
class EarlyGame
  DEADLINE_STANDARD_TURNS = 150
  MILESTONES = [
    { tech: "TECH_EDUCATION",     building: "BUILDING_WORKSHOP" },
    { tech: "TECH_METAL_CASTING", building: "BUILDING_UNIVERSITY" }
  ].freeze
```

Public interface:

- `deadline_turn` → `GameSpeed.for(@game).turns(DEADLINE_STANDARD_TURNS)`
- `for_civ(civ)` → one hash (shape below)
- `series` → `{ civ => for_civ(civ) }` over `@game.players.order(:id)`

The per-player result:

```ruby
{
  civ: "Babylon",
  end_turn: 77,
  reason: :milestone,          # :milestone | :deadline | :game_end
  milestone_turn: 77,          # always reported, even past the deadline; nil if never reached
  milestone: { tech: "TECH_METAL_CASTING", building: "BUILDING_UNIVERSITY" },
  tech_turn: 64,
  building_turn: 77,
  deadline_turn: 100
}
```

Rules:

- `tech_turn` — the first turn from `PlayerTimeline#techs(civ)` for that
  technology. **Reuse that method**; do not write a fresh query.
  `tech_researched` is team-scoped (the `civ` column is NULL, the owners live
  in `payload["civs"]`) and `techs` already merges it with `tech_from_ruins`
  (`player_timeline.rb:24-34`).
- `building_turn` — the first turn from `PlayerTimeline#buildings(civ)` for
  that building (step 2).
- a milestone's turn is `max(tech_turn, building_turn)`, and `nil` when either
  part is missing.
- `milestone_turn` is the smaller of the non-nil A and B turns; `milestone`
  names which condition produced it (on a tie, A).
- `end_turn` = `min(milestone_turn, deadline_turn)`, with `reason` set to
  `:milestone` or `:deadline` accordingly.
- when the game ended before the deadline and neither condition fired:
  `end_turn` is the game's last turn and `reason` is `:game_end`. We do not
  report a boundary past the end of the data.

One `PlayerTimeline` instance per `EarlyGame`, memoized in the constructor —
do not repeat the pattern in `KeyMomentDetector`, which constructs
`MetricSeries` afresh inside every method.

**`KeyMomentDetector` is deliberately left alone.** The early game boundary is
a player state, not a moment on the timeline, so it does not belong in
`key_moments`, in `KeyMomentsHelper::DESCRIPTIONS`, or in the `<details>`
sections of the UI.

## 4. Digest and UI

**`app/services/digest_builder.rb`:**

- in `#call` (lines 26–39) add a top-level `early_game:` key after
  `standings:`, holding `EarlyGame.new(@game).series`
- in `#game_settings` (lines 48–54) add `early_game_deadline_turn:` — the
  threshold is a property of the game, not of a player, so it is not repeated
  per row. (`deadline_turn` stays in each civ's row regardless: the digest is
  read by an LLM, which benefits from having it locally in context.)

**`app/controllers/games_controller.rb`:**

- in `#show` (lines 11–26) add
  `@early_game_rows = EarlyGame.new(@game).series.values`
- no private builder method — `EarlyGame#series` already returns display-ready
  rows. The `filter_map` pattern from `#victory_progress_rows` (lines 167–178)
  is not needed here: every player has a boundary, the worst case being
  `:game_end`.

**`app/views/games/show.html.erb`:** a new `<h2>Early Game</h2>` section
between "Final Standings" (ends at line 33) and "Capital Distances" (line 35)
— an opening-phase fact, sitting naturally next to capital proximity. Copy the
table pattern from "Victory Progress" (lines 190–213), with
`class="early-game"`:

| Civ | Ends turn | Why | Milestone | Tech | Building |
|---|---|---|---|---|---|
| Babylon | 77 | milestone | METAL_CASTING + UNIVERSITY | 64 | 77 |
| Arabia | 100 | deadline | EDUCATION + WORKSHOP (t. 111) | 96 | 111 |

Empty cells render as `"&mdash;".html_safe`, matching the rest of the file.
The section heading states the threshold: "deadline: turn 100 (quick speed)".
Strip the `TECH_` / `BUILDING_` prefixes in the view for readability. Add
`.early-game` to `app/assets/stylesheets/application.css` alongside the other
table classes.

**No drill-down page** (unlike `empire_geometries`): there is no series over
time to show, and everything fits in one row.

## 5. Prompt v20

`app/prompts/analyze_game.md`. Mind the hard constraint at lines 619–621:
*"exactly these sections, in this order … add no sections beyond these."*
So we **do not add a report section**; we extend an existing one.

Two edits:

1. **`## How to weigh the signals`** (from line 104) — a new paragraph
   teaching the model to read `early_game`: what the boundary means, that it
   is a heuristic computed from the data rather than a judgment, that
   `reason: "milestone"` marks a civilization that left the development phase
   on its own while `reason: "deadline"` marks one whose boundary was set by
   the clock, and that comparing `end_turn` across civilizations measures
   development pace. Add that a `milestone_turn` past the deadline is still a
   signal (139 against 77 is a real difference), and that the thresholds are
   scaled by game speed, so turn numbers from this game are not comparable
   with turn numbers from a game at a different speed. Worth noting: the
   prompt currently carries **no** instruction about `game_speed` at all —
   this paragraph is the first.

2. **`## Per-Player Strategic Verdict`** (lines 629–638) — extend the existing
   description to require that each civilization's verdict contains a
   **separate early game assessment**, restricted to events with
   `turn <= early_game.<civ>.end_turn` and stating that turn explicitly,
   before the verdict on the rest of the game. The assessment must rest on
   what the data shows inside that window (settling pace, technologies, the
   policy tree, happiness, wars, pantheon and religion) and compare
   civilizations against each other by `end_turn`. State explicitly: do not
   invent an assessment when the window is empty, and do not confuse the
   boundary with a judgment of quality.

Record the feature in `docs/plan.md` at the end of the file, following the
`## Plan: domination + science victory progress` pattern: a
`## Plan: per-player early game boundary` section with status, the rule, the
table above, and a note that "Prompt v20 teaches the model to read
`early_game.*` and to judge each civilization's opening separately." That is
this repository's documented pattern for a new analysis feature.

---

## Tests (TDD — red first, reviewed, then the smallest implementation)

Minitest, `bin/rails test`, records built inline in `setup`, test names written
as full sentences starting with the method name.

| File | Coverage |
|---|---|
| `test/models/game_speed_test.rb` (new) | `turns` for QUICK / STANDARD / nil; `turns(100) == 67` and `turns(150) == 100` on quick |
| `test/projections/key_moment_detector_test.rb` | **unchanged** — the 4 existing boundary tests are the regression for step 1 |
| `test/projections/player_timeline_test.rb` | new test for `buildings`: returns ordinary buildings with `class: nil`; existing `wonders` tests stay green |
| `test/projections/early_game_test.rb` (new) | milestone A; milestone B; the earlier of the two wins; a technology without its building does not end it; a building without its technology does not end it; deadline when neither fires; a milestone past the deadline yields `reason: :deadline` with `milestone_turn` preserved; `:game_end` when the game is shorter than the deadline; a technology from `tech_from_ruins` counts the same; a team-scoped technology (`payload["civs"]`) reaches both team members; the deadline scales with game speed |
| `test/services/digest_builder_test.rb` | `early_game` present in the digest, keyed by civ; `early_game_deadline_turn` present under `game` |
| `test/controllers/games_controller_test.rb` | the "Early Game" section renders with turn and reason |

Copy the `event(...)` / `snapshot(...)` helpers from the bottom of
`test/projections/key_moment_detector_test.rb`.

## End-to-end verification

**No re-import is needed.** `ImportGame#persist_event`
(`app/services/import_game.rb:92-102`) stores every line's full `payload`, and
`building_constructed` and `tech_researched` have been in `KNOWN_EVENT_TYPES`
from the start — every event this feature needs is already in the database for
games #15, #20 and #21 (the table above was computed purely from stored
events). The UI recomputes projections live on every request, so the section
appears as soon as the code ships.

```sh
bin/rails test                    # the whole suite, including the 67/100 regression
bin/rails server                  # /games/15, /games/20, /games/21
```

Expected, straight from the table in Context: #21 Babylon `77 / milestone` and
the rest `100 / deadline` with `milestone_turn` 111 / 139 / 146; #15 all four
`100 / deadline` (Bolivia with no `milestone_turn`); **#20 all six
`20 / game_end`** — the only case that will catch a bug in the `:game_end`
branch.

The prompt needs a fresh run: `analyses.digest` is a frozen snapshot, so old
analyses will not gain `early_game` retroactively.

```sh
bin/civ analyze 21
```

Then check that "Per-Player Strategic Verdict" opens each civilization with an
early game assessment quoting its boundary turn. Without an API key, the
prompt as sent is visible at `/games/21/analyses/<n>/prompt`, and the digest
sits in the `analyses.digest` column.

---

## Appendix — stage 4 feasibility (out of scope here)

A review of the ideal-opening checklist against what the data actually holds.
Verified against `examples/*.jsonl` and the logger sources.

### Available today, no changes required

- opening with 2 scouts — `unit_trained` with `UNIT_SCOUT`
- Mining as the first technology — `PlayerTimeline#techs` preserves order
- city count (4–6 Tradition / 6–10 Liberty) — `timelines.<civ>.cities`
- workers per city — `unit_trained` with `UNIT_WORKER` against city count
- closing the opening policy tree — `policy_branch_completions`
- "never go unhappy" — `happiness` in snapshots, `unhappiness_periods`
- National College on turn 50–60 — `BUILDING_NATIONAL_COLLEGE`
- caravans — `unit_trained` with `UNIT_CARAVAN` (route direction: **no**)
- good wonders (Artemis, Great Library, Oracle, Petra, Chichen Itza, Pisa) —
  `wonders`
- cities settled close to the capital (3–5 hexes) — `EmpireGeometry` +
  `HexGrid` (`mean_spacing`)
- libraries in cities below 6 pop, 10–12 pop when universities finish —
  `building_constructed` plus `population_changed` (`new_population` per
  city); needs the two streams joined, but is feasible

### Worker stealing — available today, hypothesis confirmed

A capture is a pair of events in the same turn **on the same hex**:

```
{"event":"unit_lost",   "civ":"Harappa","unit":"UNIT_WORKER","killed_by":"Iroquois","turn":114,"x":24,"y":14}
{"event":"unit_created","civ":"Iroquois","unit":"UNIT_WORKER","city":null,          "turn":114,"x":24,"y":14}
```

Checked against both logs: of 27 worker/settler losses to a major, **26 have
an exact x/y match** in the same turn on the capturer's side. The single
exception (T153, Arabia losing a settler to Babylon) is a kill rather than a
capture — so a missing match is itself a signal, not noise. The `city` field
separates trained from captured as a secondary check: a trained unit carries
its city's name, a captured one carries `null` — unless the capture happened
on a city tile, which is why **x/y equality is the strong criterion and
`city: null` only supporting**.

Note that a city-state's `unit_lost` **already survives
`tools/filter-major.sh`**, because the filter keeps any line naming a major
anywhere, and here the major appears in `killed_by`. Nothing needs unblocking.

One caveat about the signal's value: in both logs the city-state thefts land
on turns 114 and 125 (wartime), and every early capture is from **barbarians**.
The classic turn-15 steal from a city-state simply did not occur in these two
games. The heuristic will be correct, but before treating it as informative we
want to see it on a log where that move actually happened.

### What the city-state filter really removes

`tools/filter-major.sh` is not a blanket filter on city-states — it keeps every
line that names a major, so **city-state-versus-major is already in the logs**
(Harappa, Wittenberg, Troy, Baku, Teheran and Cahokia all appear in
`examples/`). Only lines concerning a minor exclusively are dropped. For
opening analysis that costs one real thing: **the city-state's own
`unit_created` for its worker** (spawning around turn 15), which is what
answers "was there anything to steal, and from when". Recovering it means
loosening the filter with a `unit_created` whitelist for minors — a change to
the pipeline, not to the logger.

### New logger events — what would supply the rest

The architecture helps: `logger.attach` (`src/logger.lua:23-29`) subscribes
**automatically** to every function in `extractors.lua` named in UpperCamelCase,
so a new hook is one function. State that no hook can catch is carried by a
per-turn poller on `PlayerDoTurn` — a pattern that already exists twice
(`src/census.lua`, `src/congress.lua`) — and the adapter already reaches
`g.Players[i]`, `g.Map`, `g.Teams` and `g.GameInfo`.

The key observation: **most of the "impossible" list is not events but state**.
There is nothing to hook; it has to be polled.

| Missing | Mechanism | Cost | Confidence |
|---|---|---|---|
| production focus, manual tile locking | new poller: `pCity:GetFocusType()`, `IsForcedWorkingPlot`, `IsAvoidGrowth` | 1 record/city/turn | API names to verify |
| scientist specialist slots filled | same poller: `pCity:GetSpecialistCount(eSpecialist)` | as above | API names to verify |
| iron in the first circle, buying the hex for it | one-off `city_surroundings` on `PlayerCityFounded`: resources within radius 3 (`pPlot:GetResourceType`) | 1 record/city | high — `plot_bought` already carries x/y and only needs something to join against |
| scouting for city sites | revealed tiles as a `snapshot` metric (an `IsRevealed` count per team) — **not** `UnitSetXY`, which would flood the log with moves | 1 number/player/turn | medium — need to check whether a getter exists or it means looping the map |
| caravan carrying food to the capital | trade route poller: `pPlayer:GetTradeRoutes()` (from/to) | 1 record/player/turn | method name to verify |
| stealing a worker from a city-state | **nothing needed** (above) | — | confirmed |

Unused hooks from `docs/lekmod-gameevents.md`: `UnitSetXY`, `BuildingSold`,
`UnitHealed`, `PlayerHappinessChanged`. The `CityCan*` / `PlayerCan*` family
are decision queries (TestAll/Accumulator), **not** notifications — do not
subscribe to them, as that same document warns.

To verify the Lua method names, use the route that produced
`docs/lekmod-gameevents.md`: grep the LEKMOD DLL sources, this time for method
registrations in `CvLuaCity.cpp` / `CvLuaPlayer.cpp` / `CvLuaPlot.cpp` rather
than for `CallHook`.

### Conclusion

Worker stealing and most of the checklist are reachable **without touching the
logger**. The genuine gaps are city micromanagement (focus, tiles,
specialists), and closing them needs a third poller rather than new hooks.
Honor and Piety openings can be described with the same signal set as
Tradition and Liberty (`policy_branch_adoptions`, `policy_branch_completions`,
war timing, faith).
