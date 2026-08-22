# Buffer cities on Pangaea

Execution plan for one feature. `docs/plan.md` keeps the project-wide
iteration history; this file is the detailed plan for this change alone.

## Context

Between two neighbouring capitals there is room for a city, and both sides
want it. A city standing in that gap absorbs the first attack, buys the turns
a capital needs to raise a defence, and doubles as the staging ground for an
attack in the other direction. Sometimes the terrain only allows one — the
minimum city spacing, a mountain range, a lake — and then one civilization
takes the corridor and the other never gets it back. **Having no buffer is a
standing tactical debt that can be called in at any later point in the game**,
and the analysis cannot currently see it: `capital_proximity` says how close
two capitals started, `geometry` says how one empire is shaped, and neither
says who owns the ground between them.

This feature answers, for every pair of capitals close enough to threaten each
other: **did each side get a city into the corridor between them, how far
forward did it get, and who got there first?** And later: **who lost that
city, and when.**

The rule (settled, expected to be recalibrated against more logs):

- **neighbours** — a pair of capitals at hex distance **≤ 17**
- **corridor** — a city whose *detour* is **≤ 6** and which lies strictly
  between the two capitals
- **window** — founded on or before the game-wide early game deadline
  (turn 150 standard / 100 quick, capped at the last logged turn)
- **map** — Pangaea only, decided by `map_script`
- **buffer** — of the corridor cities a civilization owns, the one closest to
  the rival capital

Scope: detection, digest, UI, one key moment, prompt. No verdict is computed:
the projection reports where the cities are, when they went down and in what
order, and the model judges what that was worth — the same division of labour
as `EmpireGeometry` and `CapitalProximity`.

## The corridor rule

The natural phrasing — "no more than 3 hexes off the line between the
capitals" — needs no line geometry. In the game's own metric,

```
detour(C) = d(A, C) + d(C, B) − d(A, B)
```

is the number of extra hexes an army walking from A to B pays for passing
through C. Computed over `HexGrid` for A=(10,20), B=(27,20), d=17:

```
y=23  6 5 4 3 3 3 3 3 3 3 3 3 3 3 3 3 3 3 4 5 6 .
y=22 6 4 3 2 2 2 2 2 2 2 2 2 2 2 2 2 2 2 2 3 4 6
y=21  4 2 1 1 1 1 1 1 1 1 1 1 1 1 1 1 1 1 1 2 4 6
y=20 4 2 A 0 0 0 0 0 0 0 0 0 0 0 0 0 0 0 0 B 2 4
y=19  4 2 1 1 1 1 1 1 1 1 1 1 1 1 1 1 1 1 1 2 4 6
y=18 6 4 3 2 2 2 2 2 2 2 2 2 2 2 2 2 2 2 2 3 4 6
```

`detour = 2 × (rows off the line)`, exactly and symmetrically. So **"3 hexes
of deviation" is `detour <= 6`** — one subtraction, in the same metric
`HexGrid#distance` already provides, with no second notion of distance
introduced into the codebase.

**Detour alone is not enough.** The corridor in the diagram extends past both
capitals: a city 3 hexes *behind* A also scores 6. A city behind your capital
is not a buffer, it is a back city. Hence the second condition, betweenness:

```
d(A, C) < d(A, B)  and  d(C, B) < d(A, B)
```

### Two properties of the rule worth knowing before it ships

**The zero-detour band is wide for diagonal pairs.** On a hex grid the set of
points with `detour == 0` is not a line but every point lying on *some*
shortest path, which for a pair offset along both axes is a rhombus — up to 6
hexes across at d=19. A city 5 hexes from the straight geometric line can
therefore score `detour = 0`. This is deliberate and, we think, correct: the
question is "does this city stand on a route an army would march", not "does
it sit on a ruler". But it means `detour` is not interchangeable with
"distance from the line", and the digest carries the raw `detour` per city so
the model can tell a city squarely across the road (0) from one on the flank
(5) rather than reading a boolean.

**No minimum distance from the owner's capital.** A city 4 hexes out is
counted the same as one 9 hexes out; the pair carries `from_own_capital` and
`from_rival_capital` and the model weighs them. This matters in practice — in
game #21 the Philippines' buffer against Arabia sits 4 hexes from Malolos and
15 from Mecca (a shield hugging the capital) while Arabia's sits 12 from Mecca
and 7 from Malolos (a forward post). Both are buffers; they are not the same
achievement, and *who won the ground* is a separate fact from *who has a
buffer at all*.

