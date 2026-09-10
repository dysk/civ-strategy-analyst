# Espionage

Execution notes for one feature. `docs/plan.md` keeps the project-wide
iteration history and `docs/reading-the-new-log.md` the ordering; this file
holds the game rules the projection rests on, the inferences it is forced
into, and the honest limits on both.

Two games are measured here. `examples/india-diplo.jsonl` predates every
logger fix and is what the fallbacks are calibrated on.
`examples/espionage-test.jsonl` was played to
`civ-narrative-logger/docs/capture-protocol.md` against the fixed logger,
with espionage used deliberately — turns 82–189, five sessions, a
counterspy, four rigging cycles and a failed coup. Where a mechanism is
specified but neither game exercised it, the text says so.

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
open.

**The logger now records that turn directly.** As of `civ-narrative-logger`
*"Stop trusting a progress fall on its own to mean a mission finished"*, a
`spy_surveillance_established` event fires the turn a spy's
`HasEstablishedSurveillance` flag goes false → true, carrying
`{civ, spy, turn, city, city_civ}`. One per posting, roughly 39 a game. That
event **is** `visible_from_turn` — a logged fact, not a reconstruction — for
every log written after the fix.

`examples/india-diplo.jsonl` predates it and carries no such event, so the rest
of this section is the fallback the projection still needs for that game and
the two older ones. The delay is **computable** because both terms are
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

**The constant is measured, not just derived.** In `espionage-test.jsonl`
fifteen postings reach a `spy_surveillance_established`, and **every one of
them lands on posting + 4** — no spread, no exceptions. Nobody in that game
held Familiar+ influence over a target, so the 2-turn branch stays
unexercised and the projection must still read the level rather than assume
the 4. The old log corroborates from the other side: in india-diplo the first
`spy_mission_completed` after a posting lands at **+3 or +4 in 14 of 18
postings**, which is that formula surfacing as a false completion.

A **counterspy is the exception**: it needs no surveillance, so its posting
takes effect at **+1**, the travel turn alone. Five `counter_intel` postings
in `espionage-test.jsonl`, none of them followed by a surveillance event.

So four dating rules, in descending order of what they may be used for:

- **Logged** — `spy_surveillance_established` in city C on turn T.
  Authoritative wherever the event is present. This is `visible_from_turn`.
- **Computed** — `posting + 1 + surveillance_time`. The fallback for logs
  predating the event; exact when the posting is known, which is 13 of 24
  spies in india-diplo.
- **Certain floor** — a `spy_mission_completed` in city C on turn T proves
  surveillance was live in C on T, because those mission states imply it
  (`CvEspionageClasses.cpp:1795`). Used when both of the above are missing —
  the posting was lost — and then `visible_from_turn` is a **lower bound**
  with `visible_from_turn_bounded: true` on the record.
- **Never** — a `spy_moved` turn on its own. It is the order to go, not the
  arrival, and it is never used unadjusted.

None of the four says the player looked.

## Tenure, and what the log loses

A tenure is a maximal run of sightings of one spy in one city. Over
india-diplo that is 24 spies with a location and 39 tenures.

**The spy's name is not its identity.** The DLL draws a fresh name when a spy
revives, and the logger's record carries `spy = row.Name` rather than the
`AgentID` it keys on internally. Arabia's `ARABIA_0` died at Valletta on turn
181 and came back on 186 as `ARABIA_8`; in india-diplo **all eight** revivals
name a spy that was never created — `ENGLAND_0`, `ENGLAND_1`, `ENGLAND_4`,
`CHINA_0`, `CHINA_5`, `CHINA_9`, `IROQUOIS_6`, `NETHERLANDS_2`.

So `(civ, spy)` is the wrong key. A death orphans a tenure and the revival
opens a new one for a spy that appears from nowhere, and two live spies of one
civ can in principle collide on a recycled name. Until the logger emits
`AgentID` (reported upstream as *"A stable spy identity"*), `Espionage` keys
on `(civ, spy)` **and treats a `spy_revived` naming an unknown spy as a new
spy**, which is wrong but is the only reading the log supports — `capacity`
must therefore report revivals separately from creations rather than netting
them. It also disposes of a puzzle: several of india-diplo's "spies that were
never located" are revivals of spies it knew under other names.

**The logger loses postings**, and the projection is built knowing it:

- 11 of those 24 spies are first located by a `spy_mission_completed`, not by
  a `spy_moved` — their arrival was never written.
- `ENGLAND_6` moved Amsterdam (t152) → Osininka (t168) with no `spy_moved`
  between, so re-postings are lost too.
- `spy_created` carries no location (0 of 18) and `spy_killed` carries none
  either (0 of 9), though the DLL holds one in both cases.

Reported upstream in `civ-narrative-logger/docs/planned-changes.md`, *"Let a
counterspy leave a trace"*. **Mostly fixed:**

