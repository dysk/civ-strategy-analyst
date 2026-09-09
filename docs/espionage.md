# Espionage

Execution notes for one feature. `docs/plan.md` keeps the project-wide
iteration history and `docs/reading-the-new-log.md` the ordering; this file
holds the game rules the projection rests on, the inferences it is forced
into, and the honest limits on both.

Everything measured here comes from `examples/india-diplo.jsonl` — one game,
one human against five bots. Where a mechanism is specified but that game
never exercised it, the text says so.

## Why this is a projection of its own

A spy is a **position on the map held over a span of turns**, and four
unrelated questions are answered by joining against that position: whether the
loser of a wonder race could see the winner's build, what moved a city-state's
influence, whether an empire was garrisoned against theft, and whether a
paradrop had a spotter. A primitive four features share belongs in front of
them, not inside one of them. `WonderRaces` already carries a
`rival_observed: nil` waiting for it.

## What a spy grants its owner

Two halves, and the second is the larger one.

**The map half** is cited: `CvPlot.cpp:1888` grants
`changeAdjacentSight(..., ESPIONAGE_SURVEILLANCE_SIGHT_RANGE, ...)` to every
major with `HasEstablishedSurveillanceInCity`. That is the vision that lets
artillery and bombers fire without a spotter and a paradrop pick a target.

**The intelligence half is a played rule, not a DLL constant.** A spy with
surveillance opens the target's full city screen, read-only — every yield,
every detail, and the whole production queue, exactly as its owner sees it.
It is a UI affordance, recorded here on the user's knowledge of the game.

The consequence matters more than it first looks: `city_snapshot.producing` is
the **floor** of what a watcher knew, never the ceiling. An analysis may say a
contender could see the rival's plan, not merely its current item.

**The log never shows that a player looked.** It shows the opportunity to
know. Fields are named for opportunity — `observed_by`, not `known_by` — and
both prompts must be told the difference, or the analysis will narrate a
decision the player may have made with their eyes shut.

## Dating what a spy could see

`CvEspionageClasses.cpp:1795` — surveillance is established when the state is
`SURVEILLANCE` *and* the goal is reached, **or** whenever the state is
`GATHERING_INTEL`, `RIG_ELECTION` or `SCHMOOZE`. `:1702` — establishing it
takes a base **3 turns** after arrival, shortened by
`GetInfluenceSurveillanceTime` against the target, the same tourism mechanic
that shortens occupation resistance in `docs/city-value.md`.

A spy therefore does not see anything for the first few turns of a posting: it
travels, then it establishes surveillance, and only then does the city screen
open. That delay is **computable, not guessable**, because both terms are
constants:

```
vision begins at  posting + iSpyTurnsToTravel + GetInfluenceSurveillanceTime
                = posting + 1 + (3, or 1 with a tourism lead)
                = posting + 4, or posting + 2
```

`iSpyTurnsToTravel = 1` (`CvEspionageClasses.cpp:23`).
`GetInfluenceSurveillanceTime` (`CvCultureClasses.cpp:2919`) is **3**, cut to
**1** when the spy's owner is at `INFLUENCE_LEVEL_FAMILIAR` or better over the
target — and for a city-state, over that city-state's *ally*. `InfluenceTimeline`
already carries the level per pair, so the projection picks the branch rather
than assuming one.

**The log corroborates the constant.** See the next section: the first
`spy_mission_completed` after a posting lands at **+3 or +4 in 14 of 18
postings**, which is that formula and not a mission.

So three dating rules, in descending order of what they may be used for:

- **Computed** — `posting + 1 + surveillance_time`. Exact when the posting is
  known, which is 13 of 24 spies. This is `visible_from_turn`.
- **Certain floor** — a `spy_mission_completed` in city C on turn T proves
  surveillance was live in C on T, because those mission states imply it
  (`CvEspionageClasses.cpp:1795`). Used when the posting was lost, and then
  `visible_from_turn` is a **lower bound** with `visible_from_turn_bounded:
  true` on the record.