### Why the map wrap is switched off

`HexGrid.new(width: nil)` does not wrap. On a Pangaea map every player starts
on one landmass and the map's east and west edges are ocean, so the seam
`HexGrid` normally wraps across is not a route anyone can walk in the early
game — a pair of capitals near opposite edges are far apart on foot, whatever
the wrapped distance says. This is the only place in the codebase that turns
wrapping off on purpose, so it needs its comment.

The consequence: for a pair sitting near the seam, `buffer_cities.pairs[].distance`
and `capital_proximity.distances[]` will disagree, the first being the larger.
Both are in the digest and both are correct for their own question. It cannot
happen on the games imported so far.

### Why the window is the game-wide deadline, not each civ's own boundary

`EarlyGame#series` gives every civilization its own `end_turn`, and the
obvious move is to filter each side's foundings by its own boundary. It is the
wrong clock here. In game #21 Babylon's opening ends at turn 77 and Arabia's
at 100, so a per-civ window would give the *faster* developer the *shorter*
window to claim the ground — punishing it for finishing its opening early, and
comparing the two sides of one contested corridor against two different
deadlines. The corridor is contested by both sides simultaneously; it deserves
one clock. `EarlyGame#deadline_turn`, capped at the last logged turn so we
never report a window past the end of the data (the `:game_end` convention
from `docs/early-game-boundary.md`).

### Foundings only, and cities identified by plot

Detection reads `city_founded`. The buffer race is about settling; a city
taken by conquest is a different fact and arrives through the key moment in
step 3. `PlayerTimeline#cities` drops `x`/`y`, so `BufferCities` reads the
events directly as `CapitalProximity` does.

Cities are matched by plot, never by name — game #21 has two distinct cities
called "Cavite El Viejo", one founded on turn 23 and captured on turn 87, the
other founded on turn 98 four hexes away. `EmpireGeometry` already tracks
plots for exactly this reason.

## The race, not just the outcome

Whether a corridor city exists is the smaller half of the fact. **When it went
down, and whether it went down before the rival's, is the other half**, and
the two sides are not symmetric in what the first mover gained:

- the first settler in the corridor picks the site, which usually means the
  hill, the river, the luxury or the strategic resource — the second one takes
  what is left, or is pushed out of the corridor entirely
- moving first *may* signal fear of that neighbour, or a planned attack on it.
  It equally may signal neither; it is a fact to weigh, never a motive to
  assert
- and it was paid for. A settler stalls the capital that builds it; a capital
  allowed to grow first produces the same settler sooner and keeps the
  population. An early corridor city is therefore usually a real sacrifice —
  **except** where `POLICY_COLLECTIVE_RULE` is in play, which hands over a free
  settler and speeds up the ones after it

The projection reports these facts and asserts none of them:

| Field | Says | Does not say |
|---|---|---|
| `turn` | when the corridor city was founded | who won the race — that needs both sides |
| `order` | which of that civ's own foundings it was (1 = capital) | anything about the empire's size, only its priorities |
| `capital_population` | how big the capital was on that turn | that the capital trained this settler — from `order: 3` upward it may well not have |
| `reach_before` | how far from its capital that civ had already settled before this founding | *why* it settled elsewhere first |
| `settled_first` (per pair) | which side founded its corridor city earlier | anything, when only one side has one — then it is `nil` |
| `priority` (per civ) | the order in which a civ secured its several corridors | which neighbour it feared or intended to attack |

`settled_first` is deliberately `nil` unless **both** sides have a buffer. In
game #21 Babylon settles the Arabia corridor on turn 92 against an Arabia that
never settles it at all; calling Babylon "first" there would dress a turn-92
filler city up as a won race. The asymmetric case is already stated by
`without_buffer`, which is the honest way to say it.

**Collective Rule is not compensated for.** The adoption turn is already in
the digest as `timelines.<civ>.policies`; the prompt tells the model to check
it before reading an early corridor city as a sacrifice. Duplicating the turn
into `buffer_cities` would be the same fact stored twice.

There is no plan to attribute a particular settler to a particular founding.
`unit_created` carries the training city and `unit_lost` with
`cause: "founded_city"` carries the founding, so a matching heuristic is
imaginable, but with several settlers in flight it would be guesswork
presented as fact. `order` and `capital_population` answer the same question
well enough without inventing a link.

