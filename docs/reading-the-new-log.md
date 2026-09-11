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
4. Espionage — the shared primitive, and it retro-fills tranche 1's
   `rival_observed` (promoted from a paragraph inside 5; see the section for why)
5. City-state influence and the vote (the india game is decided by exactly
   this, and by nothing else that is logged)
6. Diplomatic ties (logged, exact, read by nothing)
7. Trade routes

**Tranche 3 — intent and belief**
8. Research beelines (`researching`)
9. Yield attribution (`yield_sources`)
10. Religion and conversion
11. Resource-flow deal reconstruction (explicitly inferred)

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

**Implemented 2026-09-09** — `docs/plan.md`, *"what a city was worth when
it changed hands"*, and `docs/city-value.md` for the calibration. Shipped
in four cycles as the design below, scaling the `city_captured` weight on
population share plus the `capital` flag the capture event already carries.

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

# Tranche 2

Ordered so that the shared primitive is built before the three features that
join against it. Espionage was a paragraph inside city-state influence in the
first draft of this plan; measuring it moved it to the front, for the reason
the next section opens with.

## 4. Espionage — the primitive that four features share

### Why it is its own feature, and why it comes first

Espionage has no separate slot in the first draft because it looked like a
sub-part of the diplomatic game. It is not. A spy is a **position on the map
held over a span of turns**, and four unrelated questions are answered by
joining against that position:

| question | feature | needs |
|---|---|---|
| did the loser of a wonder race know? | tranche 1, `rival_observed` | tenure in the winner's city |
| what moved a city-state's influence? | 5 | rig missions and coups, per city-state |
| was an empire garrisoned against theft? | 4 itself | where spies died, and which spies never appear |
| could that drop have been made blind? | later, war logs | tenure adjacent to a plot |

Building it inside feature 5 would bury the tenure reconstruction inside a
city-state projection and leave the wonder-race join with nowhere to live.
`WonderRaces` already carries `rival_observed: nil`, waiting for it
(`app/projections/wonder_races.rb`).

### The primitive: spy tenure

The log names every spy (`TXT_KEY_SPY_NAME_INDIA_7`) and the name is stable
across events, so a spy is trackable. The event types that carry a location:

- `spy_moved` — `{civ, spy, city, city_civ, state, x, y}`, 34 records, 32 of
  them `travelling`. This is the **order to go**, not the arrival.
- `spy_mission_completed` — the same fields, 53 records. This is **proof of
  presence**, and of established surveillance (below).
- `spy_surveillance_established` — `{civ, spy, city, city_civ}`, added upstream
  in *"Stop trusting a progress fall on its own to mean a mission finished"*.
  Fires the turn the spy's `HasEstablishedSurveillance` flag goes true, one
  per posting. `examples/india-diplo.jsonl` predates it and carries none;
  every later log does.
- `spy_created` and `spy_killed` — no location in india-diplo (0 of 18, 0 of
  9), given `city`/`city_civ` by that same upstream commit.

A tenure is a maximal run of sightings of one spy in one city. Reconstructed
over india-diplo that gives **24 spies with a location and 46 tenures**, and
they read cleanly — `IROQUOIS_6` sat in London from turn 118 to at least 173,
completing four intel missions; `ENGLAND_1` toured Amsterdam, Lhasa and Mumbai
before going home to London on counter-intelligence at 156.

The run ends where the next sighting of that spy is in another city, where the
spy dies, and where a city taken or razed throws it out (`spy_evicted`, added
upstream once this projection was built — see `docs/espionage.md`). An open run
is held to the end of the log.

### What surveillance actually grants — checked in the DLL, not assumed

The whole feature rests on a spy in a city telling its owner what that city is
building. That is a rule of the game, not a fact in the log, so it was checked
against `LEKMOD_DLL/CvGameCoreDLL_Expansion2/`:

- `CvPlot.cpp:1888` — a plot grants
  `changeAdjacentSight(..., ESPIONAGE_SURVEILLANCE_SIGHT_RANGE, ...)` to every
  major with `HasEstablishedSurveillanceInCity`. That is the map half: the
  vision that lets artillery and bombers fire without a spotter, and a paradrop
  pick a target.
- **The intelligence half is larger than the map half, and it is not a banner.**
  A spy with surveillance opens the target's **full city screen, read-only** —
  every yield, every detail, and the **whole production queue**, exactly as its
  owner sees it (the user's own knowledge of the game; it is a UI affordance,
  not a DLL constant, so it is recorded here as a played rule rather than a
  cited line). The consequence for the wonder race is sharper than "they saw a
  wonder being built": the observer saw **what was queued behind it too**, so
  `city_snapshot.producing` is the *floor* of what a watcher knew, never the
  ceiling. An analysis may say a contender could see the rival's plan, not
  merely its current item.
