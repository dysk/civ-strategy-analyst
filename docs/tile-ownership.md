# Which city a tile belongs to

Design for one projection. `docs/plan.md` keeps the project-wide iteration
history and recorded this as an unimplemented idea under "Tile→city
resolution".

That entry proposes a nearest-owned-city lookup built on `HexGrid#distance`.
Measurement says geometry is the fallback and not the mechanism — the log
attributes three quarters to nine tenths of the tiles outright, and what is
left is a far smaller problem than the entry assumes.

**Stages one to three ship** as `TileOwnership` (2026-10-16). Two methods,
both dated to the end of the turn they are asked about:

- `candidates(plot, turn:)` returns `{ cities:, civs:, source: }` — every
  city the log lets us name, which is the one holding the plot
  (`source: :owned`), the ones holding the ring around it
  (`source: :adjacent`) or the nearest standing centres within
  `REACH` (`source: :nearest`). The fourth stage is that method returning
  nil, which says no place is named rather than carrying a `:nowhere` tag
  of its own.
- `owner(plot, turn:)` returns `{ city:, civ:, source: }`, each field filled
  only as far as the candidates agree. Two of a civ's cities beside a plot
  name the civ and leave the city nil; a hex between two empires names
  neither, and its `source` is what tells a consumer the answer is there to
  be read off `candidates`.

Together they answer 98.5, 98.5 and 93.8 percent of the rows that ask.
Every count below is measured through that projection on the imported
india-diplo, chile-vs-vietnam and babylon-domination games.

One gap the index leaves. A city founded before the log begins gets no
centre and no ring, so it enters the index only when it first acquires a
plot. Logs that start mid-game are the ones this costs, and the fix is a
read of the opening snapshot rather than anything geometric.

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

Known consumers. `Religion#uses` and `PlayerTimeline#expended_row` are
wired up; the rest are not:

- **`PlayerTimeline#expended_row`** handed out `city: nil` for every
  targeted great-person expend, because the pairing to `improvement_built`
  by `(turn, civ)` tested its candidate with `.any?` and dropped the matched
  event. Placed since 2026-10-16. Only a planted improvement leaves a plot,
  so this reaches 55 of the 239 expends in the logs, 54 of them on the
  expending civ's own land.
- **`ChronicleSpine`** narrates a great person's death, and a battle death,
  with no location at all. `PlayerTimeline`'s lost rows carry `located:
  :logged` where the log named a city, which is 142 of the 244 great-person
  deaths; the other 102 carry a plot and wait for this.
- **`Religion#uses`** returned `city`, `x` and `y` for an inferred
  missionary or inquisitor use, and the `city` was nil for 109 of the 116
  uses in the logs. A hold beginning near such a plot is the projection's
  one candidate cause, so without a place name it could not be set against
  the hold at all. Placed through this projection since 2026-10-16, 108 of
  the 116 carry a city and 39 holds across four logs have a named candidate
  cause.
- **`improvement_pillaged`** is the only record of enemy infrastructure
  being destroyed, and today nobody can say whose city lost the mine. No
  projection reads the event at all, so this one is a new reading rather
  than a field to fill - recorded as an idea in `docs/plan.md`.

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
and belongs in the index from the founding turn. A plot another city already
holds stays with it, the way the game leaves settled borders alone.

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
deltas depend on the row's parity — `HexGrid#neighbours` is that ring, and
a founding claims it. A fixed eight-delta square neighbourhood is wrong here
and inflates stage 2 at stage 3's expense, which a test pins so the mistake
cannot come back quietly.

How much work each stage does, over every `improvement_built` and `unit_lost`
row with no city:

| stage | india-diplo | chile-vs-vietnam | babylon-domination |
|---|---|---|---|
| 1, in the index | 1360 | 496 | 660 |
| 2, adjacent to one city | 57 | 50 | 61 |
| 2, adjacent to several plots of one civ | 5 | 10 | 5 |
| 2, adjacent to two or more rivals | 14 | 6 | 5 |
| 3, geometry decides | 55 | 47 | 43 |
| 4, beyond the reach of any city | 23 | 9 | 51 |
| rows in total | 1514 | 618 | 825 |

Stage 1 answers 80 to 90 percent of them exactly and geometry is left with 4
to 8 percent.