## Restraint: what a late corridor city can and cannot tell us

Neighbours frequently agree between themselves about the ground in the middle,
and a corridor settled late by a civilization that could have settled it much
earlier is the visible trace of that. **The agreement itself is not in the
data and never will be.** It is made in conversation outside the game; the
logs carry no declaration of friendship, no denouncement, no research
agreement or open borders — the only diplomatic events at all are
`war_declared` and `peace_made`. Anything we build here detects *restraint*,
which is a behaviour, not *an agreement*, which is an intention. The
projection must not conflate them, and neither may the prompt.

What restraint looks like in events: a civilization holds settlers, uses them
in other directions, and only later puts one in the corridor. "It could have
gone earlier" is exactly the part that is measurable, and it is measurable
without terrain:

```
reach_before = max hex distance from own capital
               over that civ's foundings strictly before the buffer's turn
```

When `reach_before >= from_own_capital`, the civilization had already settled
*further out than the corridor site* before it settled the corridor — so
distance was not the constraint, and the site was reachable earlier. Together
with `order`, that is the honest form of "they had the chance and did not take
it". Read on the imported games:

| Civ vs rival | buffer | `reach_before` vs site | reading |
|---|---|---|---|
| Iroquois vs Bolivia | Buffalo Creek t57, city #5, 5 hexes out | 7 ≥ 5 | had settled further out before; deprioritized this corridor |
| Vietnam vs Iroquois | Thành Pho Hue t75, city #4, 4 hexes out | 5 ≥ 4 | same |
| Iroquois vs Vietnam | Grand River t43, city #3, 4 hexes out | 4 ≥ 4 | same — **both** sides of this pair are late |
| Babylon vs Arabia | Dur-Kurigalzu t92, city #3, 7 hexes out | 8 ≥ 7 | same |
| Chile vs Vietnam | Concepción t34, city #2, 8 hexes out | 0 | its first expansion; nothing was settled earlier |
| Philippines vs Arabia | Cavite El Viejo t23, city #2, 4 hexes out | 0 | same |

Note what the table does **not** support. Iroquois–Bolivia is one-sided:
Iroquois held back, Bolivia settled its side on turn 25 — that is one
civilization's priorities, not a mutual understanding. Babylon–Arabia is late
on Babylon's side against a rival that never settled the corridor at all, and
Babylon went on to take Arabia's capital. Only Vietnam–Iroquois shows the
mutual pattern, and one of those two turns (43) is not late by any absolute
standard. **On the games we have, the signal fires four times and describes an
agreement in at most one of them.**

So: `reach_before` goes in the digest as a number, and the prompt is taught to
read *mutual* restraint — both sides of one pair late, both with reach beyond
the site, neither at war with the other inside the window — as **one possible
reading among several**, alongside the ones that fit the same trace: the
corridor was poor land, or the civ was chasing a luxury elsewhere, or it was
already committed against a different neighbour. We have no terrain, so the
"poor land" alternative can never be excluded. The prompt must say the
agreement is unverifiable from the data and must not present it as a finding.
No `agreement` field, no boolean, no score — a flag would be read as a
detection.

## Which corridor first, when there are several neighbours

A civilization with two or more close neighbours has to choose which gap to
close first, and that choice is cheap to report: `priority` maps each such civ
to its rivals ordered by the turn it settled the corridor against them.

```ruby
priority: { "Babylon" => [ "Austria", "Arabia" ] }
```

Only civs with two or more neighbouring pairs get an entry — with one
neighbour the field says nothing. Only rivals it actually buffered appear;
the ones it never did are already in the pairs' `without_buffer`. Names only,
no turns: those are in `buffers` and would otherwise be stored twice.

On the imported games:

| Civ | Order secured | Then what happened |
|---|---|---|
| Babylon | Austria (t50) → Arabia (t92) | took **Mecca on t144 and Vienna on t192** — first corridor closed, second capital taken |
| Vietnam | Chile (t31) → Iroquois (t75) | no war with either |
| Iroquois | Vietnam (t43) → Bolivia (t57) | no war with either |

Babylon is the useful case, and it is a warning: the neighbour whose corridor
it closed *first* is the one it attacked *last*. Closing a gap early is
consistent with fearing that neighbour, with intending to attack it, and with
neither — the settler simply went where the land was. The prompt gets
`priority` as a fact about sequence and is told explicitly that it does not
identify an intended target; a motive may be named only where the wars, army
power or policies in the data carry it.