- *"Stop trusting a progress fall…"* gave `spy_created` and `spy_killed` a
  `city`/`city_civ` (read from the last live poll for the kill, since the DLL
  empties the record before `SPY_STATE_DEAD`), and `spy_surveillance_established`
  now anchors many arrivals the move event missed.
- *"Give a revived or homebound spy back its posting"* closed the **revival**
  half of the `spy_moved` gap: `diffSpy` no longer returns straight after
  `spy_revived`, so a spy that revives already in a city now emits its posting.

Still open is the rest of the `spy_moved` gap — **re-postings** (`ENGLAND_6`
above) and a `spy_moved` lost mid-`MoveSpyTo` when a poll catches `CityX == -1`
— which needs upstream instrumentation first. india-diplo predates all of it,
so for that game a tenure's `from_turn` is the first sighting, **not** the
arrival, and every span is a lower bound on how long the spy was actually
there.

## Most logged missions did not happen — in logs written before the fix

`completed()` in the logger used to read any fall in `PercentComplete` as a
finished mission, but progress also restarts at a **state transition** —
travelling, surveillance and gathering intel share one `amount / goal` counter
and each new state begins it at zero (`CvEspionageClasses.cpp:2474-2487`).
Surveillance finishing therefore read as a mission finishing, at exactly
`posting + 1 + surveillance_time`.

**Fixed upstream** in *"Stop trusting a progress fall on its own to mean a
mission finished"*: `completed()` now also requires `known.state == spy.state`,
and the transition it used to mislabel is emitted as
`spy_surveillance_established` instead. Logs written after that fix carry
neither the artifact nor the need for the filter below — `missions(civ)` can
count `spy_mission_completed` straight. The rest of this section is what
`examples/india-diplo.jsonl` and the two older logs still require.

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

**What the projection must do about it, for a pre-fix log.** Filter a
completion that lands 3 to 6 turns after that spy's last posting or creation in
the same city, and count it as the surveillance moment instead of a mission.
Where no anchor survived, carry the completion with `anchored: false` — it may
be either — and never let an unanchored count reach a prompt as a bare number.
A `spy_surveillance_established` on the same spy and turn makes the filter
exact rather than a window; its absence is how the projection knows it is
reading a pre-fix log at all.

Two consequences worth stating plainly:

- **Mission counts are upper bounds in india-diplo**, and the per-civ split
  there is unreliable for every civ but India.
- **A kill still hides a completion, in every log.** The roll that kills a spy
  happens *at* `HasReachedGoal`, and `diffSpy` takes the `dead` branch before
  `completed()`, so the completion is never written — the fix above did not
  change this. The nine deaths in Delhi are nine completions the log does not
  carry.

Reported upstream as *"Report the completions that never happened"* and fixed
there; this section applies only to logs written before that commit.

## The counterspy — read in a post-fix log, inferred in india-diplo

**Post-fix logs record the garrison, and this is measured.** *"Give a revived
or homebound spy back its posting"* made `spy_moved` fire on the transition
into `counter_intel` with a city present, even when the coordinates did not
change — the one case a counterspy could previously produce no event at all.
`espionage-test.jsonl` carries five such records, each in one of its owner's
own cities and none followed by a surveillance event or a completion. So in a
post-fix log a counterspy is a `spy_moved` with `state: "counter_intel"`, and
`Espionage#counterspies` reads the garrison city and the spy straight off it.

Two things that reading has to allow for. A counterspy is **not** silent
forever, only while it stays put: the Sioux oscillated one spy between
Ihankthunwanna and Isanyathi four times in ten turns, and each leg is a real
posting, so a garrison is a *span* like any other tenure and a civ can hold
none for stretches in between. And a garrison spy's progress is always nil, so
it can never produce a completion — `state` is the only discriminator.

The three-signal inference below is the fallback for india-diplo, which
predates the fix and mentions no counterspy anywhere.

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

`Espionage#counterspies(civ)`, where no `counter_intel` `spy_moved` is present,
infers a garrison from three independent signals that agree:

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

In india-diplo `spy_killed` carries no city, so the death site is the last
known tenure; carry `turns_since_last_seen` (4 to 13 here) so a reader can
discount it. Post-fix logs put `city`/`city_civ` on the kill directly, taken
from the last live poll, and `turns_since_last_seen` is then 0.

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

**The failure detector is now measured, and the penalty is exactly −10.**
Arabia posted `ARABIA_0` to Valletta on turn 177 and it died on 181 with no
counterspy near it — the exception to the rank table above, since the kill
happens inside `AttemptCoup` and not in the mission resolution. Arabia's
influence at Valletta, absent from the turn-178 snapshot, reads **−8 at turn
182 with `per_turn` +1.25**, which is −10 on the turn of the kill with one
turn of recovery already applied. No `city_state_ally_changed`. The detector
must therefore compare against the **decayed** value, not a literal −10:
`influence + per_turn × (snapshot_turn − kill_turn)` at or near −10.

