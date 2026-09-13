# Ideal opening — feasibility and detection plan

Status: **every per-criterion feasibility row implemented** (2026-09-13) —
`OpeningStrategy` (`app/projections/opening_strategy.rb`) now covers the
full checklist below, see "What's left" for what remains structurally.
This is stage 4 of
`docs/early-game-boundary.md` ("a reference model of an ideal opening"),
deliberately left out of scope there so it could be designed against
evidence once the boundary itself existed. It supersedes that document's
own "Appendix — stage 4 feasibility" on two points: the National College
target turn, and the worker-theft mechanism (see below for both).

## Context

`EarlyGame` (`app/projections/early_game.rb`) answers *when* a civilization
leaves the opening. This document is about *how well* it played that
opening — a checklist of concrete, known-good opening moves, checked
against what the log actually holds.

The checklist, as given:

**General, any opening:**
- open with 2 scouts, unless a specific strategy calls for something else
- first researched technology is Mining, to reveal Iron early, unless a
  specific niche start calls for something else
- steal workers from city-states to save hammers
- close the opening policy tree as soon as possible, unless going for a
  specific niche build
- never go unhappy, or at minimum minimize the number of unhappy turns
- no Library in a city under population 6, unless rushing National College
- aim for population 10 or more in the city finishing University

**Tall (4–6 cities):**
- 2 workers per city
- National College around turn 60 (quick speed) — **superseded below by
  67/100, see "National College timing"**
- caravans feeding food to the capital as early as possible
- good wonder targets: Temple of Artemis, Great Library, Oracle, Petra,
  Chichen Itza, Leaning Tower of Pisa — **superseded below by the
  three-bucket split, see "Good wonder targets"**

**Wide (6–10 cities):**
- 1–1.5 workers per city
- close, even minimum-distance city placement works well
- with Liberty, National College is built after finishing the tree

Tall/wide is a placeholder. The plan is to replace it with four
opening-branch groups — Tradition, Liberty, Honor, Piety — each carrying
its own version of these thresholds. Everything below is designed so that
swap is cheap: no rule here is wired to "tall" or "wide" as a hardcoded
label.

## Classifying the opening without asking for it

None of these rules can fire correctly without knowing which opening a
civilization is actually running — a blanket "2 scouts always" is wrong
for a civ that isn't doing a scout-heavy opening on purpose. The checklist
already says as much: half its rules carry an "unless a specific strategy"
clause.

There's no `Player#strategy` field, and there doesn't need to be one. The
opening is already legible from data: `PlayerTimeline#policies(civ)`'s
first `:branch_adopted` entry is the branch a civ opened into — the same
join point Tradition/Liberty/Honor/Piety classification will use later.

**Implemented**: `OpeningStrategy` (`app/projections/opening_strategy.rb`)
wraps that lookup. `#branch(civ)` returns the opening branch;
`#closed_opening(civ)` adds `opened_turn`, the branch's finisher policy id
(derived from the branch name, e.g. `POLICY_BRANCH_TRADITION` →
`POLICY_TRADITION_FINISHER`, rather than a hardcoded per-branch table —
this also covers Liberty, whose finisher id is missing from
`db/lekmod/34.15/ids.yml` even though 35.3 has it; ids.yml carries display
names, not whether the event was logged), `finished_turn`, and
`turns_to_close`. This is the first per-criterion feasibility row
implemented ("Close the opening policy tree as soon as possible"), and the
join every later per-branch threshold table will use.

Still to express every threshold below as a table keyed by branch (tall
and wide becoming two rows of it, not a separate code path) rather than a
single universal rule with an unstated exception. A rule that fires
against the wrong branch's expectation is then a real finding — "opened
Liberty but never used a caravan" — not a false positive against an
undeclared plan.

## Per-criterion feasibility

Everything below reads from `game.event_log` and existing projections.
None of it requires a change to `civ-narrative-logger`.