## What the rule finds in the games already imported

Computed from the stored events, window turn 100 (both games are
`GAMESPEED_QUICK`). Corridor city per side, with `detour, from_own/from_rival`:

**#21 `babylon-domination` — Babylon (human) wins by domination**

| Pair | d | first | side | buffer |
|---|---|---|---|---|
| Arabia – Babylon | 13 | — | Arabia | **none** |
| | | | Babylon | Dur-Kurigalzu t92, city #3, capital pop 18 (0, 7/6) |
| Austria – Babylon | 13 | — | Austria | **none** |
| | | | Babylon | Akkad t50, city #2, capital pop 7 (5, 8/10) |
| Philippines – Arabia | 16 | Philippines | Philippines | Cavite El Viejo t23, city #2, capital pop 4 (3, 4/15) |
| | | | Arabia | Damascus t65, city #3, capital pop 12 (3, 12/7) |

**#15 `chile-vs-vietnam` — every neighbouring pair is buffered on both sides**

| Pair | d | first | side | buffer |
|---|---|---|---|---|
| Vietnam – Iroquois | 16 | Iroquois | Vietnam | Thành Pho Hue t75, city #4, capital pop 8 (1, 4/13) |
| | | | Iroquois | Grand River t43, city #3, capital pop 6 (0, 4/12) |
| Vietnam – Chile | 14 | Vietnam | Vietnam | Hai Phòng t31, city #3, capital pop 4 (0, 5/9) |
| | | | Chile | Concepción t34, city #2, capital pop 6 (4, 8/10) |
| Bolivia – Iroquois | 13 | Bolivia | Bolivia | La Paz t25, city #2, capital pop 4 (0, 6/7) |
| | | | Iroquois | Buffalo Creek t57, city #5, capital pop 8 (2, 5/10) |

Two things this establishes beyond the mechanics working.

**The absence predicts the conquest.** The two civilizations with no buffer
against Babylon are precisely the two whose capitals Babylon took: Mecca on
turn 144, Vienna on turn 192. That is the story the feature exists to surface,
and it is visible in the first game we point it at.