- `CvEspionageClasses.cpp:1795` — surveillance counts as established when the
  spy's state is `SURVEILLANCE` **and** the goal is reached, **or** whenever the
  state is `GATHERING_INTEL`, `RIG_ELECTION` or `SCHMOOZE`.
- `CvEspionageClasses.cpp:1702` — establishing it takes a base **3 turns** after
  arrival, shortened by `GetInfluenceSurveillanceTime` against the target — the
  same tourism mechanic that shortens occupation resistance in tranche 1.

Dating rules fall straight out of that, in descending order of what they may be
used for. `docs/espionage.md` carries the full version with the DLL constants;
in short:

- **Logged** — a `spy_surveillance_established` in city C on turn T. The turn
  vision opened, stated outright. This is `visible_from_turn` wherever the
  event is present, which is every log after the upstream fix.
- **Computed** — `posting + 1 + surveillance_time` (`surveillance_time` is 3,
  or 1 with a tourism lead over the target). The fallback for india-diplo and
  the two older logs, exact where the posting survived.
- **Certain floor** — a `spy_mission_completed` in city C on turn T proves
  surveillance was live in C on T, because the mission states imply it. Used
  when neither of the above is available; `visible_from_turn` is then a lower
  bound with `visible_from_turn_bounded: true`.
- **Never** — a `spy_moved` turn on its own. It is the order to go, not the
  arrival.

**The log never shows that a player looked.** It shows the opportunity to
know. Every field here is named for opportunity — `observed_by`, not
`known_by` — and both prompts must be told the difference, or the analysis will
narrate a decision the player may have made with their eyes shut.

### Join A: the wonder race, and the shape the data actually has

This is the join the plan was missing, and running it changes what it should
look for.

Over india-diplo's ten contested wonders and thirteen contender rows, a
contender held a spy in the winner's city **exactly once** — and it is the
biggest wonder loss in the game:

```
t148  London starts the Louvre                    0 stored, 12 turns left
t148  England creates spy ENGLAND_6
t152  ENGLAND_6's surveillance completes in AMSTERDAM   (t148 + 1 + 3)
t154  Amsterdam appears building the Louvre       0 stored, 4 turns left
t157  Amsterdam 469 stored, 1 left | London 425 stored, 2 left
t158  Netherlands completes the Louvre. England loses by one turn, 425 sunk.
```

England's spy was established in Amsterdam **two turns before Amsterdam
started the wonder** — a computed date, not a guess: created on 148, `1 + 3`
puts surveillance live on 152 (a post-fix log would state that turn outright
in a `spy_surveillance_established`) — and watched it go from 0 to 469 hammers.
London's rate
over the whole build: 52, 44, 44, 46, 46, 46, 47, 47, 53. **Flat.** England had
the intelligence, did not accelerate, did not stop, and lost by a turn.

Three things follow for the design:

1. **The naive window test is the wrong test.** "Did the contender hold a spy
   at any point during the race" would also fire on a spy that arrived after
   the race was decided. What matters is vision **while a decision was still
   available** — while the contender was still building and the wonder was not
   yet finished.
2. **The decision the spy informs is usually not the start.** England committed
   on 148 and its spy did not exist until 148. Vision cannot explain the start;
   it can only explain continuing or quitting. So the field to carry is not one
   boolean but the span: `observed_from_turn` and `observed_turns` — how many
   turns of its own build the contender could see the winner's.
3. **The response is measurable.** `production_stored` per turn gives a rate,
   so the rate before `observed_from_turn` against the rate after is a direct
   test of the two cases:

| pattern | reading | seen in india-diplo |
|---|---|---|
| observed, rate rises, still lost | tried to outrun it | 0 |
| observed, rate rises, won | the spy paid for itself | 0 |
| observed, `:abandoned` soon after | read the board, cut the losses | 0 |
| **observed, rate flat, lost** | **had the intelligence and pressed on** | **1 — the Louvre** |
| not observed, lost | lost a race it could not see | 12 |

Four of five rows are empty. **The classifier ships with one real instance and
four unexercised branches**, and the doc says so — the same footing as
`winner_finish`'s `:ahead_of_estimate` in `docs/wonder-race.md`. It is worth
shipping anyway because the one instance is the sharpest sentence available
about the largest wonder loss in the log, and because the empty branches are
the ones a game between humans will fill.

One nuance to encode rather than smooth over: a **third party** can hold the
spy. Tibet had a spy in Amsterdam through the Alhambra race that Zimbabwe lost.
That is not the same fact and must not be scored as one — `observed_by` is a
list of civs with the contender flagged, not a boolean on the contender.

### Join B: what actually moved city-state influence

Feature 5 depends on this and the measurement is in the next section, because
the finding belongs to the influence curve rather than to the spies.

### Join C: where spies die, and the counterspy the log never records