| Criterion | Data source | Detection |
|---|---|---|
| Open with 2 scouts | `unit_trained` + `building_constructed`, merged by turn | grade the first 4 things built by how many, and which, are scouts (`WarCasualties::SCOUT_UNITS`) — see "Open with 2 scouts" below |
| First tech is Mining | `PlayerTimeline#techs(civ)` | first entry's `tech == "TECH_MINING"` |
| Close the opening tree fast | `policy_adopted` where `policy` matches `POLICY_*_FINISHER` (confirmed ids in `db/lekmod/34.15/ids.yml`, e.g. `POLICY_TRADITION_FINISHER`, `POLICY_LIBERTY_FINISHER`) | finisher turn minus the branch's `policy_branch_adopted` turn |
| Never/minimize unhappy turns | `snapshot.happiness` (empire `GetExcessHappiness()`), via `MetricSeries#values("happiness", civ)` | count turns with `happiness < 0` inside the early-game window |
| No Library under population 6 | `building_constructed` (`BUILDING_LIBRARY`) + `CityCensus#snapshot(civ, turn)` | flag when that city's population at the build turn is below 6 |
| University at population 10 or more | `building_constructed` (`BUILDING_UNIVERSITY`, plus `EarlyGame::REPLACED_BY`-style civ variants) + `CityCensus` | population of the building city at the build turn |
| City count (tall 4–6 / wide 6–10) | `city_founded`/`city_captured`/`city_lost` | straightforward count over time — implemented as `OpeningStrategy#playstyle`, see "Classifying the opening" |
| Workers per city | `OrderOfBattle`'s `unit_created`/`unit_lost` ledger for `UNIT_WORKER`, ÷ city count at that turn | empire-wide ratio only (see "Known gaps") — implemented as `OpeningStrategy#workers_per_city` |
| Caravans feeding the capital | `trade_route_established`, `type == "food"`, `to_city == capital` | already close to what `TradeRoutes#by_destination` computes (own routes by type) |
| Good wonders | `building_constructed` where `wonder == "world"` | implemented as `OpeningStrategy#good_wonders`, see "Good wonder targets" |
| Wide: close city spacing | `EmpireGeometry#series(civ)` | already computed — each entry's `mean_spacing` is the empire-wide average distance from a city to its nearest neighbour, via the same `HexGrid` distance `CapitalProximity` uses |
| National College timing | `building_constructed` (`BUILDING_NATIONAL_COLLEGE` + civ-unique variants, e.g. `BUILDING_ISRAEL_NATIONAL_COLLEGE`) | see below |

## Worker theft — two independent paths

The mod requires a declaration of war on the city-state before its worker
can be captured — this corrects the older appendix, whose two-log corpus
never happened to exercise an unprovoked steal, so the war precondition
never showed up in the data it was checked against. There is a second,
independent path via bullying that needs no war at all.

### Path A — raid and capture

Sequence: `war_declared` naming the city-state as defender, then
`unit_lost` for that city-state with `unit == "UNIT_WORKER"` and
`killed_by` set to the attacking civ, inside the war's turn window.

`killed_by` on `unit_lost` is populated by the DLL only when a unit
changed hands rather than dying in combat — confirmed by
`civ-narrative-logger/tools/reconcile-unit-lost.jq`'s own header comment,
itself evidence-based against real hook data. `WarCasualties`
(`app/projections/war_casualties.rb`) already treats exactly this as a
capture for any unit in its `CIVILIAN_UNITS` list, which includes
`UNIT_WORKER` (line 31).

This can be read directly off `WarCasualties#first_blood(war)` and
`#scale(war)` rather than re-implemented: a war whose `scale` comes back
`:raid` (no soldier casualties exchanged) and whose `first_blood` names a
captured `UNIT_WORKER` is exactly a declare-war-grab-worker-make-peace
raid, distinct from a real war against that city-state.

```ruby
def worker_raids(civ)
  casualties = WarCasualties.for(@game)

  PlayerTimeline.for(@game).wars(civ).select { |war| war[:role] == :attacker }.filter_map do |war|
    city_state = war[:opponents].first
    next unless @game.city_state_civs.include?(city_state)

    fb = casualties.first_blood(war)
    next unless fb && fb[:unit] == "UNIT_WORKER" && fb[:fate] == :captured

    { city_state: city_state, declared_turn: war[:turn_declared],
      captured_turn: fb[:turn], peace_turn: war[:turn_peace] }
  end
end
```