**The race fields separate cases the turn alone confuses.** The Philippines
(t23, city #2, capital pop 4) adopted `POLICY_COLLECTIVE_RULE` on turn 18 —
that corridor city is fast *and* cheap, and reading it as a sacrifice would be
wrong. Vietnam's Hai Phòng (t31, city #3, capital pop 4) came with Collective
Rule still 39 turns away: same shape, genuinely paid for. Babylon's
Dur-Kurigalzu (t92, capital pop 18) is neither — a late filler into ground
nobody was contesting. All three are "a corridor city exists"; none of them
mean the same thing.

The captures also validate step 3 in advance:

| Turn | Capture | Reads as |
|---|---|---|
| 87 | Cavite El Viejo, Philippines → Arabia | the Philippines lose their buffer against Arabia |
| 152 | Medina, Arabia → Babylon | Arabia's buffer against the Philippines falls to a **third** civilization |

The Medina case is why the moment names the captor separately from the rival
the city was a buffer against: those are often not the same civilization.

**The 17 is not calibrated.** Like the 150/100 deadline it is a first
hypothesis. All three imported games are `WORLDSIZE_TINY`, one human against
`HANDICAP_AI_DEFAULT` bots, and the pair distances land at 13–16 — which is to
say the threshold has never yet had to decide a close case. It is an absolute
hex count and does not scale with map size; revisit it against the first
larger map, and against the first log where a pair sits at 18–20.

---

## 1. `BufferCities` — a new projection

New file `app/projections/buffer_cities.rb`, following `CapitalProximity`: a
`.for(game)` factory that supplies the grid, a constructor taking the game and
the grid, read-only methods, no base class.

```ruby
class BufferCities
  NEIGHBOUR_DISTANCE = 17
  DETOUR_TOLERANCE = 6
  PANGAEA = /pangaea/i

  # Pangaea puts every player on one landmass with ocean at the map's edges,
  # so the seam HexGrid wraps across is not a route anyone can march.
  def self.for(game) = new(game, grid: HexGrid.new(width: nil))
end
```

Public interface:

- `call` → the digest hash (shape below)
- `by_plot` → `{ [x, y] => [ { civ:, rival:, city: } ] }`, every buffer city
  keyed by its plot, for `KeyMomentDetector` to match captures against. A city
  can be the buffer in two pairs at once (Akkad, above), hence the array.

`call` when the map is not Pangaea:

```ruby
{ applicable: false, reason: :map_not_pangaea }
```

and otherwise:

```ruby
{
  applicable: true,
  neighbour_distance: 17,
  detour_tolerance: 6,
  window_turn: 100,
  pairs: [
    { civs: [ "Austria", "Babylon" ],
      distance: 13,
      settled_first: nil,
      buffers: {
        "Austria" => nil,
        "Babylon" => { city: "Akkad", turn: 50, x: 18, y: 16,
                       detour: 5, from_own_capital: 8, from_rival_capital: 10,
                       order: 2, capital_population: 7, reach_before: 0 }
      },
      without_buffer: [ "Austria" ] }
  ],
  priority: { "Babylon" => [ "Austria", "Arabia" ] }
}
```

Rules:

- `applicable` is `false` and `reason` names why, rather than the key being
  absent or the list empty. An empty `pairs` list means "Pangaea, no capitals
  within 17"; a missing section would let the model conclude "nobody built a
  buffer" from a map we never examined. The prompt leans on this distinction.
- pairs come from `CapitalProximity#distances` filtered to `<= NEIGHBOUR_DISTANCE`,
  built on the same unwrapped grid, sorted by distance ascending (closest
  neighbours first, as `GamesController#capital_distances` already sorts).
- a candidate for civ X against rival Y is a `city_founded` event of X with
  `turn <= window_turn`, on a plot other than X's own capital, with
  `detour <= DETOUR_TOLERANCE` and both distances strictly below the pair's.
- the buffer is the candidate with the smallest `from_rival_capital`; ties
  break on the earlier turn. `nil` when there are none.
- `order` is the buffer's 1-based index among that civilization's own
  `city_founded` events, so the capital is 1 and its first expansion is 2.
  Captures do not shift it — this counts what the civ chose to settle.
- `capital_population` is the `new_population` of the last
  `population_changed` on the capital's plot at or before the founding turn,
  `nil` when the log has none. The capital is matched by plot, since
  `population_changed` carries `x`/`y`.
- `reach_before` is the greatest hex distance from that civ's own capital
  among its `city_founded` events strictly before the buffer's turn, and `0`
  when the buffer was its first expansion. It is a distance, never a verdict:
  the comparison against `from_own_capital` is left to the prompt.
- `settled_first` is the civ whose buffer has the lower `turn`, and `nil`
  when either side has no buffer or the turns tie.
- `without_buffer` lists the civs whose entry is `nil` — a derived convenience
  so neither the view nor the prompt has to scan the hash for nulls.
- `priority` covers only civs appearing in two or more pairs, listing the
  rivals they buffered ordered by that buffer's turn, ties broken by rival
  name so the output is stable. Civs with fewer than two neighbours are absent
  rather than present with a one-element list.
- `window_turn` is `[ EarlyGame.new(game).deadline_turn, last_turn ].compact.min`.

Keep the methods small and pure: `neighbours`, `candidates(civ, own, rival, distance)`,
`entry(event, own, rival, distance)`, `detour(own, plot, rival, distance)`,
`capital_population(civ, turn)`, `reach_before(civ, turn)`, `priority`. One
`CapitalProximity` instance per `BufferCities`, memoized; the founding order
computed once into a `{ plot => index }` hash rather than recounted per pair;
`priority` derived from the finished `pairs` rather than recomputed — do not
follow `KeyMomentDetector`, which rebuilds its collaborators inside every
method.

## 2. Digest and UI

**`app/services/digest_builder.rb`** — in `#call`, a top-level `buffer_cities:`
key immediately after `capital_proximity:`, holding `BufferCities.for(@game).call`.
The two belong together: one says how close the capitals were, the other who
holds the ground between them.

**`app/controllers/games_controller.rb`** — `@buffer_cities = BufferCities.for(@game).call`
in `#show`; no private builder, `call` already returns display-ready rows.

**`app/views/games/show.html.erb`** — a new `<h2>Buffer Cities</h2>` section
directly after "Capital Distances" (which ends at line 68), before "Empire
Geometry". Three states:

- not Pangaea → `<p class="empty-state">Buffer cities are only computed for
  Pangaea maps.</p>`
- Pangaea, no pairs → `<p class="empty-state">No two capitals started within
  17 hexes.</p>`
- otherwise a `class="buffer-cities"` table, one **row per civilization of a
  pair** (two rows per pair) so the asymmetry is readable at a glance:

| Pair | Apart | Civ | Buffer | Founded | City # | Capital pop | Reach before | Detour | From own | From rival |
|---|---|---|---|---|---|---|---|---|---|---|
| Austria – Babylon | 13 | Austria | — | — | — | — | — | — | — | — |
| Austria – Babylon | 13 | Babylon | Akkad | 50 | 2 | 7 | 0 | 5 | 8 | 10 |

The row of whichever civ is `settled_first` carries a `<span class="badge">first</span>`
next to its founding turn — the badge class already exists
(`application.css:162`). Empty cells render as `"&mdash;".html_safe`, matching
the rest of the file. The heading states the window and the thresholds:
"founded by turn 100; neighbours within 17 hexes, corridor detour up to 6". No
CSS is needed — `application.css:115` styles `table` globally and the table
class names are hooks only. No drill-down page: there is no series over time
to show.

Below the table, one line per civ in `priority`, only when the hash is
non-empty: "Babylon secured its corridors in this order: Austria, Arabia."

## 3. `KeyMomentDetector#buffer_city_losses`

A buffer city changing hands is a moment on the timeline, unlike the buffer
itself, which is a starting condition. It fires **at any point in the game**,
not only in the early game — that is the whole premise: the debt is incurred
in the opening and called in later.

```ruby
def buffer_city_losses
  buffers = BufferCities.for(@game).by_plot

  of_type("city_captured").flat_map do |event|
    buffers.fetch(plot_of(event), []).select { |buffer| buffer[:civ] == event.payload["old_owner"] }
      .map do |buffer|
        { type: :buffer_city_lost, turn: event.turn, civ: buffer[:civ],
          captured_by: event.payload["new_owner"], against: buffer[:rival], city: buffer[:city] }
      end
  end.sort_by { |moment| moment[:turn] }
end
```

The `old_owner` check keeps the moment to the first time the city leaves the
hands of the civilization it was a buffer for; a later recapture between two
other parties is not that civilization's loss. `captured_by` and `against` are
separate fields because they are frequently different civilizations (Medina,
turn 152).

Wiring:

- `DigestBuilder#key_moments` — `buffer_city_losses: detector.buffer_city_losses`
- `GamesController#key_moment_groups` — its own entry,
  `[ "Buffer Cities Lost", { nil => moments.buffer_city_losses } ]`, placed
  after "Wars". Not folded into "Wars": that section holds war records with a
  different shape. Empty sections are already dropped by `key_moment_group`.
- `KeyMomentsHelper::DESCRIPTIONS` —
  `buffer_city_lost: ->(m) { "#{m[:civ]} lost #{m[:city]} to #{m[:captured_by]}, the city between its capital and #{m[:against]}'s" }`
- `KeyMomentsHelper::TRENDS` — `buffer_city_lost: :down`

## 4. Prompt

`app/prompts/analyze_game.md`. The hard constraint at lines 640–642 stands:
*"exactly these sections, in this order … add no sections beyond these."* No
new report section; extend what is there.

1. **`## How to weigh the signals`** — a new paragraph immediately after the
   `capital_proximity.distances` one (ends at line 313), which it continues.
   Teach: `buffer_cities` reports, for every pair of capitals within 17 hexes,
   whether each side settled a city in the corridor between them; that a
   civilization in `without_buffer` has nothing between its capital and that
   rival's army, so a war on that front reaches its capital directly, while
   the side holding the corridor city has both a shield and a staging ground;
   that `from_own_capital` and `from_rival_capital` say how far forward the
   city sits, a buffer 4 hexes from its own capital being a shield and one 12
   hexes out contesting the ground; that `detour` says how squarely the city
   sits across the route, 0 being on it and 6 on the flank; that the corridor
   often fits only one city, so one side holding it usually explains why the
   other has none rather than lax play; and — explicitly — that
   `applicable: false` means *not measured on this map*, never *no buffers
   existed*, and must not be reported as an absence.
2. **A second paragraph on the race**, following it. Teach: `settled_first`
   names the side that got there first and is `null` when only one side
   settled at all, in which case `without_buffer` is the fact, not a won race;
   that the first mover normally had the better choice of site; that `order`
   says how early in its own expansion the civ spent that settler, `order: 2`
   meaning it went before everything else it built; that `capital_population`
   says how big the capital was at that moment, so a corridor city founded at
   pop 4 cost growth the way one founded at pop 18 did not; that a settler
   stalls the capital building it, which is the price of moving first; and
   that **before reading an early corridor city as a sacrifice, check
   `timelines.<civ>.policies` for `POLICY_COLLECTIVE_RULE`** — a free settler
   and faster ones after it, so an early buffer under Collective Rule was
   bought at a discount. State plainly that moving first *may* indicate fear
   of that neighbour or an intended attack on it, and that neither may be
   inferred from the timing alone; say so only where the wars, army power or
   policies in the data support it.
3. **A third paragraph on restraint and priority.** Teach: `reach_before` is
   how far from its capital that civilization had already settled before it
   settled the corridor, so `reach_before >= from_own_capital` means the site
   was within reach earlier and it chose to settle elsewhere first — a fact
   about priorities, with no cause attached. Where **both** sides of one pair
   are late in that sense and neither declared war on the other inside the
   window, an understanding between the two players is **one possible
   reading**, and it must be named as unverifiable: agreements between
   neighbours are made in conversation outside the game and leave no trace in
   the log, and the same pattern is equally produced by poor land in the
   corridor (the data carries no terrain), by a luxury pulling expansion the
   other way, or by a commitment against a third neighbour. Forbid stating an
   agreement as a finding, and forbid inferring one from a single side being
   late. Then `priority`: the order in which a civilization with several close
   neighbours closed its corridors is a fact about sequence only — in game #21
   Babylon secured the Austrian corridor first and attacked Arabia first, so
   the order must not be read as naming an intended target.
4. **`## Per-Player Strategic Verdict`** (from line 651) — the early game
   assessment each entry already opens with should state, where the
   civilization has a neighbour within 17 hexes, whether it secured the
   corridor against that neighbour and whether it got there first, as a fact
   about the opening's position on the map rather than its development pace.
5. **`## Counterfactuals`** (from line 687) — the section already asks which
   civilizations could have stopped the leader and at what cost. Add that a
   `buffer_city_lost` moment marks either a stronger attack than the defender
   expected or an outer defence beginning to fail, and that the turns between
   it and a capital falling are the warning the defender actually had.

Record the feature in `docs/plan.md` at the end of the file, following the
`## Plan: per-player early game boundary` pattern: status, the rule, the
tables above, and what the prompt now teaches.

---

## Tests (TDD — red first, reviewed, then the smallest implementation)

Minitest, `bin/rails test`, records built inline in `setup`, test names written
as full sentences starting with the method name. Copy the `event(...)` helper
from the bottom of `test/projections/key_moment_detector_test.rb`.

| File | Coverage |
|---|---|
| `test/projections/buffer_cities_test.rb` (new) — geometry | non-Pangaea `map_script` returns `applicable: false` with `reason: :map_not_pangaea`; a pair beyond 17 hexes is not a pair; a city on the line is a buffer; a city 3 hexes off the line (`detour == 6`) is a buffer; 4 hexes off (`detour == 8`) is not; a city 3 hexes *behind* its own capital scores `detour == 6` but fails betweenness; a city past the rival capital fails betweenness; the forward-most of two corridor cities is the buffer; a civ with no corridor city gets `nil` and appears in `without_buffer`; distances do not wrap across the map edge; one city can be the buffer for two pairs |
| the same file — window and race | a city founded after `window_turn` does not count; `window_turn` is capped at the last logged turn; a captured city does not create a buffer; `order` counts only that civ's own foundings and ignores captures; `capital_population` reads the capital's population as of the founding turn; `capital_population` is `nil` when the log has no `population_changed` for it; `settled_first` names the earlier founder; `settled_first` is `nil` when one side has no buffer; `settled_first` is `nil` on a tie |
| the same file — restraint and priority | `reach_before` is the greatest distance from the capital among earlier foundings; `reach_before` is `0` when the buffer is the civ's first expansion; `reach_before` ignores foundings on or after the buffer's turn; `priority` orders a civ's rivals by the turn it buffered each; `priority` omits a civ with only one neighbouring pair; `priority` omits rivals the civ never buffered |
| `test/projections/key_moment_detector_test.rb` | `buffer_city_losses` reports the capture of a buffer city with `captured_by` and `against`; a capture by a third civilization still names the pair rival in `against`; a capture on a plot that is not a buffer produces nothing; a non-Pangaea game produces nothing |
| `test/services/digest_builder_test.rb` | `buffer_cities` present in the digest; `key_moments[:buffer_city_losses]` present |
| `test/controllers/games_controller_test.rb` | the "Buffer Cities" section renders a pair with one side missing its buffer; the `first` badge renders on the earlier founder's row; a non-Pangaea game renders the empty state |
| `test/helpers/key_moments_helper_test.rb` | the `buffer_city_lost` sentence names the city, the captor and the rival |

The geometry cases are worth writing as coordinates chosen off the diagram in
the corridor section, with the expected `detour` asserted directly — that
keeps the test readable as the rule rather than as a fixture.

## End-to-end verification

**No re-import is needed.** `city_founded`, `city_captured` and
`population_changed` all carry `x`/`y` and have been in `KNOWN_EVENT_TYPES`
from the start; every table above was computed purely from stored events. The
UI recomputes projections on every request.

```sh
bin/rails test
bin/rails server        # /games/15, /games/20, /games/21
```

Expected, straight from the tables: **#21** shows Arabia and Austria with no
buffer against Babylon, Babylon holding one against each, and the
Philippines–Arabia row badged `first` on the Philippines at turn 23; **#15**
shows all six sides of its three neighbouring pairs buffered, with
`settled_first` on Iroquois, Vietnam and Bolivia respectively; **#20** (log
ends turn 20) shows a `window_turn` of 20 — the case that catches an uncapped
window. Key Moments on #21 must list the turn-87 and turn-152 losses.