An earlier draft of this table credited stage 1 with 90 to 98 percent,
because the probe behind it built one index out of the whole log and
answered a turn-50 question with a tile bought on turn 200. Dating the index
costs stage 1 about eight points, and the plots it hands on are ones that
were genuinely nobody's at the time — claimed later in the game, held by
somebody at another time, or nobody's throughout.

A plot adjacent to two rivals' tiles is a border hex, which is the most
interesting answer the lookup can give and should reach the chronicle as one
rather than being collapsed to a single name, but it is 25 rows across three
games and no feature should be built around it.

`REACH` keeps stage 3 from naming a city for a battle in open wilderness,
and it is five hexes because the game says so. `MAXIMUM_ACQUIRE_PLOT_DISTANCE`
is 5, so no city can ever hold a plot further out, and the logs agree
exactly — across all three, every plot a city claimed sits at most five
hexes from its own centre, with nothing at six or beyond. How far these
rows sit from the nearest centre would have allowed a looser number, since
india-diplo and chile-vs-vietnam both fall off a cliff after six, but
babylon-domination decays instead of falling off and a rule the game
enforces beats a cliff in a distribution.

## Ties are returned, not broken

Equidistant cities come back together. The whole question covers 30 rows
across the three logs — 7 two-way ties and 5 three-way in india-diplo, 11
two-way and 1 three-way in chile-vs-vietnam, 5 two-way and 1 three-way in
babylon-domination.

A deterministic tiebreak by name or by founding turn would give a stable
answer that is not a true one, which is worse than no answer. For the
chronicle, "between Delhi and Agra" carries more than an arbitrarily chosen
Delhi. For a field that needs exactly one name, a tie stays nil.

Stage 2 already works this way, so stage 3 needs no new machinery — it adds
nearest centres to what `candidates` returns, and `owner` keeps filling a
field only where they agree. Roughly one in five of the rows that reach
geometry is a tie, measured on the live centres of the three logs.

## Candidates are never narrowed to the combatants

A death resolved to a tile can be on land belonging to neither side.
Measured on deaths that carry `killed_by` and resolve through stage 1 or 2,
the owner is a third party in 2 of 29 cases in india-diplo, 2 of 16 in
chile-vs-vietnam and none of babylon-domination's 17. Units cross other
civs' land on open borders and city-state territory sits between empires, so
the land under a battle is a fact about diplomacy rather than about the
battle — but on these numbers it is a rare one, and the case against
filtering rests on the paragraph below rather than on them.

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

A destroyed city's plots are released with no event naming them, so they
drop out of the index and fall through to stage 3, which is the correct
reading — the land is nobody's.

**`city_destroyed` does not mean the city died.** Every one of them in these
logs follows a `city_captured` of the same plot by a turn or less, and the
ones carrying the *losing* civ are that civ's record of losing the city, not
a razing. Onondaga is "destroyed" on turn 153 of india-diplo and goes on to
file 33 more snapshots under India. Mecca is "destroyed" on turn 145 of
babylon-domination and buys 25 more plots under Babylon. A real razing
carries the *current owner's* civ, and after one the city files nothing
ever again.

Telling them apart needs no new reading of the log, since the replay
already knows who holds the city, so the razing is the one whose civ is
that holder. Reading them apart moved 69 rows from an inference back to a
fact and gave 13 more a place they had none for.

Two cases that read like counter-examples are not. Cavite El Viejo is
captured by Arabia on turn 87 of babylon-domination, written off by the
Philippines the same turn, razed by Arabia on 93 and refounded by the
Philippines on 98 one hex away. Tyre is captured by the Sioux on turn 124 of
espionage-test, written off by Jerusalem that turn, razed by the Sioux on
128 and refounded by Jerusalem on 142 four hexes away. The rows that keep
naming them afterwards belong to the new cities.

A lookup is answered with the state the turn ended in, the convention
snapshots already follow here. A unit dying on the turn its city changed
hands therefore reads as standing on the taker's land, and one dying on the
turn its city was razed reads as standing nowhere. Deaths on a city centre
are 20 rows across five logs and exactly one of them falls on such a turn,
so the turn is a good enough handle and consumers need not carry a `seq`.

## Citadels

A citadel placed aggressively on an unowned border hex is the one
great-person improvement that need not sit on its builder's land. Placed
defensively inside the borders it steals nothing and lands in the index like
any other tile. The aggressive case resolves at stage 2 and names the city
the hex sits beside, which is right either way. No citadel appears in any of
the five example logs, so this is a note rather than a requirement.
