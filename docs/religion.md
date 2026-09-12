# Religion and conversion

Design notes for the feature `docs/reading-the-new-log.md` §10 leaves as a
stub. `docs/plan.md` keeps the project-wide iteration history; this file
holds the game rules the projection rests on, measured against the DLL
source and against the five example logs.

Four logs carry `city_converted`: `india-diplo.jsonl` (644, the oldest,
predates every espionage-related logger fix but is the only log with
`city_snapshot` for its full span), `babylon-domination.jsonl` (262, no
`city_snapshot` at all), `chile-vs-vietnam.jsonl` (149, no `city_snapshot`
either), `espionage-test.jsonl` (216, `city_snapshot` for turns 82–189). A
fifth, `run-b-test.jsonl`, carries exactly one — Sarai Batu converting to
Tengriism on turn 140 — too little to test anything against, and noted here
only for completeness.

The DLL is the Lekmod fork at `EnormousApplePie/Lekmod`, commit `9545382`,
same source `civ-narrative-logger/docs/lekmod-gameevents.md` was extracted
from. File:line citations below are against
`LEKMOD_DLL/CvGameCoreDLL_Expansion2/{CvReligionClasses,CvUnit}.cpp` in that
commit.

## Gaining a religion is logged. Losing one never is.

`CvCityReligions::RecomputeFollowers` (`CvReligionClasses.cpp:4385`) runs
whenever a city's follower pressure changes, for any reason, and decides
whether to report it:

```cpp
if(eMajority != eOldMajorityReligion || iFollowers != iOldFollowers)
{
    CityConvertsReligion(eMajority, eOldMajorityReligion, eResponsibleParty);
    ...
}
```

`CityConvertsReligion` (`:4559`) updates the city's actual religion state
unconditionally at line 4563 — `m_pCity->UpdateReligion(eMajority)` always
runs. But the Lua hook that produces the log's `city_converted` event sits
inside a second, narrower guard at line 4574: `if(eMajority >
RELIGION_PANTHEON)`. Everything from the diplomatic-hit calculation to the
`LuaSupport::CallHook` call at line 4760 is inside that block. **A
transition into a full religion fires the event. A transition into
atheism or pantheon-only does not, even though the city's own state
changes just the same.**

Vijayanagara (India, `india-diplo.jsonl`) shows exactly this. Its
`city_snapshot.religion` runs Hindu at 8–10 followers from turn 111 through
146, then the field disappears — omitted, not zeroed, per the log's usual
omit rule — for turns 147 through 168, then reappears as Hindu at turn 169
with 21 followers, nearly the city's entire population of 24. The
`city_converted` stream for the same city has **nothing between turn 137
and turn 168** — 21 turns during which the city fully lost its majority
religion and the log said nothing at all. The regain at 168 does fire,
because the new majority is once again above pantheon.

Two consequences:

- **A consumer diffing consecutive `city_converted` rows for one city will
  misread a silent round-trip through atheism as no change**, because both
  the row before the drop and the row after the regain name the same
  religion. Turn 137 and turn 168 both say Hinduism; nothing in the event
  stream hints that the city spent three weeks of game-time areligious in
  between. Only `city_snapshot`'s omitted field carries that.
- **The all-at-once jump from 10 to 21 followers at turn 169**, in a city
  that had shown gradual single-digit growth for the previous 35 turns,
  matches `AddProphetSpread`'s own description at `CvReligionClasses.cpp:3858`
  — "eliminates all existing religions and adds to his own" — better than
  any gradual channel below. Nothing in the log names the unit responsible;
  this is a shape argument, not a citation.

## Even within "gains," most rows are noise

`city_converted`'s payload (`extractors.lua:532–542`) carries `civ`, `city`,
`religion`, `turn`, `x`, `y`. No prior religion, no follower count, no
reason. So the event that does fire cannot itself say whether the majority
actually changed or whether the same religion's follower *count* just moved
— `RecomputeFollowers`'s guard fires on either.

Measured across all four usable logs, splitting each city's ordered
`city_converted` rows into first sighting, same-religion-as-the-row-before
(churn), and different-religion-than-the-row-before (a "flip" by the naive
reading, before the atheism blind spot above is accounted for):

| log | total | first | churn | flip |
|---|---|---|---|---|
| babylon-domination | 262 | 24 | 228 (87%) | 10 |
| chile-vs-vietnam | 149 | 29 | 112 (75%) | 8 |
| espionage-test | 216 | 33 | 169 (78%) | 14 |
| india-diplo | 644 | 61 | 540 (84%) | 43 |