- **Never** — a `spy_moved` turn on its own. It is the order to go, not the
  arrival, and it is never used unadjusted.

None of the three says the player looked.

## Tenure, and what the log loses

A spy is named (`TXT_KEY_SPY_NAME_INDIA_7`) and the name is stable, so a
tenure is a maximal run of sightings of one spy in one city. Over india-diplo
that is 24 spies with a location and 39 tenures.

**The logger loses postings**, and the projection is built knowing it:

- 11 of those 24 spies are first located by a `spy_mission_completed`, not by
  a `spy_moved` — their arrival was never written.
- `ENGLAND_6` moved Amsterdam (t152) → Osininka (t168) with no `spy_moved`
  between, so re-postings are lost too.
- `spy_created` carries no location (0 of 18) and `spy_killed` carries none
  either (0 of 9), though the DLL holds one in both cases.

Reported upstream in `civ-narrative-logger/docs/planned-changes.md`, *"Let a
counterspy leave a trace"*. Until it is fixed, a tenure's `from_turn` is the
first sighting, **not** the arrival, and every span is a lower bound on how
long the spy was actually there.

## Most logged missions did not happen

`completed()` in the logger reads any fall in `PercentComplete` as a finished
mission, but progress also restarts at a **state transition** — travelling,
surveillance and gathering intel share one `amount / goal` counter and each new
state begins it at zero (`CvEspionageClasses.cpp:2474-2487`). Surveillance
finishing therefore reads as a mission finishing, at exactly
`posting + 1 + surveillance_time`.

Anchoring every completion in india-diplo against the nearest preceding
`spy_created` or `spy_moved`:

| | count |
|---|---|
| state-transition artifacts | **23** |
| genuine completions | 21 |
| unclassifiable — the posting was lost | 9 |

**23 of 53.** The damage is worst where the volume is lowest. India's rigged
elections mostly survive, because they land on a fixed ten-turn cycle that
corroborates them independently; England's ten tech thefts reduce to two that
can be confirmed, and the Netherlands, Tibet and the Iroquois to none.

Rigging is damaged least for a readable reason, and it is the strongest
evidence this reading is right: for `SPY_STATE_RIG_ELECTION` progress comes
from the global election clock, not the city's counter, so the transition does
not always produce a fall. The defect's footprint follows the progress formula
exactly.

**What the projection must do about it.** Filter a completion that lands 3 to 6
turns after that spy's last posting or creation in the same city, and count it
as the surveillance moment instead of a mission. Where no anchor survived,
carry the completion with `anchored: false` — it may be either — and never let
an unanchored count reach a prompt as a bare number.

Two consequences worth stating plainly, because both bite the headline:

- **Mission counts are upper bounds** until the logger is fixed, and the
  per-civ split is unreliable for every civ but India.
- **A kill hides a completion.** The roll that kills a spy happens *at*
  `HasReachedGoal`, and `diffSpy` takes the `dead` branch first, so the
  completion is never written. The nine deaths in Delhi are nine completions
  the log does not carry.

Reported upstream as *"Report the completions that never happened"*. The fix is
one clause — a fall in progress is a completion only when the state is
unchanged — and the request beside it is that the logger emit the
`EstablishedSurveillance` flag it already extracts and drops, which would make
this whole section unnecessary.

## The counterspy, which must be inferred

`CvEspionageClasses.cpp:538-582`, under `ESPIONAGE_SYSTEM_REWORK` (defined at
`_Defines.h:1441`, so this is the live branch), resolves a completed mission
on a rank difference:

```
iSpyRankDifference = (attacker rank + 1) - iCounterspyRank + 1

with a counterspy:      >2 DETECTED   2|1 IDENTIFIED   0 SPOTTED   <0 KILLED
without a counterspy:   >3 UNDETECTED   3 DETECTED     2 IDENTIFIED
```

**There is no `KILLED` branch without a counterspy.** An attacking spy cannot
die in a city its target has not garrisoned.