The prompt needs a fresh run — `analyses.digest` is a frozen snapshot, so old
analyses do not gain `buffer_cities` retroactively:

```sh
bin/civ analyze 21
```

Then check that the Per-Player verdicts for Arabia and Austria name the
missing buffer as a fact about their opening, that the Philippines' turn-23
corridor city is read against their turn-18 Collective Rule rather than as a
sacrifice, and that the Counterfactuals connect the missing buffers to the
capitals falling on turns 144 and 192. Without an API key the prompt as sent
is visible at `/games/21/analyses/<n>/prompt`.

Two things the report **must not** say, and they are the acceptance criteria
for paragraph 3 of the prompt: that Babylon and Arabia had an understanding
about their corridor (Babylon is late there on its own, and went on to take
Mecca), and that Babylon's turn-50 Austrian corridor marks Austria as its
first intended target (it attacked Arabia first). Both are the readings the
data invites and neither is supported by it.

---

## Open questions, deliberately deferred

- **17 hexes**, as above: absolute, unscaled by map size, never yet tested on a
  close case.
- **Site quality.** "The first settler picked the better spot" is the premise
  of the race, and nothing in the data confirms it — the logger reports no
  terrain, no resources and no luxuries around a city. `capital_population`
  and `order` describe the cost of moving first, not the prize. Closing that
  gap needs a `city_surroundings` event; `docs/early-game-boundary.md` costs it
  out.