Population growth alone drives most of this: `DoPopulationChange`
(`CvReligionClasses.cpp:3819`) adds atheism pressure on every pop gain and
calls `RecomputeFollowers` on every pop loss, and the largest-remainder
apportionment in `RecomputeFollowers` (`:4425–4463`) reassigns the new
citizen to whichever religion's remainder is largest that turn — which
moves the *count* under an unchanged majority far more often than it moves
the majority itself.

**City-states appear in the stream under their own name** — Reykjavik and
Santo Domingo both show up in india-diplo's list, the same trap
`docs/research-beelines.md` point 2 already documents for
`tech_researched`. Any per-civ read must restrict to `game.players`.

## A city's religious history is a run, not a reading

Even the 43 "flips" above are not all real settlements. Collapsing
india-diplo's stream to actual transitions (dropping consecutive rows that
repeat the prior religion) gives 104 transitions city-wide; 43 of those have
a *known* end — a later transition for the same city — and their span until
that next transition runs from **0 turns** (two rows, same turn, different
religions) up to **90**, median **4**, with **20 of the 43 (47%) lasting
three turns or less**.

Vijayanagara again is the extreme case, turns 105–110:

```
t105  Catholicism
t105  Protestantism   (same turn)
t106  Catholicism
t106  Protestantism   (same turn)
t107  Hinduism
t108  Catholicism
t110  Hinduism        (holds — next transition is turn 137's un-logged loss)
```

A three-way contested city can flip its majority twice in a single turn.
This is `RecomputeFollowers`'s apportionment amplifying a near-tie: at
parity, whichever religion's pressure lands on the larger remainder that
turn wins the last follower, and the largest remainder itself is not
sticky from turn to turn.

**A single `city_converted` row is therefore never itself evidence of a
lasting conversion.** What the feature should report is closer to
`Espionage`'s tenure — a maximal run of one religion holding a city's
majority — with a settled run (one that lasts past some threshold, or
survives to the next `city_snapshot`) told apart from a flicker the same
way a spy tenure is told from a spy passing through.

## Two channels, and where each one is blind

`city_snapshot.religion` / `.religion_followers` is written every turn for
every city, wherever a log has `city_snapshot` at all — 5,206 rows across
india-diplo's full span, one per city per turn. It carries the omit rule
like everything else in this log: no majority religion means the field is
absent, not `null` and not `"NO_RELIGION"`. It also carries pantheon —
`TXT_KEY_RELIGION_PANTHEON` shows up directly (Jerusalem, turn 87) — which
`city_converted` can never report, since the guard at `:4574` excludes
pantheon-level majorities from the hook entirely. A city that never
progresses past its own pantheon is invisible to the event stream for its
whole life and visible in the snapshot the whole time.

So where a log has `city_snapshot`, it is the more trustworthy channel for
*current majority*, precisely because it has no equivalent to the
event-side blind spot above — it says plainly when a city holds no
religion, rather than staying silent. What it cannot do is date a
transition to the turn: two consecutive snapshots a turn apart bracket a
change, but nothing between them says which turn inside that bracket it
happened, and a change that both starts and reverts inside one snapshot
gap is invisible to it exactly as churn is invisible in a coarser digest.

Two of the five logs (`babylon-domination`, `chile-vs-vietnam`) have no
`city_snapshot` at all, and `run-b-test`'s single row is too little to
lean on either channel. For those, the event stream — noisy, and blind to
every de-conversion — is the only signal there is, and the digest and
prompt must say so plainly rather than presenting a `Religion` reading from
one of those logs with the same confidence as one built where both
channels exist.

## What actually moves the pressure, and how much of it is logged

`RecomputeFollowers` is fed by `AddReligiousPressure` and
`AddProphetSpread`, called from five places:

| channel | logged? | source |
|---|---|---|
| trade routes | **yes** — `from_pressure`/`to_pressure` on `trade_route_established` | `CvLuaPlayer.cpp:4755-4756`, already documented in `civ-narrative-logger/docs/implemented-changes.md` |
| adjacency (within `RELIGION_ADJACENT_CITY_DISTANCE`) | no | `SpreadReligionToOneCity`, `CvReligionClasses.cpp:332-394` |
| missionary / prophet spread | no event on the action itself | `DoSpreadReligion`, `CvUnit.cpp:8809-8953` |
| spy pressure | no | belief-gated, `CvReligionClasses.cpp:353-360, 3112-3121` |
| holy city passive pressure | no | `AddHolyCityPressure`, `CvReligionClasses.cpp:344, 4119` |

