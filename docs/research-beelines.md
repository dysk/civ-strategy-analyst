# Research beelines

`ResearchBeelines` and `KeyMomentDetector#research_rushes` flag a civilization
reaching one of eleven marker technologies on a suspiciously short tech
count - the signature of a beeline (research aimed at one target, ignoring
everything else on the way) rather than an organic research order.

## The bands are calibration, not measurement

Each marker's band below came from watching real LEKMOD games, not from a
statistical fit over a corpus of them. Read a hit as suggestive, not as
proof a beeline happened - and expect the bands to move as they get
checked against more logs.

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

Checked against `examples/india-diplo.jsonl`, the bands discriminate rather
than firing on everything: only India (Education, tech #18, turn 74) and
England (Navigation, tech #27, turn 118) land inside a band, out of every
civilization and every marker technology in the game.

## What each marker actually unlocks

The `marker` label names the tech's payoff, not the tech itself - but the
label is prose written by hand, and one of the eleven is wrong outright.
The table below is resolved against the mod source, the same way the
marker tech ids are: `PrereqTech` on the `<Units>`/`<Buildings>` rows in
`Override/CIV5Units.xml`, not guessed from the label or from vanilla BNW
(LEKMOD moves things - Infantry now needs Electronics instead of
Plastics, `general.md`'s "Changes to Individual Units" - so a vanilla
assumption is not evidence here).

| marker | tech | what actually unlocks | why it matters |
|---|---|---|---|
| `crossbows` | Machinery | `UNIT_CROSSBOWMAN` (Crossbowman) | the first ranged unit that outclasses anything a civ still on Composite Bowmen or Pikemen can field |
| `universities` | Education | `BUILDING_UNIVERSITY` (University), plus the Oxford University national wonder it opens | economic, not military - but not harmless. Being first to a science building compounds: the extra beakers buy the next tech, and the next science building, faster than a rival still without it, so a first-to-Education hit widens the gap every turn after rather than just marking one lead |
| `frigates` | Navigation | `UNIT_FRIGATE` (Frigate), alongside the Privateer | colonial-era naval dominance and coastal raiding |
| `public_schools` | Scientific Theory | `BUILDING_PUBLIC_SCHOOL` (Public School) | economic - the same compounding as `universities`, one tier further in. A civilization first here is stacking a second science building's lead on top of whatever gap the first one already opened |
| `artillery_cavalry` | Dynamite | `UNIT_ARTILLERY` (Artillery) only | **the label is wrong.** Every unit with `PrereqTech=TECH_DYNAMITE` is `UNIT_ARTILLERY`, `UNIT_COLORADO` (a US unique) or `UNIT_ROCKET_CORPS` (a Korean unique) - no cavalry unit unlocks here. Read this hit as an Artillery beeline, never mention cavalry when narrating it. Artillery itself has Range 3 against a Cannon's Range 2, and its AI role (`UNITAI_CITY_BOMBARD`) is built around sieging cities. Paired with Cavalry the civ already has (Cavalry needs Military Science, well earlier in the tree than Dynamite), Artillery's range softening a target for Cavalry to run down is a hard-to-stop combination worth narrating as one threat. |
| `research_labs` | Plastics | `BUILDING_LABORATORY`, displayed as "Research Lab" | economic; the third rung of the same compounding as `universities` and `public_schools` - a civilization first here has been stacking science-building leads since Education. The band itself is a single value (`{42, 42}`), the only zero-width band of the eleven - see "The `research_labs` band is a single point" below, it does not match either example log that reaches Plastics |
| `planes` | Flight | `UNIT_TRIPLANE` (fighter class) and `UNIT_WWI_BOMBER` ("Great War Bomber") | the sharpest military marker of the eleven. Nothing on the ground can touch either unit at all - the Fighter upgrade needs Radar and the Anti-Aircraft Gun needs Ballistics, both many techs further out. Early on, the only real counter is a rival fielding its own planes. |
| `battleships` | Electronics | `UNIT_BATTLESHIP`, `UNIT_CARRIER`, and (LEKMOD-specific) `UNIT_INFANTRY` | a triple spike, not one ship - strongest capital ship, air power projection, and the era's core defensive infantry all land on the same tech |
| `landships` | Combustion | `UNIT_WWI_TANK`, displayed as "Landship", and `UNIT_DESTROYER` | Landship is the first Armored-class unit, and LEKMOD gives Armored units +50% vs. land units (`general.md` line 134) - a rush here is a steamroll against anyone still fielding Riflemen or Cavalry. Not undefended, though: Combustion requires Railroad, and Railroad alone unlocks the Anti-Tank Rifle (+200% vs. Armored per `general.md`), and planes counter Landships as readily as anything else on the ground. |
| `the_internet` | The Internet | **nothing material.** No unit or building has `PrereqTech=TECH_INTERNET`; the tech's own row carries `InfluenceSpreadModifier +100%` | the odd one out - this is a Culture/Tourism spread-rate doubling, not a unit or building. A hit here signals a Cultural Victory push, not military aggression, and should never be narrated the way the other ten are |
| `stealth_bombers` | Stealth | `UNIT_STEALTH_BOMBER` | 20-tile range, 85 ranged combat - a strike with effectively no interception window |

## The `research_labs` band is a single point

Every other marker's band spans 2 to 5 techs (Machinery: 15-17, Education:
16-19, Internet: 57-61...). `research_labs` alone is `{min: 42, max: 42}` -
zero width, a single integer with no tolerance either side.

Only two of the five example logs ever reach Plastics at all, and neither
lands in the band: Babylon (`babylon-domination.jsonl`, turn 155) reached
it on its 50th tech, India (`india-diplo.jsonl`, turn 138) on its 46th -
`distance_to_band` of +8 and +4, both comfortably late rather than a
near-miss. That is not evidence the band is wrong on its own; neither game
is plausibly racing for Research Lab, so a real beeline landing near a
narrower target is still consistent with what is here. But it does mean
this repo's own example corpus supplies zero corroborating data point for
`42` - unlike the other ten markers, which the "bands are calibration, not
measurement" section above can at least point to a game for, this one
rests entirely on whatever external games it was calibrated from.

A zero-width band is also a much harder needle to thread than any other
marker's: research order can shift a tech count by one from a single
research agreement, city-state science bonus, or ruin pickup that has
nothing to do with whether the civilization was actually beelining
Plastics. Treat a miss by exactly one tech here with real suspicion that
the band should be `{41, 43}` or wider rather than that no rush happened -
and if a future log shows a genuine Plastics rush landing one tech off
`42`, that is grounds to widen the band, not to dismiss the hit.

## Tech count basis

The tech count a marker is measured against is the number of
`tech_researched` events crediting the civilization, up to and including
the turn it researched the marker tech - not `snapshot.techs` on that
turn, and not `tech_researched` plus `tech_from_ruins`.

`snapshot.techs` disagrees with the event count by one or two on the same
turn, because a snapshot is stamped at the player's turn start and a tech
taken during that turn may or may not be reflected in it yet. The event
count is unambiguous: a `tech_researched` event exists or it doesn't.

`tech_from_ruins` is not a second acquisition path to add to
`tech_researched`. It fires *alongside* `tech_researched` for the same
tech, purely as an auxiliary marker of how the tech was obtained -
England's Mining at turn 9 in india-diplo logs both. Counting it as
additive double-counts every tech a civilization got from a ruin,
overstating that civilization's tech count for the rest of the game.

## Roster

`tech_researched.civs` lists city-states alongside majors - every
city-state in the game "researches" the same tech on the same turn a
major does, since they share the tech pool. `KeyMomentDetector#research_rushes`
restricts its civ loop to `game.players`; `ResearchBeelines#markers_reached`
itself takes an explicit civ and is safe by construction, the same
contract `TradeRoutes` and `YieldAttribution` use.

## Marker technology ids

The eleven marker ids were resolved against a checkout of the LEKMOD mod
source, not guessed from their in-game names - `TECH_PLASTIC`, not
`TECH_PLASTICS`. The `<Technologies>` table itself sits, unmodified from
vanilla BNW, inside `Override/CIV5Units.xml` rather than a file named for
it - the same misfiled-table trap `db/lekmod/README.md` documents for
Resolutions and Buildings. `db/lekmod/<version>/technologies.yml`
(generated by `script/extract_lekmod_technologies`) exists to make that
resolution auditable; the eleven ids themselves are hardcoded in
`ResearchBeelines::MARKERS`, the same way `KeyMomentDetector::BRANCH_POLICIES`
hardcodes a small, pre-verified table rather than resolving it at runtime.