The first draft said counter-intelligence "reads off `spy_moved`", and that
nine kills in Delhi against a civ with no counter-intel posting proved a
**passive** defence of buildings and a tech lead. Checked against the DLL, that
reading is wrong — and the truth is a better finding.

`CvEspionageClasses.cpp:538-582`, under `ESPIONAGE_SYSTEM_REWORK` (defined at
`_Defines.h:1441`, so this is the live branch), resolves every completed
mission on a rank difference:

```
iSpyRankDifference = (attacker rank + 1) - iCounterspyRank + 1

with a counterspy:      >2 DETECTED   2|1 IDENTIFIED   0 SPOTTED   <0 KILLED
without a counterspy:   >3 UNDETECTED   3 DETECTED     2 IDENTIFIED
```

**There is no `KILLED` branch without a counterspy.** An attacking spy cannot
die in a city its owner's rival has not garrisoned. And the whole
`iCounterspyRank` computation — `BUILDING_CONSTABLE`,
`BUILDING_AUSTRALIA_CONSTABULARY` and `BUILDING_INTELLIGENCE_AGENCY`, each
worth `+1`, plus a flat `+1` — sits **inside** `if (pCityEspionage->HasCounterSpy())`.
So the buildings raise the **defending spy's effective rank** and are worth
exactly nothing on their own; without a garrison they neither kill nor slow.
(Note for the implementation: it is Constable and Intelligence Agency, *not*
Police Station, that carry the bonus in this branch.)

**So the nine kills in Delhi are proof of a counterspy the log never mentions.**
And the spy is identifiable:

| spy | created | events | ever located |
|---|---|---|---|
| `INDIA_7` | turn 94 | promoted `agent` t108, `special_agent` t109 | **never** |

India created six spies; five appear in a city and `INDIA_7` never does. It was
promoted twice in two turns — and `bCounterSpyUpgrade` is set precisely on
`SPOTTED` and `KILLED`, while the **first kill in the game is on turn 109**.
`INDIA_7` was sitting in Delhi the whole game, doing the thing that decided
every other civ's espionage, and the logger has no record of it.

Why india-diplo missed it: the logger emitted `spy_moved` only on a coordinate
change and `spy_mission_completed` only on a mission, and a counterspy placed
once and left alone did neither. **Reported upstream and fixed twice.** *"Give
a revived or homebound spy back its posting"* made `spy_moved` fire on the
transition into `counter_intel` with a city present; *"Say what a spy first
seen in a city is doing there"* put `state` on `spy_created`, so a garrison
that settled in before the session started is legible across a reload seam.
A garrison is now a tenure whose states include `counter_intel`, and
`Espionage#counterspies` reads it directly.

The read and the inference are chosen **per civ, not per log**. India-diplo
carries one counter-intelligence posting after all — England pulling
`ENGLAND_1` home to London on turn 156, which moved and so fired the ordinary
branch — while India's own garrison in the same log is invisible and inferred.

`Espionage#counterspies(civ)` — read from a `counter_intel` `spy_moved` where
one is present, otherwise inferred, never asserted, from three independent
signals that agree:

1. **a spy with no location** — created, sometimes promoted, never in a city;
2. **enemy spies dying in one of the civ's cities**, which the DLL says is
   impossible without a garrison there;
3. **promotions clustering with those deaths**, since the defender is what
   levels up on a kill.

The record carries `city` (the modal death site), `confidence` (how many of the
three signals fired) and `spy` when a never-located spy can be named. Signal 2
alone locates the garrison without naming it, which is the common case and
still worth having.

`Netherlands` has its own never-located spy (`NETHERLANDS_1`) with no deaths to
corroborate it — signal 1 alone, and the record must say so rather than promote
a guess to a garrison. `espionage-test.jsonl` produces one more of those,
Arabia's `ARABIA_8` on turn 186.

Signal 3 implies signal 2, so no separate signal list is needed on the record:
a `city` means deaths fired, a `spy` means the unplaced spy did, and confidence
3 means all three. India is the only civ in either game whose promotions fall
in a death turn.

**`spy_killed` carries no city**, so the death site is the spy's last known
tenure. Carry `turns_since_last_seen` (4 to 13 here) so a reader can discount
the inference.

The per-civ ledger that falls out of this is the honest version of the
"who defended themselves" question: India ran 23 missions, lost 0 spies, and
garrisoned its capital; England ran 10 and lost 4; Tibet ran 6 and lost 3.

### The coup — the one mission with no event at all

A spy in a city-state that already has an ally can **stage a coup**:
`CvEspionageClasses.cpp:2110`, *"if success, the spy's owner becomes the ally;
if failure, the spy dies."* It is the fast, risky alternative to rigging
elections for ten turns at a time, and it is the counter a rival uses against a
diplomatic runaway.

What the DLL says exactly, because the signature depends on it:

- `CanStageCoup` requires the city-state to **already have an ally** — a coup
  takes an alliance, it cannot create one from nothing.