And the whole `iCounterspyRank` computation — `BUILDING_CONSTABLE`,
`BUILDING_AUSTRALIA_CONSTABULARY` and `BUILDING_INTELLIGENCE_AGENCY`, each
`+1`, plus a flat `+1` — sits **inside** `if (pCityEspionage->HasCounterSpy())`.
The buildings raise the *defending spy's effective rank* and are worth nothing
on their own: without a garrison they neither kill nor slow. It is Constable
and Intelligence Agency that carry the bonus in this branch, **not** Police
Station, which is what to look for in `city_snapshot.buildings`.

So the nine kills in Delhi prove a garrison the log never mentions, and the
spy is nameable: India created six spies, five appear in a city, and
`INDIA_7` — created turn 94, promoted turn 108 and 109, never located — is the
sixth. `bCounterSpyUpgrade` is set on `SPOTTED` and `KILLED`, and the first
kill in the game is turn 109.

`Espionage#counterspies(civ)` infers a garrison from three independent signals
that agree:

1. **a spy with no location** — created, sometimes promoted, never in a city;
2. **enemy spies dying in one of the civ's cities**, which the rank table says
   is impossible without a garrison there;
3. **promotions clustering with those deaths**, since the defender levels up
   on a kill.

The record carries `city` (the modal death site), `confidence` (how many
signals fired) and `spy` when a never-located spy can be named. Signal 2 alone
locates a garrison without naming it, which is the common case and still worth
having. The Netherlands has a never-located spy (`NETHERLANDS_1`) with no
deaths to corroborate it — signal 1 alone, and the record says so rather than
promoting a guess to a garrison.

`spy_killed` carries no city, so the death site is the last known tenure.
Carry `turns_since_last_seen` (4 to 13 here) so a reader can discount it.

## The coup, which has no event at all

`CvEspionageClasses.cpp:2110` — *"if success, the spy's owner becomes the ally;
if failure, the spy dies."* The fast, risky alternative to rigging elections
ten turns at a time, and the counter a rival uses against a diplomatic runaway.

- `CanStageCoup` requires the city-state to **already have an ally** — a coup
  takes an alliance, it cannot create one.
- On success the couper's influence is **swapped** with the previous ally's,
  and every other major's is cut by
  `ESPIONAGE_COUP_OTHER_PLAYERS_INFLUENCE_DROP`. Not a flat grant.
- On failure the couper's influence is set to **−10** and the spy is killed.

The logger's six `spy_*` types are `created`, `moved`, `mission_completed`,
`killed`, `promoted`, `revived`; a coup is neither a move nor a completed
mission, so nothing fires. Both outcomes must be inferred:

- **failed** — a `spy_killed` whose last tenure is in a **city-state**, with
  that civ's influence there at or near **−10** on the next
  `city_state_snapshot`. Both halves are needed: a death alone could be a
  garrisoned major, and a −10 alone has other causes (India sat at −60 at
  Harappa on turn 35, long before any spy existed).
- **succeeded** — two civs' influence at one city-state exchanging values
  between consecutive snapshots, with a `city_state_ally_changed` on the same
  turn and no `rigging_election` mission to explain it.

**Zero coups in india-diplo** — all nine kills were in Delhi, a major's city,
and no influence pair ever swapped. Both detectors ship unexercised. They also
matter to city-state influence: a successful coup moves an alliance with no
logged cause, so it is a candidate explanation for part of that feature's
residual and must be named there as one.

## The wonder-race join, and why the obvious test is the wrong one

Over ten contested wonders and thirteen contender rows, a contender held a spy
in the winner's city **exactly once** — and it is the biggest wonder loss in
the game:

```
t148  London starts the Louvre                    0 stored, 12 turns left
t148  England creates spy ENGLAND_6
t152  ENGLAND_6's surveillance completes in AMSTERDAM   (t148 + 1 + 3)
t154  Amsterdam appears building the Louvre       0 stored, 4 turns left
t157  Amsterdam 469 stored, 1 left | London 425 stored, 2 left
t158  Netherlands completes the Louvre. England loses by one turn, 425 sunk.
```