`war[:turn_peace] - war[:turn_declared]` also feeds the "minimize unhappy
turns" criterion for free — a war against a city-state, however brief,
still costs happiness while it lasts.

### Path B — bullying

No war needed, but requires enough military presence near the city-state
to bully in the first place — realistically rare this early unless the
opening leans Honor. The mod's bully penalties are fixed: **-15 influence
for bullying gold, -50 for bullying a unit.** `city_state_friendship_changed`
(`player_timeline.rb:131-135`) already carries `old_friendship`/
`new_friendship` on every change, so the penalty is a plain delta check —
no median/outlier calibration needed, unlike `WonderRaces`' acceleration
detection, because the two constants are exact.

```ruby
BULLY_PENALTY = { gold: -15, worker: -50 }.freeze
TOLERANCE = 3

def bullied_workers(civ)
  @log.of_type("city_state_friendship_changed").select { |e| e.civ == civ }.filter_map do |e|
    delta = e.payload["new_friendship"] - e.payload["old_friendship"]
    next unless (delta - BULLY_PENALTY[:worker]).abs <= TOLERANCE

    { turn: e.turn, city_state: e.civ, delta: delta }
  end
end
```

Corroborate with a same/adjacent-turn `unit_created` (`UNIT_WORKER`) for
the civ as a secondary check — cheap, and guards against a rare civ/policy
modifier shifting the penalty by more than `TOLERANCE`.

## National College timing

Target: **turn 67 on quick speed, turn 100 on standard speed.** This is
not two separate constants — `GameSpeed#turns` (`app/models/game_speed.rb`)
already converts a standard-speed turn count with the same `2/3` factor
`EarlyGame::DEADLINE_STANDARD_TURNS` uses, and `(100 * 2/3r).round == 67`
exactly. So the target is `GameSpeed.for(@game).turns(100)`, reusing the
existing helper rather than hardcoding per-speed numbers. This replaces
the older appendix's unsourced "turn 50–60" estimate.

Building lookup follows `EarlyGame::REPLACED_BY`'s pattern: match
`BUILDING_NATIONAL_COLLEGE` plus any civ-unique replacement (e.g.
`BUILDING_ISRAEL_NATIONAL_COLLEGE`, confirmed in
`db/lekmod/35.3/buildings.yml`).

For a Liberty opening, the checklist's own rule changes the comparison:
National College is expected only after the tree closes, so the
meaningful measurement there is turns-after-finisher, not turns-from-game-start.
This is exactly the kind of per-branch threshold the `OpeningStrategy`
classification above exists to carry.

## Known gaps

- **Workers per city** is only ever an empire-wide ratio (`worker count ÷
  city count` at a turn). The game does not log which city a worker is
  assigned to, so no per-city figure is recoverable.
- **A third worker-theft path may exist through `diplo_event`**
  (`UiDiploEvent`), which carries an undecoded numeric `type` enum nowhere
  mapped in this codebase. Not needed for Path B above (the friendship-delta
  signal is sufficient on its own), but worth flagging as a separate,
  currently-opaque event if some other diplomatic narrative ever needs it.

## Suggested next step

Iteration 1 (the finisher-policy turn, via `OpeningStrategy`) is done —
see "Classifying the opening" above and `docs/plan.md`.

**Implemented**: `OpeningStrategy#worker_raids` (Path A above). One
adjustment from the pseudocode: `PlayerTimeline#wars(civ)` hands out a
one-sided `{turn_declared, opponents, role}` shape, not the
`{turn, attacker_civs, defender_civs}` shape `WarCasualties` reads, so
`worker_raids` rebuilds the latter from the civ and its opponents before
calling `first_blood`. Everything else matches the doc: only wars where
the civ is `:attacker`, only where the opponent is in
`game.city_state_civs`, and only where `first_blood` names a captured
`UNIT_WORKER` — a soldier traded first makes it a real war, not a raid.

**Implemented**: `OpeningStrategy#bullied_workers` (Path B above), reading
`PlayerTimeline#city_states` rather than the raw log directly, since it
already parses `city_state_friendship_changed` into the
`{turn, city_state, old_friendship, new_friendship}` shape this needs.
Matches a friendship delta within `TOLERANCE` of the fixed `-50` bully
penalty, then requires a `UNIT_WORKER` `unit_created` for the civ within
one turn as corroboration — the delta band alone can't rule out some
other friendship swing landing in the same range by coincidence.

