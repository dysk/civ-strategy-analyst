# Which city a tile belongs to

Design for one projection, to review before writing failing tests for it,
the same way `docs/city-state-influence.md` and `docs/espionage.md` preceded
theirs. `docs/plan.md` keeps the project-wide iteration history and records
this as an unimplemented idea under "Tile→city resolution".

That entry proposes a nearest-owned-city lookup built on `HexGrid#distance`.
Measurement says geometry is the fallback and not the mechanism — the log
attributes nine tenths of the tiles outright, and what is left is a far
smaller problem than the entry assumes.

## Context

Six event types carry `x`/`y` with no city, so every question about where
something happened is currently unanswerable. Counts from
`examples/india-diplo.jsonl`, as "rows with no `city` / rows in total":

| event | without a city |
|---|---|
| `improvement_built` | 985 / 985 |
| `unit_lost` | 552 / 1041 |
| `unit_created` | 307 / 1402 |
| `improvement_pillaged` | 63 / 63 |
| `natural_wonder_discovered` | 20 / 20 |
| `trade_route_plundered` | 3 / 3 |

Known consumers, each already blocked on exactly this:

- **`PlayerTimeline#expended_row`** (`player_timeline.rb:218`) hands out
  `city: nil` for every targeted great-person expend. The pairing to
  `improvement_built` by `(turn, civ)` already exists at `:230`, but
  `expend_action` tests it with `.any?` and drops the matched event, so the
  plot it carries never reaches the row.
- **`ChronicleSpine`** narrates a great person's death, and a battle death,
  with no location at all.
- **`Religion#uses`** (`religion.rb:54`) returns `city`, `x` and `y` for an
  inferred missionary or inquisitor use, and the `city` is usually nil. This
  is not cosmetic. A hold beginning near such a plot is the projection's one
  candidate cause, and without a place name it cannot be set against the
  hold at all.
- **`improvement_pillaged`** is the only record of enemy infrastructure
  being destroyed, and today nobody can say whose city lost the mine.

## The log attributes tiles itself

`plot_acquired` and `plot_bought` are imported (`import_game.rb:16`) and read
by nothing. Both name the city:

```
{"city":"Delhi","civ":"India","event":"plot_acquired","turn":4,"x":31,"y":14}
{"bought_with":"culture","city":"Lhasa","civ":"Tibet","event":"plot_bought","turn":6,"x":46,"y":19}
```

In india-diplo that is 1155 + 1105 rows covering 65 of its 66 cities, so a
plot→city index is a read of the log rather than a geometric inference.

## The founding ring is derived, not looked up

The first acquisition lands around turn 6, so the tiles a city holds from
founding appear in no event. They need none. The game enforces a minimum
settling distance, and the logs confirm it — the smallest gap between the
centres of two coexisting cities is **3** hexes in india-diplo and **4** in
chile-vs-vietnam. At a gap of 3, every tile adjacent to one centre is at
least 2 from any other, so a city's own ring of six is unambiguously its own
and belongs in the index from the founding turn.

Ring 2 is not. The same gap of 3 puts a tile two hexes from one centre one
hex from the other, which makes it the second city's ring 1. From ring 2
outward only the index answers.

Two closer pairs appear in the logs and both are artifacts rather than
counter-examples. In babylon-domination, Cavite El Viejo is destroyed on turn
93 and refounded one hex away on turn 98. In india-diplo, the founding of
Chitungwiza is logged twice on turn 146 at the same plot, which is a dedup
gap worth chasing separately.

## The lookup

Four stages, each returning the city **and** how it was arrived at, so a
consumer can treat a fact and an inference differently. `Deals` already does
this with `unattributed_imports`, and `Religion` with `inferred: true`.

| stage | source | tag |
|---|---|---|
| 1 | the plot is in the index, or is a live city's centre or ring 1 | `:owned` |
| 2 | the ring-1 plots around it are indexed and name one city | `:adjacent` |
| 3 | nearest city centre by `HexGrid#distance`, within the cutoff | `:nearest` |
| 4 | nothing within the cutoff | `:nowhere` |