**Zero *successful* coups in either game**, so that half ships unexercised.
In india-diplo there were no coups at all — all nine kills were in Delhi, a
major's city, and no influence pair ever swapped. They also
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
148 and `1 + 3` puts its surveillance live on 152. (A post-fix log would carry
a `spy_surveillance_established` for `ENGLAND_6` in Amsterdam on turn 152 and
this would be read, not derived.) It watched the Louvre go from 0 to 469
hammers. London's rate over the whole build: 52, 44, 44, 46, 46, 46, 47, 47,
53 — **flat**. England had the intelligence, did not accelerate, did not stop,
and lost by a turn.

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

| pattern | reading | india-diplo | espionage-test |
|---|---|---|---|
| observed, rate rises, still lost | tried to outrun it | 0 | 0 |
| observed, rate rises, won | the spy paid for itself | 0 | 0 |
| observed, `:abandoned` soon after | read the board, cut the losses | 0 | 0 |
| **observed, rate flat, lost** | **had the intelligence and pressed on** | **1 — the Louvre** | **1 — Pisa** |
| not observed, lost | lost a race it could not see | 12 | 9 |

**Three of five branches are unexercised across two games.** Both live
instances are the same branch, which is itself worth saying: in twenty-two
contender rows nobody who could see a race they were losing ever changed what
they were doing about it.

A **third party** can hold the spy: Tibet watched Amsterdam through the
Alhambra race that Zimbabwe lost, and in `espionage-test.jsonl` four other
civs watched Mecca build Pisa. Not the same fact — `observed_by` is a list of
civs with the contender flagged, never a boolean on the contender.

### Pisa, and the two near-misses that vindicate the dating

`espionage-test.jsonl` repeats the Louvre with the events logged rather than
reconstructed:

```
t143  spy_surveillance_established — Belgium's FRANCE_3 in MECCA
t156  Brussels starts Pisa                    0 stored, 6 turns left
t157  Mecca appears building Pisa           111 stored, 2 turns left
      Brussels                                65 stored, 5 turns left
t158  Mecca 214 stored, 1 left | Brussels 109 stored, 4 left
t159  Arabia completes Pisa. Belgium loses, 155 sunk.
```

Belgium's rate: 65, 44, 46 — **flat**, again. The start is not the informed
decision here (Mecca had nothing queued on 156); the three turns of continuing
are, and Mecca showed *two turns left* against Brussels' five from 157 on.

The same race carries the case the naive test would get wrong. **Mysore also
lost Pisa**, and Mysore had a spy in Mecca: `MUGHAL_5` was posted there on
t155. Its surveillance completed on **t159** — the turn Pisa was finished.
"Held a spy in the winner's city during the race" answers *yes* for Mysore and
is wrong: Mysore sank 89 hammers blind and could not have seen a thing while
a decision was still available. The Sistine Chapel repeats it — Mysore's
`MUGHAL_0` got vision of Brussels on t160, the completion turn.

Two near-misses in one game, both produced by the four-turn delay alone. That
is the argument for `visible_from_turn` over `from_turn`, and it is no longer
theoretical.

## What the log will not say, whatever is built

- **Which technology was stolen.** No API exposes it. The logger's suggested
  reconstruction — a `tech_researched` not matching the thief's `researching`
  on the turn a `gathering_intel` mission completed — is untested and must not
  ship as fact. On a pre-fix log it is also built on the completion event that
  the section above shows is mostly artifact, so it would fire against turns on
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

### The same ledger from a post-fix log

`espionage-test.jsonl` needs no artifact filter and no counterspy inference,
which is the whole point of the fixes. Twenty-four completions over turns
132–189, all of them real:

| civ | completions | kind | postings | counterspy | spies lost |
|---|---|---|---|---|---|
| Jerusalem | 8 | intel, all in Mecca | 2 | — | 0 |
| Arabia (human) | 4 | rigging, all in Reykjavik | 4 | — | 1 (coup) |
| Sioux | 4 | intel, all in Mecca | 9 | yes, 3 spans | 0 |
| Belgium | 3 | intel, all in Mecca | 5 | — | 0 |
| Yugoslavia | 4 | intel | 4 | — | 0 |
| Mysore | 1 | intel | 5 | yes, 2 spans | 0 |

Every AI pointed its spies at Mecca, the human's capital, and only the human
rigged an election. The rigging cadence is the clearest signal in either log:
turns 151, 161, 171, 181 — ten turns apart to the turn, four cycles, which is
what a genuine repeat looks like once the transition artifact is gone.

Two cautions carried forward. Jerusalem's `GREECE_4` appears only as a
surveillance event on turn 186, with no creation and no posting: it came into
existence inside a reload seam, and the first poll of a session is silent by
design. And the Sioux's nine postings are mostly one spy oscillating between
two of its own cities, so a posting count is a count of orders, not of
distinct operations.

`espionage-test.jsonl` also carries 1957 `city_snapshot` records with
`producing` on 1852 of them, which makes it the **second** log
`WonderRaces` and `CityValue` are applicable to, and the first that is not
india-diplo.
