# Game speed factors

Execution plan for one feature. `docs/plan.md` keeps the project-wide
iteration history; this file is the detailed plan for this change alone.

## Context

`GameSpeed::FACTORS` covers all five speeds, and an unrecognized string
still falls through to `STANDARD_FACTOR = 1`. Three call sites scale a
standard turn threshold through it:

| Call site | Threshold | Meaning |
|---|---|---|
| `early_game.rb:33` | 150 | the latest turn the early game can run to |
| `key_moment_detector.rb:667` | 100 | the grace period for early-game moments |
| `opening_strategy.rb:287` | 100 | the turn a National College is late by |

Before `FACTORS` covered every speed, an epic or marathon game fired all
three at standard turns and read as a civilization catastrophically slow.
Every example log is `GAMESPEED_QUICK`, so the fixtures exercise no other
speed; `test/models/game_speed_test.rb` covers them directly.

`Battles::WINDOW_TURNS` deliberately stays out of this table. Speed scales
production and growth, never damage, hit points, healing or movement, so
a fight lasts the same number of turns at every speed.

## Ground truth

From `<GameSpeeds>` in
`/Users/dysk/projects/Lekmod/LEKMOD/Override/CIV5Units.xml`. Most
percentages move together, and that shared column is the general pace:

| Field | Marathon | Epic | Standard | Quick | Online |
|---|---|---|---|---|---|
| Growth / Train / Build / Culture / Faith / Gold / GreatPeople / UnitDiscover / UnitHurry / UnitTrade / VictoryDelay / League | 300 | 150 | 100 | 67 | 50 |
| ResearchPercent | 300 | 150 | 100 | 67 | **67** |
| GoldenAgePercent | **200** | **125** | 100 | **80** | 50 |
| SpyRatePercent | **100** | **100** | 100 | **50** | **40** |
| BarbPercent | **400** | 150 | 100 | 67 | 50 |
| HurryPercent | 100 | 100 | 100 | 100 | 100 |

So the general pace factor is 3, 1.5, 1, 2/3, 1/2 — and four fields
refuse to follow it.

## The rule

1. One general pace factor scales a turn threshold. All three call sites
   are turn thresholds and use it. A threshold measured in combat turns
   does not scale at all.
2. A field that diverges gets its own factor and its own method. Nothing
   derives a divergent quantity from the general factor.
3. An unrecognized speed string still reads as standard, because a wrong
   threshold beats a crash, but it stops being silent.

## Steps

Each step is one TDD cycle — failing tests first, left unstaged for
review, then the smallest implementation that greens them, then one commit
holding both.

### 1. Complete the general factor — done

- `FACTORS` holds `MARATHON => 3`, `EPIC => Rational(3, 2)`,
  `QUICK => Rational(2, 3)` and `ONLINE => Rational(1, 2)`. Standard is
  the fallback, `STANDARD_FACTOR`.
- The existing "falls back to standard speed for an unknown speed" test
  has to stop using `GAMESPEED_MARATHON`. Replace it with a string that is
  genuinely not a speed.
- Tests: `turns(150)` answers 450 / 225 / 150 / 100 / 75 across the five
  speeds; an unrecognized string answers 150; `nil` answers 150.

### 2. Say when the speed was not recognized

- `known?` is true when the raw string matched a factor.
- `DigestBuilder` carries `game_speed_recognized: false` only when it is
  false, beside the existing `game_speed`.
- The prompt reads it as a warning that every turn threshold in the digest
  may be scaled wrong, not as a fact about the game.
- Tests: `known?` across the five speeds and on a nonsense string; the
  digest key appears only for the nonsense case.

### 3. Research pace, where it differs — dropped

`ResearchPercent` differs from the general pace on online speed alone
(67 against 50). The National College target stays on the general factor,
because building the college paces an opening more than researching it.
No call site needs a research factor, so `research_turns` does not exist.

### 4. Golden age — done

Covered by `docs/great-people.md` step 3a — `GOLDEN_AGE_FACTORS` and
`golden_age_turns`, built from the `GoldenAgePercent` row above. Listed
here so the three factors stay in one file and one test class.

### 5. Prompt

`analyze_game.md` lines 101-103 state the quick case as if it were the
only one:

> Map, size, speed, start era and `max_turns`. `game_speed` scales every
> turn number — a marathon game runs at three times standard pace, an epic
> at one and a half, a quick at two thirds, an online at half. Compare turn
> numbers only within this game, and never against a turn named in another
> game's report. Where `game_speed_recognized` is false, the speed string
> was not one this tool knows: treat every turn threshold as standard-paced
> and say so once rather than reading lateness into it.

## Not in scope

- **Espionage timings.** `TRAVEL_TURNS` and `SURVEILLANCE_TURNS` are DLL
  constants, and `SpyRatePercent` is flat at marathon and epic, so these
  may well not scale at all. Check `CvEspionageClasses.cpp` before touching
  them.
- **Barbarian rate.** `BarbPercent` 400 at marathon is the one field with a
  shape of its own. Nothing reads it today; `docs/loss-cause.md` adds a
  barbarian tally, and if that tally ever grows a threshold, this is the
  column it scales by.
- **Instant great-person yields.** `UnitDiscoverPercent`,
  `CulturePercent`, `UnitTradePercent` and `UnitHurryPercent` scale what a
  bulb, a treatise, a trade mission and a hurry are worth. Nothing in the
  application reads a magnitude for any of them, and nothing can — the log
  records that a great person was spent, never what it produced. A bulb is
  a one-off beaker injection, so it does not appear in `yield_attribution`
  (whose science sources are cities, city-states, happiness and deficit) and
  does not move the per-turn `science` snapshot either. Its only trace is a
  tech arriving a step early.

  Worth noting while the table is in front of us: those four fields carry
  the general pace factor exactly. A quick game has two thirds the turns
  and pays two thirds for an instant use, while tile yields per turn are
  not speed-scaled at all. So the permanent-against-one-off trade-off the
  great-people prompt reasons about holds its shape across speeds, and
  needs no per-speed correction. That is reasoning from the table, not a
  measurement.