**Adjacency runs every turn, for every city in the game, against every
other city in the game** (`CvGameReligions::SpreadReligion`,
`:312-329` — a plain double loop over all living players' cities). It is
the DLL's own O(n²) computation and nothing polls it; its only trace is
whatever `city_converted` or snapshot change eventually results. This is
the same mechanism `civ-narrative-logger/docs/implemented-changes.md`
already describes from the trade-route side — "proximity already spreads
the faith" is why two fully-converted neighbours report zero trade-route
pressure between them (`RELIGION_ADJACENT_CITY_DISTANCE`,
`CvReligionClasses.cpp:3802-3812`) — but the adjacency spread itself carries
no event of its own.

**Spy pressure is a new connection to `docs/espionage.md`.** It only
applies when the religion's own beliefs grant `GetSpyPressure() > 0`
(`CvReligionClasses.cpp:3112-3121`), and when it does, *any* of that
player's spies stationed in a foreign city — found by
`GetSpyIndexInCity(pCity) != -1`, no particular mission state required —
pushes that player's founded religion's pressure into the city every turn
it stays there. Every spy tenure `Espionage` already tracks becomes a
religious-pressure vector too, for any founder whose religion carries that
belief. Whether any of the five example games' founded religions carry it
is unchecked here — it would need `db/lekmod/<version>/religion.md` read
against each game's `religion_founded`/`religion_enhanced` beliefs.

**Missionary and prophet strength is not a flat constant.**
`CvUnit::GetConversionStrength` (`:9098-9127`):

```
strength = RELIGION_MISSIONARY_PRESSURE_MULTIPLIER × unit's religious strength
           × (100 + belief modifier) / 100
```

where the modifier is `GetProphetStrengthModifier` for a great person or
`GetMissionaryStrengthModifier` otherwise — both belief-driven, so the same
unit converts harder or softer depending on which beliefs its owner's
religion picked. There is no single number to calibrate the way
`CityStateStanding::RIG_GAIN` calibrates a rig.

**No single `city_converted` row can be assigned one of these five causes
as fact.** They stack on the same city the same turn — adjacency, a spy's
passive pressure, and a caravan's trade-route pressure can all land on one
city at once, `RecomputeFollowers` only reports the net result, and the
payload does not even carry the pressure delta, only the eventual majority.
This is the same shape as `docs/city-state-influence.md`'s `unexplained`
residual: candidate causes, never a single attributed one.

## Missionaries and Inquisitors act through a side door

Neither `CvUnit::DoSpreadReligion` (`:8809`) nor `DoRemoveHeresy` (`:8999`)
calls `LuaSupport::CallHook` anywhere in its body — searched directly, no
hook of any kind. Contrast a **Prophet's final spread**: once
`GetReligionData()->GetSpreadsLeft() <= 0`, `IsGreatPerson()` routes through
`CvPlayer::DoGreatPersonExpended`, which is what fires the `GreatPersonExpended`
hook `PlayerTimeline` already reads as `:religious_action`
(`app/projections/player_timeline.rb:184-209`). **A Prophet with more than
one spread charge produces no event of any kind for every spread before
its last** — this reading follows directly from the code (`CvUnit.cpp:8918-8941`
takes the `finishMoves()` branch, not the kill/expend branch, while spreads
remain), but no example log was checked here for a multi-spread Prophet to
confirm it lands that way in practice.

A **Missionary or Inquisitor's use is invisible outright** — no hook fires
under any condition, spent in one action or not. The only trace is the
unit's own `unit_lost`, since both call `kill(true)` immediately after
acting (`CvUnit.cpp:8929`, `:9027`). `PlayerTimeline` already treats an
absent `killed_by` on a civilian unit as "expended its ability," the same
logic `GREAT_PERSON_UNITS` uses for Scientists and Workers; the same rule
applies here even though Missionary and Inquisitor are ordinary
faith-purchased units, not great people. Measured across the four usable
logs, units created versus units lost with no killer:

| log | Missionaries created | Inquisitors created |
|---|---|---|
| babylon-domination | 35 | 2 |
| chile-vs-vietnam | 23 | 1 |
| espionage-test | 32 | 1 |
| india-diplo | 64 | 5 |

Unlike a spy, **neither unit's position is polled between creation and
death.** `Espionage` can place a spy because the logger diffs every major's
spy roster every turn; nothing polls Missionaries or Inquisitors the same
way. So even the weak join — "this unit was consumed near this city around
this turn" — usually cannot be made at all; the record is limited to "a
Missionary/Inquisitor was consumed somewhere, sometime around this turn,"
read separately from "this city's majority changed," with no reliable way
to connect the two beyond turn proximity when the unit's `city` field
happens to be set (it is populated on `unit_created` and, per the same
convention `Espionage`'s postings rely on, only sometimes carried through
to the loss).

**`IsDefendedAgainstSpread`** (`CvReligionClasses.cpp:3401-3427`) blocks a
spread outright when the target city already holds one of *its own owner's*
Inquisitors carrying a different religion. A Missionary sent into a
well-defended city achieves nothing, leaves no distinguishing trace, and
reads identically in the log to one that succeeded — the same silent-failure
shape `docs/espionage.md` documents for a spy that never sees anything. And
an Inquisitor's defensive presence, before it is ever spent on
`DoRemoveHeresy`, is a **garrison** in exactly `Espionage`'s sense: a
position held over a span of turns, producing nothing in the log but its
original `unit_created` and, if it moves, whatever a caught-in-transit
position poll happens to record.

## What the log will never say

- **Why a Missionary or Prophet was sent where it was sent.**
  `GetReligionToSpread`, `CanSpreadReligion` and the rest of the `Can*`/`Get*`
  family are decision-query hooks, and `civ-narrative-logger`'s own design
  rule (`docs/design-decisions.md`, "Event list source of truth") is never to
  subscribe to them — their return values feed game logic, so a listener
  could alter play.
- **The exact strength of one spread.** The belief modifiers
  (`GetMissionaryStrengthModifier`, `GetProphetStrengthModifier`,
  `GetSpreadDistanceModifier`) could be looked up from
  `db/lekmod/<version>/religion.md` as percentages, but the instance-level
  roll needs the target city's live pressure state at that exact moment,
  which is never logged.
- **The diplomatic and economic weight of a real conversion.** A successful
  spread that changes a foreign city's majority levies a real, DLL-computed
  opinion hit against whoever's religion it displaced —
  `ChangeNegativeReligiousConversionPoints`, 1 point for a city that never
  held the rival's religion, 3 for one that had it established, 25 for a
  holy city (`CvReligionClasses.cpp:4711-4744`) — and can pay the converting
  religion's founder a one-time gold bonus
  (`GetGoldWhenCityAdopts`, `:4582-4601`). Both are as unreachable from Lua
  as `CvDeal`, and neither leaves any trace in the log at all.

## A proposed shape for the projection

Not implemented yet — this is the design to review before writing failing
tests for it, the same way `docs/city-state-influence.md` and
`docs/espionage.md` preceded their projections.

- **`Religion#holds(civ)`** — per-city maximal runs built from the
  deduplicated `city_converted` stream (restricted to `game.players`),
  each carrying `city`, `religion`, `from_turn`, `to_turn`, and `settled:`
  (true once a run either survives to the next `city_snapshot` reading for
  that city, where one exists, or crosses some minimum span — the threshold
  itself is an open question below). Where `city_snapshot` exists for the
  game, cross-check every hold's boundaries against the snapshot's own
  religion column, including its silences, rather than trusting the event
  stream's gains-only view alone.
- **Trade-route pressure** needs no reconstruction — `from_pressure`/
  `to_pressure` are already on `trade_route_established` — so this is a
  read through the existing `TradeRoutes` projection rather than a new one.
- **`Religion#missionary_uses(civ)` / `#inquisitor_uses(civ)`** — inferred
  from `unit_lost` rows with no `killed_by`, for `UNIT_MISSIONARY` and
  `UNIT_INQUISITOR`, each flagged `inferred: true` and carrying whatever
  `city`/`x`/`y` the loss record happens to hold.
- **Digest and prompt guidance**: a hold's start is never labelled with a
  single cause among the five channels above. A hold beginning within a
  turn or two of an inferred missionary/inquisitor use, or during an active
  high-pressure trade route, is a candidate explanation and should be
  phrased as one — the same residual framing `docs/city-state-influence.md`
  already establishes.

## Calibration status

- The churn/flip/first split (the first table) is stable in direction
  across all four logs but has not been turned into a chosen "settled"
  threshold. The Vijayanagara case argues for "survives to the next
  snapshot" over a fixed turn count, but that only works in the two logs
  that carry `city_snapshot` throughout.
- The atheism blind spot is confirmed in one city in one log. It should
  hold everywhere the mechanism is the same DLL code, but it has not been
  cross-checked against a second silent-relapse instance.
- The multi-spread Prophet silence is read from the code, not observed —
  no example log was checked turn-by-turn for a Prophet using more than one
  charge.
- Whether any founded religion in these five games carries the
  spy-pressure belief is unchecked.
