# What a city was worth when it changed hands

Execution notes for one feature. `docs/plan.md` keeps the project-wide
iteration history; this file holds the rules that need calibrating and the
honest limits on what the log can see.

## Context

`ChronicleSpine` gave `city_captured` a flat weight of 4, which rated the
Iroquois capital and a border town alike. `india-diplo` has exactly two
captures and they went opposite ways:

| | Onondaga (t152) | Buffalo Creek (t155) |
|---|---|---|
| population before / after | 18 / 9 | 7 / 2 |
| buildings before / after | 18 / 10 | 9 / 5 |
| population share of owner | 0.25 | 0.13 |
| science share of owner | 0.34 | 0.11 |
| capital | yes | no |
| conquest | yes | yes |
| held | to the end, puppet, pop recovering | occupied + razed, gone by t157 |
| resistance turns | 3 → 2 → 1 → 0 | 1 → 0 |

One was a fifth of the Iroquois' potential and a third of their science;
the other was a frontier town thrown away. `CityValue` measures that
share; `PlayerTimeline` attaches it to the capture; `ChronicleSpine`
scales the weight by it.

## The share

`CityValue#at(city, turn)` reads the last `city_snapshot` of the city on
or before `turn`, takes the **owner from that row**, and reports, for
population, buildings and the five yields carried per city
(`yield_science`, `yield_production`, `yield_gold`, `yield_culture`,
`yield_faith`):

- **`<metric>_share`** — the city's value over the sum of that value
  across the owner's own cities at the same turn. Never over the
  empire-wide `snapshot` yields, which fold in city-states, trade routes,
  religion and happiness. A yield the whole empire earns nothing of has a
  nil share, not a zero.
- **`<metric>_rank`** — the city's place among the owner's cities by that
  value, largest first.

A reload can snapshot one turn twice; the later payload wins, the same
rule `CityCensus` and `WonderRaces` already use.

## The valuation on a capture

`PlayerTimeline#cities` attaches a `valuation` to every `:captured` and
`:lost` entry:

- **`value`** — `CityValue#at(city, capture_turn - 1)`: the share the city
  was of the empire that is about to lose it, as it stood the turn before.
- **`before` / `after`** — population and buildings on the last snapshot
  under the old owner and the first under the new one. `after − before` is
  what the sacking destroyed; for a cession (`conquest: false`) the two sit
  close and nothing was destroyed.
- **`resistance`** — the captor's snapshots of the city from the capture
  turn until the first turn `resistance_turns` reached zero, each carrying
  `resistance_turns`, `occupied`, `puppet`, `razing`. A city held through
  its unrest is bounded here; one razed keeps its `occupied`/`razing`
  turns to the end of its life.
- **`captor_influence`** — the new owner's influence over the old owner
  (`points`, `level`, `trend`) on the nearest snapshot at or before the
  capture turn. `level` is `INFLUENCE_LEVEL_UNKNOWN` for every pair in
  `india-diplo`, so only `points` and `trend` carry meaning there.

The whole `valuation` is nil where the log has no `city_snapshot` at all,
degrading like `BufferCities` rather than reporting a wrong number.

## The chronicle weight — uncalibrated

`ChronicleSpine` scales the `city_captured` moment:

- **`:major`** — weight 4, anchors an entry. Fires when the
  `city_captured` payload has `capital: true`, **or** the city's
  `population_share` the turn before was **≥ 0.20**.
- **`:minor`** — weight 2, stays as texture below the anchor threshold.
- **absent `scale`** — no `city_snapshot` placed the city; the weight
  stays at the flat 4.

**`MAJOR_POPULATION_SHARE = 0.20` is the user's calibration from play, not
a measurement.** The evidence is two captures (Onondaga at 0.25, Buffalo
Creek at 0.13) plus `babylon-domination`'s eight, which carry no
`city_snapshot` and so only exercise the flat fallback. The cut is on
population alone — the steadiest measure of a city's worth — because a
frontier town cranking one build can spike a single yield share (Buffalo
Creek held rank 1 and 21% of Iroquois production the turn it fell) without
being worth an entry. Expect to revisit both the threshold and the
choice of metric against more logs with real captures.

## What the log cannot see

- **A capture read from the wrong side of the turn.** `value` and `before`
  use `capture_turn - 1`. In `india-diplo` the capture-turn snapshot still
  shows the old owner, so `capture_turn` itself would also work, but the
  minus-one is the safe reading of "before".
- **Buildings lost vs. buildings that were never there.** `before`/`after`
  `buildings` is a bare count; which buildings burned is not logged.
- **The tiles worked.** A city's territory and terrain are not in
  `city_snapshot`; population and buildings are the whole measure of what
  was taken.
- **A city that changed hands more than twice.** Each capture is valued on
  its own; the projection does not track a city's running loss of worth
  across repeated sackings. The prompt states the rule; no number is
  computed for it.
