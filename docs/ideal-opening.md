# Ideal opening — feasibility and detection plan

Status: **iteration 1 implemented** (2026-09-13) — `OpeningStrategy`
(`app/projections/opening_strategy.rb`) classifies the branch a civ opened
into and how long it took to close it. Everything else below is still
planning. This is stage 4 of
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
- aim for population 10–12 in the city finishing University

**Tall (4–6 cities):**
- 2 workers per city
- National College around turn 60 (quick speed) — **superseded below by
  67/100, see "National College timing"**
- caravans feeding food to the capital as early as possible
- good wonder targets: Temple of Artemis, Great Library, Oracle, Petra,
  Chichen Itza, Leaning Tower of Pisa

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
| Open with 2 scouts | `unit_trained`/`unit_created`, `unit == "UNIT_SCOUT"` | count scout creations before the first settler moves out / early turn window |
| First tech is Mining | `PlayerTimeline#techs(civ)` | first entry's `tech == "TECH_MINING"` |
| Close the opening tree fast | `policy_adopted` where `policy` matches `POLICY_*_FINISHER` (confirmed ids in `db/lekmod/34.15/ids.yml`, e.g. `POLICY_TRADITION_FINISHER`, `POLICY_LIBERTY_FINISHER`) | finisher turn minus the branch's `policy_branch_adopted` turn |
| Never/minimize unhappy turns | `snapshot.happiness` (empire `GetExcessHappiness()`), via `MetricSeries#values("happiness", civ)` | count turns with `happiness < 0` inside the early-game window |
| No Library under population 6 | `building_constructed` (`BUILDING_LIBRARY`) + `CityCensus#snapshot(civ, turn)` | flag when that city's population at the build turn is below 6 |
| University at population 10–12 | `building_constructed` (`BUILDING_UNIVERSITY`, plus `EarlyGame::REPLACED_BY`-style civ variants) + `CityCensus` | population of the building city at the build turn |
| City count (tall 4–6 / wide 6–10) | `city_founded`/`city_captured`/`city_lost` | straightforward count over time |
| Workers per city | `unit_trained`/`unit_created` (`UNIT_WORKER`) ÷ city count at that turn | empire-wide ratio only — the log has no per-city worker assignment |
| Caravans feeding the capital | `trade_route_established`, `type == "food"`, `to_city == capital` | already close to what `TradeRoutes#by_destination` computes (own routes by type) |
| Good wonders | `building_constructed` where `wonder == "world"` | already covered by `Wonders`/`WonderRaces` |
| Wide: close city spacing | `city_founded` (x, y) for the civ's own cities + `HexGrid` (already used by `CapitalProximity`) | no projection exists yet; mechanical extension of `CapitalProximity`'s own pattern to same-civ pairs instead of cross-civ pairs |
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

- **Own-city spacing** (the wide criterion) has no projection yet. Nothing
  blocks writing one — same coordinates, same `HexGrid` class
  `CapitalProximity` already uses, just paired within one civ's own cities
  instead of across civs.
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

Both worker-theft paths from the checklist are now implemented. National
College timing is the next cleanest per-criterion item.