- On success the couper's influence is **swapped** with the previous ally's,
  and every other major's is cut by
  `ESPIONAGE_COUP_OTHER_PLAYERS_INFLUENCE_DROP`. Not a flat grant — a swap.
- On failure the couper's influence is set to **−10** and the spy is killed
  (`ExtractSpyFromCity` then `SPY_STATE_DEAD`).

**The logger has no coup event.** Its six `spy_*` types are `created`, `moved`,
`mission_completed`, `killed`, `promoted`, `revived` — a coup is neither a move
nor a completed mission, so nothing fires. Like the counterspy, it must be
inferred, and unlike the counterspy its signature is loud:

- **failed** — a `spy_killed` whose last tenure is in a **city-state** (not a
  major), with that civ's influence there at or near **−10** on the next
  `city_state_snapshot`. Both halves are needed: the death alone could be a
  garrisoned major, and a −10 alone could be other things (India sat at −60 at
  Harappa on turn 35, long before any spy existed).
- **succeeded** — two civs' influence at one city-state **exchanging values**
  between consecutive snapshots, with an `city_state_ally_changed` on the same
  turn and no `rigging_election` mission to explain it.

**Zero coups in india-diplo** — all nine kills were in Delhi, a major's city,
and no influence pair ever swapped. Both detectors ship unexercised, and they
are the second-most likely thing a human-versus-human log will contain that
this one does not. They also matter to feature 5: a coup is a way an alliance
changes hands with **no logged cause**, so it is a candidate explanation for
part of that feature's residual, and must be named there as one.

### Join D: vision as a weapon

Specified, **unverified**, and it waits for a war log: a `paradrop` carries a
plot, and a drop onto a plot a spy's surveillance revealed is a direct join.
**India-diplo contains zero paradrops.** Build the join, ship it inapplicable,
say so — do not calibrate it against nothing.

### Design

- `Espionage` (`app/projections/espionage.rb`), `extend Projection`.
  `applicable?` false when the log carries no `spy_*` record at all — the two
  older example logs must be checked before this ships.
  - `tenures(civ = nil)` → `{civ, spy, agent, city, city_civ, from_turn,
    to_turn, until_turn, visible_from_turn, visible_from_turn_bounded, states,
    ended_by: :moved | :killed | :evicted | :log_end}`. `to_turn` is the last
    turn the log proves the spy stood there and `until_turn` is when it left,
    by the best evidence the log offers; `observers_of` joins against the
    second. A kill closes a tenure even when the record carries no city, and
    `spy_evicted` closes one at a city taken or razed. `visible_from_turn` is **read
    from `spy_surveillance_established`** where the log carries one; on a
    pre-fix log it is **computed** — `posting + 1 + (3, or 1 at
    INFLUENCE_LEVEL_FAMILIAR or better over the target)`, both DLL constants,
    measured at exactly +4 in 15 of 15 postings in `espionage-test.jsonl` —
    and falls back to a bounded floor only where the posting was lost. A
    `counter_intel` tenure is the exception at **+1** — a garrison needs no
    surveillance and never emits the event — and the state is read off the
    whole run, since it usually arrives a turn behind the order in a second
    `spy_moved` in the same city.
    Keyed on `(civ, agent)` where the logger writes an `agent`, and on
    `(civ, spy)` where it does not. The name is not an identity: the DLL
    redraws it on revival, so in an older log a `spy_revived` names a spy that
    never existed and opens a new tenure rather than continuing the dead one.
    A death ends a run wherever the agent turns up next, the city it died in
    included.
  - `observers_of(city, from_turn, to_turn)` → the tenures whose visible span
    overlaps the window, which is the whole of joins A and D.
  - `missions(civ = nil)` → `spy_mission_completed` split on the record's own
    `state`, which names the kind outright — `gathering_intel` is
    `:tech_theft`, `rigging_election` is `:election_rigging`. Every completion
    in both logs carries one, so nothing is inferred from whose city it was and
    no city-state list is needed. **On a pre-fix log, filtered first**: a completion 3–6 turns
    after that spy's posting or creation in the same city is the surveillance
    transition, not a mission — 23 of india-diplo's 53 are, and the per-civ
    split is mostly artifact without the filter (`docs/espionage.md`).
    Unanchored completions carry `anchored: false` and never reach a prompt as
    a bare count. A log carrying `spy_surveillance_established` has already had
    that transition split off upstream, so the filter is skipped and the count
    is taken straight. Never a
    stolen technology — no API exposes it, and the logger's suggested
    reconstruction is untested, built on the same corrupted event, and must not
    ship as fact.
  - `losses(civ = nil)` → one record per `spy_killed` with the host city (on
    the record in a post-fix log, the last sighting in india-diplo), the host's
    civ, `city_inferred` and `turns_since_last_seen`. A spy that was never
    located anywhere dies with no city rather than a guess.
  - `counterspies(civ)` → the garrisons: `{civ, city, spy, agent, from_turn,
    to_turn, until_turn, kills, inferred, confidence}`, the three turn fields
    meaning what they mean on a tenure. Read from a `spy_moved` into `counter_intel` where the
    log carries one — five in `espionage-test.jsonl`, none followed by a
    surveillance event or a completion. A garrison is a **span, not a
    standing state**: the Sioux moved one spy between two of their own cities
    four times in ten turns, so the record has to end when the spy leaves. In
    india-diplo inferred from the three agreeing signals and labelled inferred
    everywhere it surfaces.
  - `coups(civ = nil)` → `{civ, city_state, spy, turn, outcome, influence}`
    from the two signatures. The **failure** signature is measured — Arabia at
    Valletta, turn 181 — and the test undoes the recovery the next snapshot
    already applied, `influence − per_turn × (snapshot_turn − kill_turn)`, which
    reads −9.25 against a flat −10 and so is tested near rather than equal. A coup is also the one way
    a spy dies with no counterspy present, so `counterspies` must not read a
    kill in a city-state as evidence of a garrison. The **success** signature
    is unexercised in both logs and ships that way.
  - `capacity(civ)` → created / revived / killed / promoted counts, and the
    count of spies **never located**, which is the cheapest honest measure of
    both how much a civ invested and how much of that investment sat at home.
    Revivals are reported **beside** creations, never summed into them: while
    the name changes on revival the two cannot be reconciled, and a sum would
    double-count one spy.
