# The wonder race

Execution notes for one feature. `docs/plan.md` keeps the project-wide
iteration history; this file holds the rules that need calibrating and the
honest limits on what the log can see.

## Context

`city_snapshot` carries `producing`, `production_stored` and
`production_turns_left` for every city every turn. Nothing read them. In
`india-diplo` 42 world wonders were completed and ten were contested — two
or more cities building the same wonder — and the sharpest of those is
England putting 425 hammers over ten turns into the Louvre and losing it
to Amsterdam on the turn it would have finished. `WonderRaces`
reconstructs those races; `KeyMomentDetector` surfaces the losses;
`ChronicleSpine` decides which losses anchor an entry.

## The reconstruction

A race has no id and no "started" event. For every `building_constructed`
with `wonder: "world"`, scan every city's `producing` up to the completion
turn:

- **contested** — at least one city other than the winner's was ever seen
  building it. An uncontested completion produces no record.
- **`production_invested`** — the contender's `production_stored` on its
  **last** snapshot building the wonder, up to one turn stale. Reported as
  observed, with `first_seen_turn` / `last_seen_turn`.
- **`turns_left_when_last_seen`** — `production_turns_left` on that same
  snapshot: the game's own estimate of the distance still to cover. This is
  the better "how close" measure; `production_stored` alone cannot tell a
  near-miss from a city that queued a wonder and put nothing in it.
- **`outcome`** — `:lost` when the contender was still building the wonder
  on the completion turn or the one before; `:abandoned` when it dropped
  the wonder earlier. Losing and walking away are different facts.
- **`contended_from_turn`** — the second builder's `first_seen_turn` (the
  turn it became a contest); the lone contender's own start when the winner
  completed it unobserved.

## What the log cannot see

- **A Great Engineer instant-buy is not logged.** `building_constructed`
  carries `bought_with` but it only ever holds `"faith"`;
  `great_person_expended` carries `{civ, great_person, turn}` with no city
  and no target, so a `UNIT_ENGINEER` cannot be tied to a wonder (engineers
  also build Manufactories). The proxy is `winner_finish`: `:hard_built`
  when the winner's last snapshot still estimated ≤ 1 turn,
  `:ahead_of_estimate` when it estimated more — an engineer, a production
  overflow, a chopped forest or a granted building, and the log cannot say
  which. **All 42 india-diplo wonders finished from `turns_left: 1`**, so
  the `:ahead_of_estimate` branch ships specified and unverified.
- **A same-turn tie reads as an ordinary loss.** LEKMOD picks one winner
  at random when two civs complete the same wonder on one turn; only that
  civ gets a `building_constructed`. The tied loser looks like any `:lost`
  contender last seen on the completion turn. No india-diplo wonder was
  completed twice, so this is untested and unhandled.
- **The refund is a rule, not a record.** LEKMOD returns a lost wonder's
  production as gold. The amount is not in the log. The digest reports
  `production_invested` and the prompts say what becomes of it; no gold
  figure is ever computed.
- **`WonderRaces` degrades** to `applicable: false` on the two example
  logs with no `city_snapshot`, like `BufferCities` off Pangaea.

## Rules that need calibrating

The user's own numbers from play, not a measurement — the same footing as
`docs/buffer-city.md`'s 17 and 6.

- **`WONDER_RACE_MIN_INVESTED = 1`** (`KeyMomentDetector`) — a `:lost`
  contender needs more than zero `production_invested` to become a moment.
  This drops two india-diplo losses (Great Library / Zimbabwe, Colossus /
  Netherlands, both 0 hammers) and keeps everything else. It is a floor,
  not a judgement of closeness.
- **`:close` vs `:distant`** (`KeyMomentDetector#race_loss_scale`) — a loss
  is `:close` when `turns_left_when_last_seen ≤ 4` **or**
  `production_invested ≥ 200`, else `:distant`. On india-diplo this splits
  the ten losses 6 / 4: Stonehenge, Machu Picchu, Himeji, Louvre and both
  Red Fort losses are `:close`; Great Wall (96/6, 72/6), Great Mosque
  (37/5) and Alhambra (17/18) are `:distant`. The Great Wall pair is the
  borderline — the doc's own table calls it contested, but the game rated
  it six turns off, so it is texture here rather than an anchor.
- **`ChronicleSpine`** weights `:close` at **4** and `:distant` at **2**;
  `ANCHOR_WEIGHT` is 3, so a `:close` loss anchors its own entry and a
  `:distant` one only colours a neighbouring one. `wonder_race` (the
  start) is weight **1** — a game has many, and it is texture for the
  entry its loss anchors, never an anchor itself.

## Verification against india-diplo (game 32)

```sh
bin/rails runner 'pp WonderRaces.new(Game.find(32)).races'
bin/rails runner 'pp KeyMomentDetector.new(Game.find(32)).wonder_races_lost'
```

- ten contested wonders, the 32 uncontested completions absent
- the Louvre among them: `winner` Netherlands / Amsterdam, England /
  London a contender with `production_invested: 425`,
  `turns_left_when_last_seen: 2`, `outcome: :lost`, `scale: :close`
- every `winner_finish` is `:hard_built`
- `babylon-domination` produces `{applicable: false, reason:
  :no_city_snapshots}` for `digest[:wonder_races]`