Both worker-theft paths from the checklist are now implemented.

**Implemented**: `OpeningStrategy#national_college` (National College
timing, above). `BUILDING_ISRAEL_NATIONAL_COLLEGE` is the only civ-unique
replacement found in `db/lekmod/35.3/buildings.yml`. For any opening other
than Liberty it compares the build turn against
`GameSpeed.for(@game).turns(100)` and reports `turns_early`; for Liberty it
instead reports `turns_after_finisher` against `closed_opening(civ)`, nil
until the tree actually closes.

**Implemented**: `OpeningStrategy#first_tech` (first tech is Mining, back
in "General, any opening"). Reads `PlayerTimeline#techs(civ)`, the merged
research-and-ruins list the feasibility table already names, and returns
the earliest entry's tech id, or `nil` if the civ has none logged. A hut
tech ahead of any deliberate research is skipped as a windfall rather than
a choice, except when that hut tech is Mining itself, which satisfies the
checklist's actual goal (revealing Iron early) regardless of how it
arrived.

**Implemented**: `OpeningStrategy#opening_scouts` (open with 2 scouts, back
in "General, any opening"). Grades the civ's first `OPENING_ITEMS_WINDOW`
(4) production outputs — `unit_trained` and `building_constructed`, merged
by turn — by how many of them were scouts: `:opened_with_two_scouts` when
the first two are both scouts, `:two_scouts_interrupted` when a second
scout still lands in the window but not back-to-back (a shrine wedged in
between might mean a deliberate pantheon rush rather than a mistake),
`:one_scout`, or `:no_scouts`. A civ-unique scout replacement counts the
same as `UNIT_SCOUT`, reusing `WarCasualties::SCOUT_UNITS` rather than
duplicating that list. Returns the full first-4 `items` list alongside the
verdict, plus `interrupted_by` — whatever sits between the first two
scouts when the run isn't clean — so a report can name the culprit instead
of just flagging that something interrupted it.

Deliberately left out: the Aztec Jaguar, a warrior replacement sometimes
used as a scout substitute by intent. The log can't distinguish that
intent from an ordinary early Jaguar build, so it isn't counted as a
scout — noted here rather than guessed at in code.

**Implemented**: `OpeningStrategy#city_spacing` (Wide: close city spacing,
above). No new detection — `EmpireGeometry#series(civ)` already computes
`mean_spacing` on every founding or capture. This samples that series at
the same early-game boundary `EarlyGame#for_civ` uses to mark the end of
the opening (`end_turn`), taking the last entry at or before that turn, so
a city founded after the opening already closed doesn't count toward how
the opening was played. Nil-shaped (`turn`/`cities`/`mean_spacing` all
`nil`) for a civ that never founded a city.

**Implemented**: `OpeningStrategy#playstyle` — the tall/wide classification
the structural section above calls for, ahead of the opening-branch groups
it's meant to precede. City count at the early-game boundary
(`city_spacing`'s `cities`) is the primary signal, since it's what the
checklist's own bands (tall 4–6, wide 6–10) actually measure: below 6 is
`:tall`, above 6 is `:wide`. The shared boundary at exactly 6 falls back to
the opening branch, but only for Tradition (`:tall`) and Liberty
(`:wide`) — Honor and Piety are played both ways in this mod, so a tied
count under either stays `nil` rather than guessed at. `mean_spacing` and
`branch` ride along in the result as context; neither feeds the verdict,
since the checklist treats spacing as an effect of playing wide, not a
cause of it, and Honor/Piety's own flexibility rules out branch as a
general-purpose signal beyond that one tie-break.

### Good wonder targets

**Implemented**: `OpeningStrategy#good_wonders`. The checklist's wonder
list is really three buckets, not one:

- **Universal** — Temple of Artemis, Oracle, Great Lighthouse, Colossus.
  The last two are already gated by the game itself: a coastal city is
  required to build them, so a completed one is proof of coastal placement
  on its own, with no separate coastal check needed.
- **Tall** — Great Library, Petra, Chichen Itza, Leaning Tower of Pisa,
  Hanging Gardens.
- **Wide** — Pyramids, Stonehenge.

Which style bucket applies comes from `#playstyle`, not `#branch` directly
— a civ that opened Liberty but only settled 5 cities is graded against
the tall list. An unresolved style (Honor/Piety tied at exactly 6 cities)
grades against the universal bucket only, since neither style list is
known to apply. `#good_wonders(civ)` returns `{ targets:, built: }` —
`targets` is the universal bucket plus whichever style list applies,
`built` is the subset of the civ's actual wonders (via
`PlayerTimeline#wonders`) that land on one of those targets. A wonder
built from the wrong style's list — Stonehenge for a tall civ — is on
neither, and doesn't count.