- `WonderRaces` fills its `rival_observed` from `observers_of`, and each
  contender gains `observed_from_turn`, `observed_turns`, `observed_by`,
  `contender_human`, and `rate_before` / `rate_after` from `production_stored`
  deltas. It reports the **opportunity** and never labels the response: an AI
  contender made no decision to label. No AI code reads surveillance, nothing
  in the engine reports a rival's in-progress wonder to anyone, and the AI is
  passed `bInterruptWonders = false` at all four call sites, so it structurally
  cannot abandon. The corpus agrees — 22 AI contenders lost, 0 abandoned; the
  single abandonment in either game is the human's, and was uninformed
  (`docs/espionage.md`).
- `KeyMomentDetector#wonder_race_lost_while_watching` — the Louvre case, and
  the only new moment this feature adds. **Fires only for a human contender**;
  on an AI it would manufacture a decision out of an engine default. Both live
  instances across the two logs are AI, so the moment ships with **no**
  exercised instance and earns its place in a game between humans.
  `ChronicleSpine` does **not** get a new weight: it modifies an existing
  `wonder_race_lost`, it does not anchor a second entry on the same event.
- Digest: `espionage` per civ — capacity, the mission split, losses, and
  tenures at conclusion only, never per turn. Forty-six tenures is small
  enough to carry whole; the cross-cutting rule still applies if a longer game
  produces hundreds.

### Iterations

1. `Espionage#tenures` — the run reconstruction, `visible_from_turn` from
   `spy_surveillance_established` where present and otherwise computed from the
   two constants with `InfluenceTimeline` picking the branch, the bounded
   fallback, `ended_by`. Joins `DigestBuilderCostTest::PROJECTIONS`.
2. `#missions`, `#losses`, `#capacity` — the splits, the inferred host city and
   its staleness.
3. `#counterspies` — a tenure whose states include `counter_intel` where the
   log carries one, else the three signals and the confidence they combine to,
   decided per civ. `docs/espionage.md` carries the DLL rank table the inference
   rests on, since a reader has no other way to know why a kill implies a
   garrison.
4. `#coups` — both signatures. The failure is measured once; the success
   fires on none of the 68 ally changes in the two logs, two of which carry
   snapshots on both sides and are rejected on the swap test itself.
5. `WonderRaces` — `observers_of` join, the observed span, the rate test, the
   five-way classification with four branches declared unexercised.
6. `KeyMomentDetector` + digest section + both prompts. `analyze_game.md` gets
   the opportunity-not-knowledge rule, the read-only-city-screen scope of what
   an observer saw, and the counterspy — read from the log where present, its
   inference and confidence where not; `chronicle_game.md` gets how to write a
   race lost in full view.

## 5. City-state influence and the vote

India ended allied to **10 of 11** city-states and won on diplomacy. The first
draft of this plan concluded that the victory was *"bought with spies, with
caravans as a supporting flow."* **Measured, that is not what happened**, and
the correction is the reason to build the feature the way the next paragraphs
describe.

### The residual is the finding

Influence decays toward a resting point at a logged `per_turn` rate, so the
gain a civ actually bought is `final - initial - Σ(per_turn × elapsed)`. Rigging
an election moves Ljubljana about **+45** each time, measured off eight rigs
ten turns apart against a decay of −1.25. Applying that figure across India's
eleven city-states:

