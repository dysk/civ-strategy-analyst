# Reading the log the logger now writes

Roadmap across several features. `docs/plan.md` keeps the project-wide
iteration history and gains a `## Plan:` section per feature as each is
implemented; this file is the ordering and the evidence behind it.

Every number quoted here is measured against `examples/india-diplo.jsonl`,
which is **one game, one human against five bots**. Where a mechanism is
specified but that game never exercised it, the text says so; treat those
as designed and unverified.

## Context

`civ-narrative-logger` has finished Tier 1 and Tier 2 of
`docs/candidate-events.md`: per-city snapshots, city-state standings, trade
routes, espionage, yield attribution, resource stocks, and the diplomatic
state of every pair. `civ-strategy-analyst` imports all of it and reads
almost none of it.

`docs/import-volume.md` closed with the question this plan answers:

> Whether `city_snapshot` should feed a projection — city production is the
> first thing in the log that shows a wonder race and the moment somebody
> lost it — is a separate question, and worth answering only once a real game
> has produced the records.

`examples/india-diplo.jsonl` is that game: 18,273 lines, 68 event types, 6
majors, 11 city-states, turns 0–184, ending `VICTORY_DIPLOMATIC` for India on
turn 183. Every feature below was checked against it before being proposed,
and the numbers quoted are measured, not assumed.

**Constraint that shapes everything here:** `babylon-domination.jsonl` and
`chile-vs-vietnam.jsonl` carry **zero** `city_snapshot` records. Every
projection built on them must degrade like `BufferCities` does — an
`applicable: false` with a `reason:`, never a silently wrong number.

## What the log carries that nothing reads