Adjacency means `HexGrid#distance == 1`, which is six plots whose offset
deltas depend on the row's parity. A fixed eight-delta square neighbourhood
is wrong here and inflates stage 2 at stage 3's expense.

How much work each stage does, over every `improvement_built` and `unit_lost`
row with no city:

| stage | india-diplo | chile-vs-vietnam | babylon-domination |
|---|---|---|---|
| 1, in the index | 1500 | 556 | 736 |
| 2, adjacent to one city | 7 | 26 | 30 |
| 2, adjacent to several plots of one civ | 2 | 17 | 5 |
| 2, adjacent to two or more rivals | 8 | 0 | 8 |
| 3, geometry decides | 20 | 21 | 46 |
| 4, beyond a cutoff of 5 hexes | 6 | 0 | 31 |
| rows in total | 1537 | 620 | 825 |

Stage 1 answers 90 to 98 percent of them exactly, and geometry is left with
1 to 6 percent. A plot adjacent to two rivals' tiles is a border hex, which
is the most interesting answer the lookup can give and should reach the
chronicle as one rather than being collapsed to a single name, but it is
sixteen rows across three games and no feature should be built around it.

The **cutoff** keeps stage 3 from naming a city for a battle in open
wilderness. Beyond it the answer is `:nowhere` and no place is named. Five
hexes is a starting proposal and not a measurement, in the same spirit as
`CityStateStanding::RIG_GAIN` — it catches 6 of india-diplo's 20 geometric
rows, 31 of babylon-domination's 46 and none at all in chile-vs-vietnam, the
spread being how far from anybody's borders each game's wars were fought.
Settle the number against a second log before fixing it.

## Ties are returned, not broken

Equidistant cities come back together. The whole question covers eleven rows
across the three logs — two two-way ties and one three-way in india-diplo,
four two-way and one three-way in chile-vs-vietnam, two two-way and one
three-way in babylon-domination.

A deterministic tiebreak by name or by founding turn would give a stable
answer that is not a true one, which is worse than no answer. For the
chronicle, "between Delhi and Agra" carries more than an arbitrarily chosen
Delhi. For a field that needs exactly one name, a tie stays nil.

## Candidates are never narrowed to the combatants

A death resolved to a tile is often on land belonging to neither side.
Measured on deaths that carry `killed_by` and resolve through stage 1 or 2,
the owner is a third party in 6 of 40 cases in india-diplo, 2 of 22 in
chile-vs-vietnam and 7 of 33 in babylon-domination. Units cross other civs'
land on open borders, and city-state territory sits between empires, so the
land under a battle is a fact about diplomacy rather than about the battle.

Filtering candidate cities to the civs involved is worse than useless when
`killed_by` is absent, which is the common case — 386 of india-diplo's 552
unattributed deaths. The only known side is then the civ that lost the unit,
and the filter drags every such death homeward. Geometry runs against every
city, and the owner's identity is part of the result.

## The index is a replay, not a map

Ownership moves during a game, so the index is built by replaying events in
log order rather than collecting them into one table. Founding adds a centre
and its ring, an acquisition or a purchase adds a plot, a capture moves a
city's whole set to the new owner, and a destruction removes it.
`EmpireGeometry#replay` already walks `city_founded` and the captures for
exactly this purpose and keeps only plots, discarding the city names this
needs.

Two things the replay has to survive. `city_destroyed` can fire twice for the
same city, in both logs that carry it at all, so removal must be idempotent.
A destroyed city's plots are released with no event naming them, so they drop
out of the index and fall through to stage 3, which is the correct reading —
the land is nobody's.

## Citadels

A citadel placed aggressively on an unowned border hex is the one
great-person improvement that need not sit on its builder's land. Placed
defensively inside the borders it steals nothing and lands in the index like
any other tile. The aggressive case resolves at stage 2 and names the city
the hex sits beside, which is right either way. No citadel appears in any of
the five example logs, so this is a note rather than a requirement.