| city_state | rigs | gain | decay | explained by rigs | unexplained |
|---|---|---|---|---|---|
| Ljubljana | 8 | 241 | −91 | 360 | −28 |
| Zurich | 5 | 160 | −48 | 225 | −17 |
| Montevideo | 6 | 198 | −121 | 270 | 49 |
| Tashkent | 3 | 229 | −11 | 135 | 105 |
| La Venta | 1 | 108 | −1 | 45 | 64 |
| Lusaka | 0 | 12 | 10 | 0 | 2 |
| **Harappa** | 0 | 205 | 27 | 0 | **178** |
| **Santo Domingo** | 0 | 163 | −38 | 0 | **201** |
| **Panama City** | 0 | 123 | −80 | 0 | **203** |
| **Mohenjo-Daro** | 0 | 146 | −88 | 0 | **234** |
| **Reykjavik** | 0 | 266 | −111 | 0 | **377** |

**Six of the ten alliances were won with no spy at all**, and about half the
total influence India bought has nothing in the log to explain it. Reykjavik
went 45 → 311 on a permanently negative `per_turn` and never saw a spy.

So the projection's job is not to attribute the climb. It is to **split it into
what the log explains and what it does not**, and to say so in that order. That
residual is the vocabulary the first draft said was missing for the normal case:
it is where gold gifts and quests live, and both are unloggable —
`CvDeal` is unreachable from Lua and `MinorCivQuestTypes` is a C++ enum with no
database table. **A successful coup also lands in the residual** — it moves an
alliance with no event of its own — so feature 4's coup detector is the one
tool that can carve a piece out of this number, and the residual field must
name coups among its candidate causes rather than implying the whole of it is
gold and quests.

The residual also names the bridge to feature 7. India ran **15 CS-bound trade
routes** and adopted `POLICY_MERCHANT_CONFEDERACY` on turn 81 (+1 influence per
turn from routes to city-states, and nobody else took it). The three
city-states with two routes each — Santo Domingo, Panama City, Harappa — carry
residuals of 201, 203 and 178. That is a **hypothesis with arithmetic behind
it**, not a logged fact, and it must reach the digest labelled as one. It is
also why 5 and 7 belong in the same tranche.

### What else an alliance is worth

Allies are not only a victory condition, and the plan should not treat them as
one:

- **Votes, exactly.** `congress_snapshot` carries `votes` and `core_votes` per
  civ. At turn 167 India held **28 votes of which 4 were core** — 24 bought —
  against everyone else's 0 to 2. `CongressTimeline#delegate_votes` already
  reads the record and drops `core_votes` on the floor; splitting it is nearly
  free and is the single clearest number in the game. Votes also elect the host
  and carry ordinary resolutions, long before anyone is near a diplomatic win.
- **Bonuses**, from `trait` in `session_started.city_states[]`, at two
  strengths — `level` in `city_state_snapshot.relations[]` separates friend
  from ally.
- **A buffer.** This adds no geometry: `CapitalProximity#city_state_capitals`
  already holds every city-state's plot and `BufferCities`' corridor test
  already decides whether a city sits between two capitals. Run it with a
  city-state capital as the corridor city, weighted by whether the alliance
  was held at the time.

### The counters this game never showed

Among humans a diplomatic victory is rare because it is answerable. Of the four
answers, the log sees two:

| counter | visible? | fired here |
|---|---|---|
| garrison your own cities against theft | **read** from a `counter_intel` `spy_moved` in a post-fix log; **by inference** (feature 4's counterspy signals) in india-diplo | yes, and invisibly: India held Delhi all game and killed nine spies, in a log that predates the fix |
| coup an ally away outright | **only by inference** — feature 4's two signatures | never |
| conquer a city-state to shrink the vote pool | yes — `city_captured` with `old_owner` in `game.city_state_civs`, and `votes_needed_for_diplo_victory` moving | never; the threshold sat at 34 from turn 101 to the end |
| outbid with gold | **no** — `CvDeal` unreachable | — |
| run the quests | **no** — not logged | — |

In a post-fix log two of the five are read straight from an event; in
india-diplo only the conquest is, the garrison and the coup are inferences the
projection must label as inferences, and two are invisible. The digest must
carry that shape beside the influence curve — without it the analysis credits
every aggressor and never sees a defence, which is exactly the failure this
game's data invites, since the one defence that did happen left no record.

### Design

- `CityStateStanding` (`app/projections/city_state_standing.rb`).
  `applicable?` false with no `city_state_snapshot`.
  - `series(city_state, civ)` → the sparse points, deduplicated per turn the
    way `InfluenceTimeline` and `CityCensus` already do. 238 records over 87
    turns; the curve between two points is read back from `per_turn`, never
    interpolated into fake points.
  - `attribution(city_state, civ)` → `{gain, decay, rigs, explained,
    unexplained, cs_routes, merchant_confederacy}`. `unexplained` is the
    headline field and is never labelled with a cause.
  - `alliances(civ)` → held spans, from `ally` plus `city_state_ally_changed`.
  - `traits` from `session_started.city_states[]`.
- `CongressTimeline#delegate_votes` returns `{votes, core_votes}`; the
  difference is the bought vote count. This changes an existing return shape,
  so it is its own cycle with the digest and its test moving together.
- `KeyMomentDetector#city_state_conquered` — the vote-pool counter, unexercised.
- `BufferCities` gains city-state capitals as corridor cities, alliance-weighted.
- `ChronicleSpine`: no new anchor. An alliance flipping is texture; the vote
  count crossing the threshold already has `diplomatic_victory_imminent`.

### Iterations

1. `CityStateStanding#series` + `#alliances` + `#traits`.
2. `#attribution` — decay, rig steps, the residual. `docs/city-state-influence.md`
   carries the +45 per rig as the user's calibration off eight instances, in the
   style `docs/buffer-city.md` uses for its 17 and 6.
3. `CongressTimeline` core/bought vote split.
4. `KeyMomentDetector#city_state_conquered`; `BufferCities` city-state corridors.
5. Digest section + both prompts, including the two blind spots stated as blind
   spots.

## 6. Diplomatic ties

`friendship_*`, `defensive_pact_*`, `open_borders_*`, `embassy_*` and
`trade_agreement_*` are 54 records, exact, cheap and read by nothing; the
analysis has no diplomacy beyond `war_declared` / `peace_made`. It precedes
deals because it is fact rather than inference, and it is small enough to be
one projection with paired open/close spans and no calibration to argue about.

`DiplomaticTies#spans(civ, other)` → one record per tie with `type`,
`from_turn`, `to_turn`. A pact standing when a war is declared elsewhere is the
join worth having, and `PlayerTimeline#wars` already carries the other side of it.

## 7. Trade routes

118 established, both sides' gold, science, food, production, tourism and
religious pressure. **The first question is where the caravan went, and the log
answers it with no inference:**

| destination | n | `type` | what it is |
|---|---|---|---|
| own empire | 16 | `food` (14), `production` (2) | no gold at all; feeds a city's growth or its hammers, and stays where a barbarian cannot reach it |
| a city-state | 54 | `international` | gold, plus influence and — with `POLICY_MERCHANT_CONFEDERACY` — food and production; the exposed one |
| another major | 48 | `international` | gold both ways, and science, tourism and religious pressure in both directions |

`type` and `to_civ` decide it: `food`/`production` always have `to_civ == civ`,
`international` never does. A civ running internal caravans is buying
development and safety; one running them abroad is buying gold and accepting
risk, and that is a posture the analysis cannot currently see at all.

**Count live routes, never establishments.** India established 22 routes and
never ran anything like that many: 4–5 concurrently from turn 100 to 176, then
eight opened in the last six turns — seven of them to city-states — peaking at
**12 on turn 183, the winning turn**. The establishment count and the
concurrency curve are different facts and only the second describes the empire.

### Counting a live route is the hard part

A route has no id, so its lifetime is reconstructed, and the reconstruction is
lossy in two measured ways:

- **38 of 118 routes have no recorded end** (81 `trade_route_ended` against 118
  established, one end consumed per start). Those fall back to
  `turn + turns_left`, the expiry the record itself states.
- **The `(civ, from_city, to_city, to_civ)` join is wrong sometimes.** A greedy
  first-end-after-start match paired India's Mumbai→Delhi food route from turn
  47 with an end on turn 183 — a 136-turn route whose own `turns_left` said 17.
  Re-established pairs are common and the key cannot tell two instances apart.

**Rule:** a route is live from `turn` to `min(matched_end, turn + turns_left)`,
and the concurrency series carries a flag on each point where a matched end was
discarded for the stated expiry. The numbers above use that rule; they still
carry error bars and the digest says so.

Further caveats to carry:

- **The influence a city-state route grants is not in the route record.** It
  shows only as movement in `city_state_snapshot.per_turn`, so feature 5 reads
  it from the curve and this feature never adds it up from routes.
- **Quests are not logged at all**, so a caravan sent to fulfil one is
  indistinguishable from any other.
- `trade_route_ended` carries no reason and no values.
- `trade_route_plundered` names only the plunderer (2 of 3 were barbarians) —
  no victim, no route, no gold. Tied to an ending only by sharing a turn.

It also shows a civ **feeding a rival's science** — Delhi→Amsterdam gave the
Netherlands 13 beakers a turn and India none — and carries the tourism and
pressure vectors the cultural and religious stories need.

`TradeRoutes#concurrency(civ)` at checkpoints, `#by_destination(civ)` as the
three-way split, `#one_sided` for the routes whose two yields are lopsided.

---

# Tranche 3

Further out, and specified more lightly on purpose: each of these should be
re-measured against a second real log before it is designed in full, because
india-diplo is one game with one human in it.

## 8. Research beelines, and the rush they add up to

`researching` + `research_turns_left` are on every snapshot and dropped today by
`DigestBuilder::SNAPSHOT_METRICS`. It is the one field in the log that shows
**intent** rather than outcome. On its own it says what a civ was aiming at this
turn; joined with the tech count it says what it was aiming at for the last
thirty — a **rush**, a marker technology reached with suspiciously few techs
behind it:

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

**Checked against india-diplo, and it discriminates** — the property that makes
a heuristic worth shipping. Only two fire: **India, Education as tech #18 on
turn 74** (band 16–19; England took it at #24, Tibet #21, the Netherlands #29)
and **England, Navigation as tech #27 on turn 118** (band 26–29; the Netherlands
#31, India #47 — England built the Great Lighthouse and the Arsenal of Venice,
so the frigate read fits). Nothing else lands in a band.

Three things to settle before implementing:

1. **The two tech counts disagree by one or two.** `tech_researched` plus
   `tech_from_ruins` gives India 18 at Education; `snapshot.techs` on turn 74
   gives 19. Snapshots are stamped at the player's turn start, so a tech taken
   during that turn may or may not be counted. Report both, pick one as the
   band's basis, say which. India sits at the very top of 16–19 under one and
   inside it under the other, so it is not academic.
2. **City-states appear in `tech_researched.civs`** — Harappa, Zurich,
   Montevideo and the rest "research" the same tech on the same turn. Every civ
   loop must be restricted to `game.players` or every rush fires eleven extra
   times.
3. **The marker ids need resolving, not guessing.** `TECH_PLASTIC` exists in
   this log, `TECH_PLASTICS` does not; `TECH_STEALTH` appears nowhere in the 70
   techs the game reached. Resolve all eleven through `LekmodIdsExtractor` over
   the `Technologies` table — the pass tranche 1 already added for `Buildings`.

The bands are the user's calibration from play, not a measurement, and
`docs/research-beelines.md` says so. A rush is a `KeyMomentDetector` moment
carrying the target, the marker turn, the tech count and the distance to the
band, so a near-miss reads as a near-miss.

## 9. Yield attribution

`snapshot.yield_sources` splits science, faith, culture and tourism into
cities / city-states / happiness / religion / research agreements / deficit.
Turns a curve into a mechanism, and it is cheap — it rides a snapshot read that
already happens. Two caveats, both from the DLL: the two paths disagree on
vocabulary (`city_states` in science is `minor_civs` in culture; `other_players`
means research agreements), and **the parts do not sum to the total** under a
golden age, anarchy, or a science deficit. Report the parts and the shortfall,
never a normalised percentage that hides it.

This is also the second, independent check on feature 5: if city-states are
paying India's science, `yield_sources` says how much, and that number can be
held against the influence the alliances cost.

## 10. Religion and conversion

644 `city_converted`, plus `from_pressure` / `to_pressure` on trade routes, plus
`religion` and `religion_followers` per city snapshot. A whole axis of the game
that is currently invisible. The pressure fields make this the third consumer of
feature 7's route reconstruction, which is an argument for doing 7 properly
rather than cheaply.

## 11. Deal reconstruction, labelled as inference

`CvDeal` is unreachable from Lua, so gold, gold-per-turn and city trades cannot
be logged at all. What can: `snapshot.resources[]` gives `total` / `used` /
`import` / `export` per strategic and luxury resource, and **a luxury appearing
in one player's imports and another's exports on the same turn is a deal**. The
projection matches import/export pairs between majors; an import with no major
exporter is a city-state ally's gift, which is itself a useful signal — and the
one piece of evidence that would put a number on feature 5's residual.

The digest and both prompts must say this is reconstructed, and must say what
stays invisible: the price, the gold, the duration.

---

## Cross-cutting

**Digest size is still unguarded, and tranche 1 did not fix it.** The digest is
~55k input tokens today; timelines, key moments and resolutions are unbounded
full lists. `test/services/digest_builder_cost_test.rb` bounds *work* (two log
passes, one construction per projection) and nothing bounds *size* — tranche 1
added `wonder_races` and the capture valuations without it, and tranche 2 adds
espionage, city-state standings, diplomatic ties and trade routes on top.
**Landed** as `DigestBuilderCostTest#"keeps the digest within its size budget
as a game grows"`: 250 bytes per turn per civ, calibrated on the fixture at 187
and verified against a minimal per-city-per-turn section, which takes it to 318.
Five games between 20 and 203 turns sit between 86 and 187, so the bound is on
the measure that separates a section scaling with the product from one scaling
with wars or races.

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