- **A third civilization's city in the corridor.** Today a wedge city belonging
  to neither member of the pair is invisible; it is neither side's buffer but
  it does block the road. Cheap to add once `candidates` exists — group the
  corridor by owner instead of filtering to the pair — but it is a second
  concept and does not need to ship first.
- **Buffers acquired by conquest.** A corridor city captured on turn 60 is a
  buffer for its new owner, and step 1 will not say so. Handling it means
  replaying ownership at `window_turn` the way `EmpireGeometry` does, rather
  than reading foundings. Worth doing only if a log shows it happening inside
  the window.
- **Terrain.** Like `capital_proximity` and `geometry`, this carries none: a
  corridor crossing a mountain range or a lake reads exactly like open ground,
  and the reason only one side has a buffer may be that only one city ever
  fits. This is also what permanently caps the restraint signal: "they agreed
  to leave it" and "the land was worthless" produce identical events.
- **A razed buffer.** `city_destroyed` exists in the logs and follows the
  captures we already read (Cavite El Viejo t87 → destroyed t93, Medina t152 →
  destroyed t159). A razed corridor city empties the corridor for good, which
  is a harder fact than a captured one that merely changed hands. Step 3
  reports it as a capture; distinguishing the two is a second moment and can
  wait until the first is in use.
- **Mutual restraint as its own signal.** If a human-multiplayer log ever
  shows the pattern cleanly — both sides late, both with reach to spare,
  no war — it may be worth reporting the pair-level fact rather than leaving
  the model to notice it. Not before: on the two games we have, the mutual
  case occurs once and is not convincing.