| Event / field | Volume in india-diplo | Read by |
|---|---|---|
| `city_snapshot` (pop, 7 yields, `producing`, `production_stored`, buildings, defense, damage, puppet/occupied/razing, religion) | 5,206 | nothing |
| `snapshot.resources[]` (total/used/import/export per resource) | on every snapshot | nothing |
| `snapshot.yield_sources` (science/faith/culture/tourism attribution) | on every snapshot | nothing |
| `snapshot.researching` + `research_turns_left` | on every snapshot | nothing (dropped by `SNAPSHOT_METRICS`) |
| `city_state_snapshot` (influence, `per_turn`, level, protected, ally) | 238 | nothing |
| `session_started.city_states[]` (trait, personality, unique unit, plot) | 11 | nothing |
| `trade_route_established` (both sides' gold/science/food/production/tourism/pressure) | 118 | nothing |
| `city_converted` | 644 | nothing |
| `embassy_*`, `open_borders_*`, `friendship_*`, `defensive_pact_*`, `trade_agreement_*` | 54 | nothing |
| `spy_*` | 130 | nothing |
| `game_ended` (`victory`, `winner_civs`, `winning_turn`) | 1 | **nothing** |

Roughly 55% of a real log's rows reach no projection.

---

## Order of work

Ranked by value against cost. Tranche 1 is specified below; the rest is
context for the order, to be detailed when reached.

**Tranche 1 — the city snapshot pays for itself**
0. `game_ended` as the outcome (half a day, fixes a correctness gap)
1. Population counted per city (small, and it changes the chronicle's rankings)
2. The wonder race (the reason `city_snapshot` was logged at all)
3. What a city was worth when it changed hands

**Tranche 2 — the diplomatic game**
4. City-state influence and the spies that move it (the india game is decided
   by exactly this, and by nothing else that is logged)
5. Diplomatic ties (logged, exact, read by nothing)
6. Trade routes

**Tranche 3 — intent and belief**
7. Research beelines (`researching`)
8. Yield attribution (`yield_sources`)
9. Religion and conversion
10. Resource-flow deal reconstruction (explicitly inferred)

---

# Tranche 1

## 0. `game_ended` is the outcome

**Implemented 2026-09-07** — `docs/plan.md`, *"the game's outcome, read
rather than inferred"*. What follows is the plan as written plus the three
game-ending mechanisms found while implementing it.

`OutcomeResolver` infers the winner from the last score snapshot and
`civ analyze` takes `--winner` / `--victory-type` by hand, because the plan
was written when *"there's no victory event in the data"*. There is now:

```json
{"event":"game_ended","turn":184,"victory":"VICTORY_DIPLOMATIC",
 "winner_civs":["India"],"winner_team":0,"winning_turn":183}
```

- `ImportGame` writes `games.winner_civ`, `winner_civs`, `victory_type`,
  `completed` from it (`app/services/import_game.rb`, beside
  `apply_game_settings`). `victory_type` is mapped onto the words
  `OutcomeResolver#inferred_result` already speaks.
- `OutcomeResolver` gains a `source: :logged` between `:declared` and
  `:inferred`; the explicit `--winner` still wins, so a user override is never
  silently discarded.
- `winner_civs` is an array (team victory), so a team win must not be flattened
  to one civ. It is a Postgres string array; `winner_civ` stays as its first
  element for the views and CLI that show one name.

### Three ways a game ends, not one

`game_ended` fires off `Game.SetWinner`. LEKMOD's own multiplayer vote system
(`mp_proposal_result`, unrelated to the World Congress) also ends games, and
only some of those paths reach `SetWinner`. Checked against
`civ-narrative-logger/src/victory.lua`, `src/extractors.lua` and LEKMOD's
`ProposalChartPopup.lua` `onProposalResult`:

| vote | effect on pass | `SetWinner`? | reaches `game_ended`? |
|---|---|---|---|
| **concede** | `SetWinner(subject.team, VICTORY_DIPLOMATIC)` | yes | yes — as a diplomatic win |
| **scrap** | `SetWinner(activePlayer.team, VICTORY_SCRAP)` | yes | yes — with a meaningless winner |
| **irrelevance** | host kicks the subject, game continues | no | no |
| remap | lobby reshuffle | no | no |

- **concede** already arrives as `game_ended`, labelled `VICTORY_DIPLOMATIC`.
  No outcome work — the only loss is the label. Relabelling it from a genuine
  delegate win (cross-reference a passed `concede` near `winning_turn`) is a
  follow-up, not a correctness gap.
- **scrap** ends the game with no real winner — the `winner_civs` on that
  record is only the client that resolved the vote. `ImportGame` maps
  `VICTORY_SCRAP` → `victory_type: "scrapped"`, both winner columns nil;
  `OutcomeResolver` returns no winner and does **not** fall through to
  inference, which would otherwise invent a score-leader winner for a game
  nobody won.
- **irrelevance** never reaches `game_ended` — it takes a major out of victory
  contention and out of the session without ending the game. It is a
  `KeyMomentDetector#players_declared_irrelevant` moment (weight 3, anchors its
  own chronicle entry) plus a `PlayerTimeline#irrelevance(civ)` record, not an
  outcome.

**None of the three example logs carries `game_ended` or any `mp_*` record** —
all are one human against bots — so every branch above ships tested only
against synthetic fixtures.

Iterations: `ImportGame` (`game_ended` + `VICTORY_SCRAP`); `OutcomeResolver`
(`source: :logged`); `KeyMomentDetector` + `PlayerTimeline` + `ChronicleSpine`
for irrelevance.

## 1. Population counted per city

**Implemented 2026-09-07** — `docs/plan.md`, *"population counted per
city"*. The plan below is as written; it shipped in four cycles with no
design change.

### Why

`Demographics` (`app/models/demographics.rb`) says so itself:

> Per-city sizes are not carried in the snapshots, so the empire's citizens
> are spread evenly over its cities before the curve is applied.

That premise is now false. And because `x**2.8` is convex, spreading evenly is
not a rounding error — Jensen's inequality makes it a systematic understatement
that varies with the shape of the empire:

| turn 180 | cities | avg-based souls | per-city souls | ratio |
|---|---|---|---|---|
| India | 4 | 54,702,000 | 82,117,000 | 1.50 |
| Netherlands | 9 | 16,595,000 | 26,819,000 | 1.62 |
| Zimbabwe | 12 | 5,785,000 | 8,614,000 | 1.49 |
| England | 3 | 4,856,000 | 6,559,000 | 1.35 |
| Iroquois | 7 | 3,746,000 | 4,468,000 | **1.19** |
| Tibet | 18 | 2,788,000 | 5,021,000 | **1.80** |

The spread runs 1.19×–2.66× across the game, and **it reorders the standings**:
by the current formula Iroquois out-populates Tibet at turn 180; counted city by
city, Tibet is larger. The chronicle is told `souls` is *"a real population
figure and may be given as one"*, so this is wrong prose, not just a wrong
number.

### The join is exact

Checked over all 1,104 `(turn, civ)` pairs in india-diplo:

- `sum(city_snapshot.population) == snapshot.population` on 1,082
- `count(city_snapshot) == snapshot.cities` on 1,082
- the 22 misses are all on turns 29, 78, 146 and 181 — the four reload turns —
  and are off by **exactly 2×**, i.e. duplication, not loss

`ImportGame` dedups those across sessions on the payload digest, but the
projection must still group defensively by `(turn, civ, city)`; `CongressTimeline`
already sets the precedent (`keeps one host entry per turn when a turn was
snapshotted twice`).

### Design

- New projection `CityCensus` (`app/projections/city_census.rb`), `extend
  Projection`: `sizes(civ, turn)` → the deduplicated list of city populations
  at the nearest `city_snapshot` turn `<= turn`; `applicable?` false when the
  log has no `city_snapshot` at all.
- `Demographics` gains a second constructor path — `Demographics.new(city_sizes:
  [18, 7, 4])` summing `SOULS_PER_CITIZEN * size**GROWTH_EXPONENT` per city —
  and keeps the existing `population:`/`cities:` path as the documented fallback
  for logs without city snapshots. The class comment stops apologising and
  starts naming which branch ran.
- `ChronicleDigest#with_souls` asks `CityCensus` first, falls back second, and
  records which it used (`"souls_source" => "cities" | "average"`) so the
  chronicler is never left guessing whether the figure is real.
- Per-city souls reach the digest too, at checkpoints only — the chronicle
  prompt already asks for *"a city of some tens of thousands"* and has never
  had the data to write it.

### Iterations

1. `CityCensus#sizes` — per civ, per turn, deduplicated; `applicable?`.
2. `Demographics.new(city_sizes:)` — the per-city sum. `test/models/demographics_test.rb`
   pins `population: 42, cities: 3 → 4_856_000`; the new path is a new test, the
   old one stays green.
3. `ChronicleDigest#with_souls` prefers the census, falls back, labels the source.
   `test/services/chronicle_digest_test.rb:30` pins the fallback.
4. Per-city souls at checkpoints + the prompt paragraph on reading them.

## 2. The wonder race

**Implemented 2026-09-07** — `docs/plan.md`, *"the wonder race"*, and
`docs/wonder-race.md` for the calibration. Shipped in five cycles: the
design below plus a `winner_finish` field (the closest the log comes to
seeing a Great Engineer instant-buy, which it cannot see directly) and a
`:close`/`:distant` scale on the loss instead of a flat spine weight of 4,
so a wonder the game still rated many turns off does not anchor an entry.

### Why, with the evidence

42 world wonders were completed in india-diplo. **Ten of them were contested,**
and the log says by whom and for how much:

| turn | wonder | won by | lost by | hammers sunk |
|---|---|---|---|---|
| 51 | Stonehenge | Tibet / Lhasa | Iroquois / Onondaga | 95 |
| 73 | Great Wall | England / London | Zimbabwe, Iroquois | 96, 72 |
| 115 | Machu Picchu | Zimbabwe | Tibet / Lhasa, India / Vijayanagara | 142, 90 |
| 143 | Himeji Castle | Iroquois / Onondaga | Zimbabwe / Great Zimbabwe | 210 |
| **158** | **Louvre** | **Netherlands / Amsterdam** | **England / London** | **425** |
| 163 | Red Fort | India / Vijayanagara | Iroquois, Zimbabwe | 268, 142 |

England spending 425 hammers over ten turns and losing the Louvre is a
chronicle entry that no existing projection can see.

### What the data supports, and what it does not

- `city_snapshot` carries `producing`, `producing_kind`, `production_stored`,
  `production_turns_left`, every city, every turn. A race is reconstructed by
  scanning `producing == <wonder>` for turns `<= completion`.
- There is **no** "production started" event, **no** wonder flag on
  `city_snapshot`, and **no** gold-compensation record. The refund is a rule of
  the game, not a fact in the log — the digest reports `production_invested` and
  the prompt says what becomes of it. Never invent the gold figure.
- The loser's investment is their **last observed** `production_stored`, up to
  one turn stale. Report it as observed, with `last_seen_turn`.
- Distinguish **losing** a race from **abandoning** one: the item vanishing from
  `producing` on the completion turn or the one after is a loss; vanishing
  earlier is a switch of plans, and the difference is the whole point.

### Identifying a wonder before it is finished

`producing` is a bare `BUILDING_*` id. A wonder nobody completed never appears
in a `building_constructed` record, so in-game observation alone under-reports.

Extend `LekmodIdsExtractor` (`app/services/lekmod_ids_extractor.rb`) to the
`Buildings` table: `MaxGlobalInstances = 1` → world wonder, `MaxTeamInstances`
→ team, `MaxPlayerInstances` → national — the same rule the logger uses in
`adapter.lua:61-72`. Output `db/lekmod/<version>/buildings.yml`, optional like
`ids.yml` and `units.yml`, falling back to wonders observed in this game when
absent. This also gives every `BUILDING_*` in the digest a display name, which
nothing has today.

### Design

- `WonderRaces` (`app/projections/wonder_races.rb`) → one record per contested
  wonder: `{wonder, completed_turn, winner: {civ, city}, contenders: [{civ, city,
  first_seen_turn, last_seen_turn, turns_building, production_invested,
  outcome: :lost | :abandoned}]}`. Uncontested completions are not races and
  produce nothing.
- `KeyMomentDetector#wonder_races_lost`, and a `wonder_race` moment when a
  second builder joins one already under way. Leave room on the race record for
  a `rival_observed` field: tranche 2 fills it from `spy_moved`, since whether
  the loser had a spy in the winner's city separates losing a race you could
  see from losing one you could not.
- `ChronicleSpine`: `wonder_race_lost` weighted **4** (above `world_wonder`'s 3
  — the loss is the story, the win already has a moment). A race *start* is
  weight 1, light: 42 wonders × contenders would otherwise flood the spine.

### Iterations

1. `LekmodIdsExtractor` over `Buildings`; `buildings.yml`; wonder classification
   with the observed-wonders fallback.
2. `WonderRaces` — contenders, investment, `:lost` vs `:abandoned`.
3. `KeyMomentDetector#wonder_races_lost` + the race-start moment.
4. `ChronicleSpine` weights; digest section; prompt.

## 3. What a city was worth when it changed hands

### Why

`ChronicleSpine::WEIGHTS` gives `city_captured` a flat **4**. In india-diplo
that scores these two the same:

| | Onondaga (t152) | Buffalo Creek (t155) |
|---|---|---|
| population | 18 | 7 |
| buildings | 18 | 9 |
| science / turn | 54.2 | 12.5 |
| production / turn | 50.8 | 22.0 |
| capital | **yes** | no |

One is the Iroquois capital and a fifth of their science; the other is a border
town. The correction is a *share*, not a *classification*: a taxonomy of
tech-city / production-city mostly re-discovers that the capital wins, whereas
"this city was 31% of its owner's science" is directly what a capture or a loss
cost.

**This belongs in the analysis at least as much as in the chronicle**, and it
obsoletes a paragraph the prompt currently relies on
(`app/prompts/analyze_game.md`, the war-cost section):

> Population is the best measure of that potential the data offers, and it comes
> as an empire-wide figure at each checkpoint rather than per city, so read a
> capture's cost from where the owner's `population` line bends around that turn.

Reading a bend in an empire-wide curve was a workaround for data that now
exists. The paragraph must be rewritten, not merely supplemented.

### The asymmetry, and how much of it is measurable

The prompt already states the core rule — *"weigh the loss by the city as it
stood before the capture, not by what the captor gained - much of the difference
is destroyed rather than transferred"* — and it stays. What it lacks is the
mechanism, and the mechanism is now partly observable rather than only assertable:

| Fact | Where it comes from |
|---|---|
| the city as it stood before | last `city_snapshot` before the capture turn |
| what the captor actually got | first `city_snapshot` after — population and `buildings` both drop |
| conquest vs. cession | `city_captured.conquest`; **false** means handed over by diplomacy, and then nothing is destroyed — the one case where gain equals loss |
| the unrest that follows | `city_snapshot.resistance_turns`, `occupied`, `puppet`, `razing`, observed turn by turn |
| longer for a bigger city | population at capture against the observed resistance length |
| shorter with tourism dominance | `snapshot.influence[]` — the captor's `level` over the former owner on the capture turn |

So the resistance rule is stated as a rule in the prompt **and** carried as
observed turns in the digest, and the two can disagree in a way that is
informative rather than embarrassing.

**Honest limit on the evidence:** india-diplo has exactly two captures, both
`conquest: true`, and they went opposite ways. **Buffalo Creek** (pop 7, a
border town) was occupied and razed — `occupied` and `razing` on both its
post-capture snapshots, gone from the log by turn 157. **Onondaga** (pop 18, the
Iroquois capital) was puppeted on the capture turn and **held to the end of the
game** — 32 turns, never occupied, never razed, population recovering 9 → 17. So
one real conquered city *is* held through its resistance and observed turn by
turn; `occupied`/`razing` are exercised only by the town that was thrown away.
Baseline resistance is the post-capture population in turns, which makes both
captures a measured point for the tourism-shortening rule rather than none:
Onondaga fell to pop 9 and resisted **3** (`resistance_turns` 3 → 2 → 1 → 0 over
turns 153–156), Buffalo Creek fell to pop 2 and resisted **1**. Both captors
were India, whose tourism over the Iroquois read 66 points and
`INFLUENCE_TREND_RISING` on the capture turn. Still missing: a capture by a civ
with no tourism lead, to tell that roughly two-thirds cut apart from era or
buildings — and the named `level` the rule keys on, which is
`INFLUENCE_LEVEL_UNKNOWN` for every pair in this log. babylon-domination's eight
captures carry no `city_snapshot` at all.

### Design

- `CityValue` (`app/projections/city_value.rb`): for a `(city, turn)`, its
  share of its owner's empire at that turn — `population_share`,
  `production_share`, `science_share`, `gold_share`, `culture_share`,
  `faith_share`, `buildings_share`, plus `rank` among the owner's cities by
  each. Shares are taken over the owner's own `city_snapshot` rows, never over
  `snapshot` yields, which include non-city sources.
- Reported at capture, at loss, at razing, and at checkpoints for the standing
  empire. `PlayerTimeline#cities` gains the valuation on `:captured` / `:lost`.
- `ChronicleSpine` scales the `city_captured` weight by the share taken: a
  capital or a city above roughly a fifth of its owner's yields keeps 4+, a
  freshly founded border town drops to 2. The exact break points come from the
  two real captures plus babylon-domination's eight, and are declared
  uncalibrated in the doc — the same honesty `docs/buffer-city.md` uses for its
  17 and 6.
- A by-product, free and worth having: a city whose share of one yield far
  exceeds its share of population is *specialised*, and that is one number per
  yield rather than a taxonomy.

### Iterations

1. `CityValue#at(city, turn)` — shares and ranks, dedup-safe.
2. Valuation attached to captures, losses and razings in `PlayerTimeline`:
   before/after population and buildings, `conquest`, observed
   `resistance_turns`, and the captor's influence level over the former owner.
3. `ChronicleSpine` weight scaling.
4. Digest section + **both** prompts. `analyze_game.md`: replace the
   "read the bend in the population line" paragraph, keep the
   gain-is-less-than-loss rule, add the cession exception and the resistance
   mechanism. `chronicle_game.md`: how heavily to weigh a city changing hands.

---

# Tranche 2 and 3 — why in this order

**4. City-state influence.** India ended allied to **10 of 11** city-states and
won on diplomacy.

**Build this to measure a contest, not a ramp.** India faced one human's worth
of opposition and five bots' worth of none, and among humans a diplomatic
victory is rare precisely because it is answerable: rivals flip their spies to
counter-intelligence, outbid with gold, run the quests, or take the city-states
outright to shrink the vote pool. The log sees the first and the last of those
four and is blind to the middle two — gold gifts are not logged at all
(`CvDeal` is unreachable) and quests are not logged either. That asymmetry must
be stated in the digest, or the analysis will credit every aggressor and never
see a defence. A projection tuned on this one game will describe an uncontested
climb and have no vocabulary for the normal case.

Of the two counters the log can see, one is trivial to detect and neither is
tested. **Counter-intelligence** reads off `spy_moved` (see below).
**Conquering a city-state to shrink the vote pool** is a `city_captured` whose
`old_owner` is in `game.city_state_civs`, and it should show up twice — as a
capture, and as `votes_needed_for_diplo_victory` moving in `congress_snapshot`.
**No city-state was taken in india-diplo**, and the threshold sat at 34 from
turn 101 to the end, so the detector has never fired. Build it and say it is
unexercised.

**Allies are not only a victory condition**, and the plan should not treat them
as one. They are, in rough order of how measurable each is:

- **Votes**, exactly. `congress_snapshot` carries `votes` and `core_votes` per
  civ, and the difference is what the city-states are paying. At turn 167 India
  held **28 votes of which 4 were core** — 24 bought — against everyone else's
  0 to 2. `CongressTimeline` already reads this record and takes only the total;
  splitting it is nearly free and is the single clearest number in the game.
  Votes also elect the host and carry ordinary resolutions, which matter long
  before anyone is near a diplomatic win.
- **Bonuses**, from the trait in `session_started.city_states[]` — and at two
  strengths, since a friend already pays something and an ally pays more. The
  `level` field in `city_state_snapshot.relations[]` separates them.
- **A buffer**, slightly worse than a buffer city of one's own but on the same
  ground. This one reuses code rather than adding any:
  `CapitalProximity#city_state_capitals` already holds every city-state's plot,
  and `BufferCities`' corridor test (lateral offset plus betweenness) already
  decides whether a city sits in the corridor between two capitals. Running
  that test with a city-state capital as
  the corridor city, weighted by whether the alliance was held at the time,
  answers "who covered that approach" for allies as it already does for cities.

`city_state_snapshot` carries the full matrix — influence,
`per_turn` rate, level, `protected`, `ally` — and `session_started.city_states[]`
carries trait, LEKMOD personality and unique unit. Today `PlayerTimeline` sees
only the threshold-crossing events, so it can say *that* Ljubljana flipped eight
times and never *how close* anyone was. The snapshot is sparse (238 records over
87 turns, emitted on level change plus a per-session baseline) but lossless: the
curve between two records is read back from `per_turn`.

**Espionage belongs in this feature, and not as a footnote.** The mission
breakdown is the sharpest single split in the whole log:

| civ | `rigging_election` | `gathering_intel` |
|---|---|---|
| **India** | **23** | 0 |
| England | 0 | 10 |
| Iroquois | 0 | 6 |
| Tibet | 0 | 6 |
| Netherlands | 0 | 4 |
| Zimbabwe | 0 | 4 |

Every other civ pointed its spies at technology. India pointed all of its at
city-states, and nobody else rigged a single election. The targets line up with
the influence curve: Ljubljana rigged 8 times went 20 → 247, Montevideo 6 times
56 → 206, Zurich 5 times 20 → 171, Tashkent 3 times 20 → 239.

So in *this* game the diplomatic victory was **bought with spies, with caravans
as a supporting flow** — not the other way round. A projection that reads
city-state influence without reading `spy_mission_completed` beside it will show
the influence climbing and have nothing to attribute it to.

### But election-rigging is the narrow case, not the usual one

Rigging is what India did because nobody stopped it. The ordinary uses of a spy
are stealing technology and guarding against the theft, and the log distinguishes
every one of them from the fields it already carries:

| use | how it reads | seen here |
|---|---|---|
| steal a technology | `spy_mission_completed`, `state: gathering_intel`, in a major's city | 30, every civ but India |
| rig an election | same event, `state: rigging_election`, in a city-state | 23, India only |
| guard your own cities | `spy_moved` where `city_civ == civ`; `state: counter_intel` | 6 sent home, 1 explicit |
| watch before acting | `state: surveillance` | 1 |

`city_civ` against `game.players` splits target types in one line, and the split
per civ is stark: India 23/23 on city-states, every other civ 100% on majors.
**Which technology was stolen is not readable** — no API exposes it. The
logger's suggested reconstruction (a `tech_researched` that does not match the
thief's `researching` on the turn a `gathering_intel` mission completed) is
recorded in the plan as a possibility and is **untested**; it must not ship as a
fact.

### Two links worth building that this game could not show

**A spy in a capital is intelligence about production, and that ties back to the
wonder race.** The log is omniscient — `city_snapshot.producing` shows what
every city builds — but the *players* were not, and the difference is analysable.
Whether a civ had a spy sitting in the capital that beat it to a wonder is the
difference between losing a race it could see and losing one it could not. That
join costs nothing: `spy_moved` gives the city and the turn, `WonderRaces` gives
the contenders and the window. It is the sharpest available answer to "did they
know?", and it belongs in tranche 1's wonder feature as a field that tranche 2
fills in.

**A spy also gives vision, and vision is a weapon.** A spy in a city reveals it
and the hexes around it, which is what lets artillery, bombers and missiles fire
without a spotter, and what makes a paradrop or an XCOM drop possible. `paradrop`
is its own event type and carries a plot, so a drop into a city a spy occupied is
a direct join. **India-diplo contains zero paradrops**, so this is specified and
unverified — it waits for a war log, and the doc says so rather than pretending
the mechanism was checked.

**5. Diplomatic ties.** `friendship_*`, `defensive_pact_*`, `open_borders_*`,
`embassy_*`, `trade_agreement_*` are exact, cheap and read by nothing; the
analysis has no diplomacy beyond `war_declared` / `peace_made`. Precedes deals
because it is fact rather than inference.

**6. Trade routes.** 118 established, both sides' gold, science, food,
production, tourism and religious pressure.

**The first question is where the caravan went, and the log answers it cleanly.**
Measured on india-diplo, the split is exact and three-way:

| destination | n | `type` | what it is |
|---|---|---|---|
| own empire | 16 | `food` (14), `production` (2) | no gold at all; feeds a city's growth or its hammers, and stays inside your borders where a barbarian cannot reach it |
| a city-state | 54 | `international` | gold, plus influence and (with `POLICY_MERCHANT_CONFEDERACY`) food and production; the exposed one |
| another major | 48 | `international` | gold both ways, and science, tourism and religious pressure in both directions |

`type` and `to_civ` decide it with no inference: `food`/`production` always have
`to_civ == civ`, `international` never does. A civ running internal caravans is
buying development and safety; one running them abroad is buying gold and
accepting risk — and that is a strategic posture the analysis cannot currently
see at all.

**The city-state route is worth more than its gold.** India adopted
`POLICY_MERCHANT_CONFEDERACY` on turn 81 (LEKMOD: *"+2 production, +2 food and
+1 Influence per turn from trade routes to City States"*) and nobody else took
it. Cross-referencing `policy_adopted` against CS-bound routes costs a lookup
and changes what a caravan means for that civ.

**Count live routes, never establishments.** India established 22 routes over
the game and never ran anything like that many: concurrently it held **4–5 from
turn 100 to turn 176**, then opened eight in the last six turns — seven of them
to city-states — peaking at **12 on turn 183, the winning turn**. The
establishment count and the concurrency curve are different facts and only the
second one describes the empire.

### Counting a live route is the hard part of this feature

A route has no id in the log, so its lifetime must be reconstructed, and the
reconstruction is lossy in two measured ways:

- **38 of 118 routes have no recorded end** (81 `trade_route_ended` against 118
  established, and the join consumes one end per start). Those fall back to
  `turn + turns_left`, which is the expiry the record itself states.
- **The `(civ, from_city, to_city, to_civ)` join is wrong sometimes.** A greedy
  first-end-after-start match paired India's Mumbai→Delhi food route established
  on turn 47 with an end on turn 183 — a 136-turn route whose own `turns_left`
  said 17. Re-established pairs are common and the key cannot tell two
  instances apart.

Rule for the projection: a route is live from `turn` to
`min(matched_end, turn + turns_left)`, and the concurrency series carries a
flag when the matched end was discarded in favour of the stated expiry. The
numbers above use that rule; they still carry error bars and the doc says so.

Caveats to document:

- **The influence a CS route grants is not in the route record.** It arrives
  only as movement in `city_state_snapshot.per_turn`, so the link is stated and
  the effect is read from the influence curve, never added up from the routes.
- **Quests are not logged at all** (`MinorCivQuestTypes` is a C++ enum with no
  database table — the one item the logger deliberately left open), so a caravan
  sent to fulfil a quest is indistinguishable from any other. Say so rather than
  guessing.
- `trade_route_ended` carries no reason and no values; joins on
  `(civ, from_city, to_city, to_civ)` are ambiguous when a pair is
  re-established, which happens.
- `trade_route_plundered` names only the plunderer (2 of 3 were barbarians) —
  no victim, no route, no gold. It can be tied to an ending only by sharing a turn.
- 118 established against 81 ended: 37 routes were still live at the end.

It also shows a civ *feeding a rival's science* — Delhi→Amsterdam gave the
Netherlands 13 beakers a turn and India none — and carries the tourism and
pressure vectors the cultural and religious stories need.

**7. Research beelines, and the rush they add up to.** `researching` +
`research_turns_left` on every snapshot, dropped today by `SNAPSHOT_METRICS`.
The one field in the log that shows *intent* rather than outcome.

On its own it says what a civ was aiming at this turn. Joined with the tech
count it says what it was aiming at for the last thirty — a **rush**, which is
a marker technology reached with suspiciously few techs behind it:

| target | techs, marker included | marker |
|---|---|---|
| crossbows | 15–17 | Machinery |
| universities | 16–19 | Education |
| frigates | 26–29 | Navigation |
| public schools | 32–34 | Scientific Theory |
| artillery cavalry | 34–36 | Dynamite |
| research labs | 42 | Plastics |
| planes | 46–47 | Flight |
| battleships | 49–50 | Electronics |
| landships | 51–52 | Combustion |
| the Internet | 57–61 | The Internet |
| stealth bombers | 63–65 | Stealth |

**Checked against india-diplo, and it discriminates** — which is the property
that makes a heuristic worth shipping. Only two fire:

- **India, Education as tech #18 on turn 74** — inside the 16–19 band while
  England took it at #24, Tibet #21, the Netherlands #29. India was the runaway
  science civ and this is the turn it committed.
- **England, Navigation as tech #27 on turn 118** — inside 26–29, against the
  Netherlands' #31 and India's #47. England built the Great Lighthouse and the
  Arsenal of Venice; the frigate read fits.

Nothing else lands in a band. Machinery came at #19/#26 (no crossbow rush),
Dynamite at #54 for India alone (ordinary progression, not a rush).

Three things to settle before implementing:

1. **The two tech counts disagree by one or two.** Counting `tech_researched`
   plus `tech_from_ruins` gives India 18 at Education; `snapshot.techs` on turn
   74 gives 19. Snapshots are stamped at the player's turn start, so a tech
   taken during that turn may or may not be in the count. Report both; pick one
   as the band's basis and say which in the doc. India sits at the very top of
   16–19 under one and inside it under the other, so it is not academic.
2. **City-states appear in `tech_researched.civs`.** Harappa, Zurich,
   Montevideo and the rest all "research" the same tech on the same turn. Every
   civ loop here must be restricted to `game.players`, or every rush fires
   eleven extra times.
3. **The marker ids need checking against the ruleset, not guessed.**
   `TECH_PLASTIC` exists in this log, `TECH_PLASTICS` does not; `TECH_STEALTH`
   appears nowhere in the 70 techs the game reached. Resolve all eleven through
   `LekmodIdsExtractor` over the `Technologies` table — the same pass that
   tranche 1 adds for `Buildings`.

The bands are the user's own calibration from play, not a measurement, and the
doc says so — the same footing as `docs/buffer-city.md`'s 17 and 6. A rush is a
`KeyMomentDetector` moment carrying the target, the marker turn, the tech count
and the distance to the band, so a near-miss reads as a near-miss.

**8. Yield attribution.** `yield_sources` splits science, faith, culture and
tourism into cities / city-states / happiness / religion / research agreements /
deficit. Turns a curve into a mechanism. Cheap — it rides the snapshot read that
already happens. Note the two DLL paths disagree on vocabulary (`city_states` in
science is `minor_civs` in culture, `other_players` means research agreements)
and the parts do not sum to the total under golden age, anarchy, or a science
deficit.

**9. Religion and conversion.** 644 `city_converted`, plus `from_pressure` /
`to_pressure` on trade routes, plus `religion` and `religion_followers` per
city. A whole axis of the game that is currently invisible.

**10. Deal reconstruction, labelled as inference.** `CvDeal` is unreachable from
Lua, so gold, gold-per-turn and city trades cannot be logged at all. What can:
`snapshot.resources[]` gives `total`/`used`/`import`/`export` per strategic and
luxury resource, and *a luxury appearing in one player's imports and another's
exports on the same turn is a deal*. The projection matches import/export pairs
between majors; an import with no major exporter is a city-state ally's gift,
which is itself a useful signal. The digest and the prompt must both say this is
reconstructed, and must say what stays invisible — the price, the gold, the
duration.

---

## Cross-cutting

**Digest size is now unguarded and about to be pressed.** The digest is ~55k
input tokens today; timelines, key moments and resolutions are unbounded full
lists, and this plan adds six sections. `test/services/digest_builder_cost_test.rb`
bounds *work* (two log passes, one construction per projection) but nothing
bounds *size*. Add a size assertion to that test in tranche 1, before the growth
arrives rather than after.

**Every new projection must be added to `DigestBuilderCostTest::PROJECTIONS`**
and must read through `game.event_log`, never its own query — the two-pass
budget is what keeps 29k city snapshots from being walked once per projection.

**Nothing per-city-per-turn reaches the digest.** `CHECKPOINT_INTERVAL = 25` and
`sample_checkpoints` are the existing pattern; city-level detail goes to the
digest only at checkpoints, at captures, and at race conclusions.

**Old logs must stay analysable.** Two of the three example logs have no
`city_snapshot`. `applicable: false` with a `reason:` everywhere, and the
chronicle's souls fall back to the averaged formula with the source labelled.

---

## Verification

Per iteration: `bin/rails test` green, failing tests first and reviewed before
implementation.

End to end, once tranche 1 lands:

```sh
bin/civ import examples/india-diplo.jsonl --name "India Diplo"
bin/rails runner 'pp DigestBuilder.new(Game.last).call.slice(:outcome, :wonder_races)'
bin/civ chronicle <id> --lang pl
bin/civ import examples/babylon-domination.jsonl   # the no-city_snapshot regression
bin/civ analyze <babylon id>
```

What to check by hand:

- the outcome reads `VICTORY_DIPLOMATIC` / India / turn 183 with
  `source: :logged`, without `--winner`
- Tibet out-populates the Iroquois at turn 180 in the chronicle digest, and
  `souls_source` says `cities`
- the ten contested wonders appear, the Louvre among them with England's 425
  hammers, and the 32 uncontested ones do not
- Onondaga and Buffalo Creek carry visibly different capture weights, and the
  analysis report reasons about the capture from the city's share rather than
  from a bend in the population curve
- babylon-domination still produces a full analysis, with the new sections
  marked inapplicable rather than empty or wrong
- the digest size assertion holds on india-diplo, which is the largest log

Both `docs/plan.md` (a `## Plan:` section per feature, in house style) and a
per-feature `docs/*.md` for anything with a rule that needs calibrating —
the city-value break points above all.