**Implemented**: `OpeningStrategy#unhappy_turns` (never/minimize unhappy
turns, back in "General, any opening"). Counts `MetricSeries#values("happiness",
civ)` entries that are negative, sampled up to the same early-game boundary
`city_spacing` uses, so a dip after the opening already closed doesn't
count toward how the opening was played. A snapshot's turn stands for the
run since the previous one rather than every unsampled turn in between, so
`count` is a count of unhappy snapshots, not a count of unhappy game
turns. Returns `{ count:, turns: }`, zero-shaped for a civ with no
happiness snapshots at all.

**Implemented**: `OpeningStrategy#early_libraries` (no Library under
population 6, back in "General, any opening"). Reads `BUILDING_LIBRARY`
plus its civ-unique replacements (`BUILDING_AKKAD_LIBRARY`,
`BUILDING_ROYAL_LIBRARY`), joins each against `CityCensus#snapshot` at the
build turn, and returns only the violations — a Library with no population
snapshot yet is skipped rather than flagged, since there's nothing to
compare against. The "unless rushing National College" exception from the
checklist isn't modeled here; this reports the raw fact, and a report
layer can cross-reference `#national_college` if it needs the exception.

**Implemented**: `OpeningStrategy#universities` (University at population
10 or more, back in "General, any opening"). Reads `BUILDING_UNIVERSITY`
plus `EarlyGame::REPLACED_BY.fetch("BUILDING_UNIVERSITY")` rather than
duplicating that list, and returns every University built with its
population and an `on_target` flag (`population >= 10`), `nil` when no
population snapshot covers the build turn.

**Implemented**: `OpeningStrategy#caravans_to_capital` (Tall: caravans
feeding the capital, back in "Tall (4–6 cities)"). The capital is the
civ's first `city_founded` city, read directly rather than through
`CapitalProximity`, whose own capital lookup is gated on having map
coordinates logged — irrelevant to this question and would silently drop
a civ that lacks them. Returns `{ capital:, routes:, first_turn: }`, where
`routes` is every established `type == "food"` route whose `to_civ` and
`to_city` both name the civ's own capital, earliest first, and
`first_turn` is the turn the first one landed — nil-shaped when the civ
never founded a city.

**Implemented**: `OpeningStrategy#workers_per_city` (Workers per city, in
both the "Tall" and "Wide" sections). Only ever recoverable as an
empire-wide ratio — see "Known gaps" — sampled at the same early-game
boundary `city_spacing` uses. Counted off `OrderOfBattle#at(turn, civ)`
rather than `unit_trained`: a produced worker fires both `unit_trained`
and `unit_created` on the same turn, so summing the two would double count
it, where `OrderOfBattle`'s `unit_created`/`unit_lost` ledger already nets
losses out for free. Returns `{ turn:, workers:, cities:, ratio: }`,
`ratio` and `cities` nil for a civ that never founded a city.

## What's left

Every row in the "Per-criterion feasibility" table above is now
implemented, including the tall/wide split via `OpeningStrategy#playstyle`.
What's still missing is the planned Tradition/Liberty/Honor/Piety
per-branch threshold *table* itself (the finer-grained one `playstyle` was
never meant to replace, only to feed). `first_tech`, `opening_scouts`,
`closed_opening`, worker theft, National College, city spacing,
`playstyle`, `good_wonders`, `caravans_to_capital`, and `workers_per_city`
are all branch-agnostic or already keyed off `#branch`/`#playstyle`, so
that table stays cheap to add.