England's spy was established in Amsterdam **two turns before Amsterdam started
the wonder**, and that date is computed, not guessed: the spy was created on
148 and `1 + 3` puts its surveillance live on 152. It watched the Louvre go
from 0 to 469 hammers. London's rate over the whole build: 52, 44, 44, 46, 46, 46, 47,
47, 53 — **flat**. England had the intelligence, did not accelerate, did not
stop, and lost by a turn.

Three rules follow:

1. **"Held a spy at any point during the race" is the wrong test** — it fires
   on a spy that arrived after the race was decided. What matters is vision
   while a decision was still available.
2. **Vision usually cannot explain the start.** England committed on 148 and
   its spy did not exist until 148. Carry the span — `observed_from_turn` and
   `observed_turns` — not a boolean.
3. **The response is measurable.** `production_stored` per turn gives a rate,
   so the rate before `observed_from_turn` against the rate after is a direct
   test:

| pattern | reading | instances |
|---|---|---|
| observed, rate rises, still lost | tried to outrun it | 0 |
| observed, rate rises, won | the spy paid for itself | 0 |
| observed, `:abandoned` soon after | read the board, cut the losses | 0 |
| **observed, rate flat, lost** | **had the intelligence and pressed on** | **1 — the Louvre** |
| not observed, lost | lost a race it could not see | 12 |

**Four of five branches are unexercised** — the same footing as
`winner_finish`'s `:ahead_of_estimate` in `docs/wonder-race.md`. Worth
shipping because the one instance is the sharpest sentence available about the
largest wonder loss in the log, and because a game between humans fills the
rest.

A **third party** can hold the spy: Tibet watched Amsterdam through the
Alhambra race that Zimbabwe lost. Not the same fact — `observed_by` is a list
of civs with the contender flagged, never a boolean on the contender.

## What the log will not say, whatever is built

- **Which technology was stolen.** No API exposes it. The logger's suggested
  reconstruction — a `tech_researched` not matching the thief's `researching`
  on the turn a `gathering_intel` mission completed — is untested and must not
  ship as fact. It is also built on the completion event, which the section
  above shows is mostly artifact, so it would currently fire against turns on
  which nothing was stolen.
- **Whether a player looked at the city screen a spy opened.**
- **Gold gifts to city-states** (`CvDeal` unreachable) and **quests**
  (`MinorCivQuestTypes` is a C++ enum with no database table).
- **Paradrops joined to spy vision** — specified, and india-diplo contains
  **zero** paradrops.

## The per-civ ledger

The cheapest honest measure of who played this game at all, and the shape it
takes here:

Logged completions against what survives the artifact filter:

| civ | logged | artifact | real | unanchored | spies lost | garrisoned |
|---|---|---|---|---|---|---|
| India | 23 | 5 | **18** | 0 | 0 | yes, Delhi (inferred) |
| England | 10 | 7 | **2** | 1 | 4 | one explicit recall, t156 |
| Tibet | 6 | 3 | **0** | 3 | 3 | — |
| Iroquois | 6 | 2 | **0** | 4 | 1 | — |
| Netherlands | 4 | 3 | **0** | 1 | 1 | signal 1 only |
| Zimbabwe | 4 | 3 | **1** | 0 | 0 | — |

The qualitative split survives the correction and is the finding: **India
pointed every spy at city-states and nobody else rigged a single election;
every other civ pointed every spy at technology.** India lost no spies and
killed nine.

The quantitative split does not survive. What looked like a busy espionage war
among the other five civs is mostly postings counted twice — between them they
have **three** confirmable tech thefts, plus whatever hides behind the nine
deaths and the nine unanchored completions. The honest sentence is that the
other five civs *tried* repeatedly against Delhi and were caught; not that they
succeeded thirty times.
