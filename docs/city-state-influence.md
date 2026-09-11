# City-state influence attribution

Execution plan for one feature. `docs/plan.md` keeps the project-wide
iteration history; `docs/reading-the-new-log.md` §5 is this feature's full
design; this file carries the one number it depends on.

## The +45 per rig

`CityStateStanding#attribution` splits the influence a civ bought at a
city-state into what the log explains and what it does not. Two causes are
logged: decay, from the `per_turn` rate `city_state_snapshot` already reports,
and election rigging, from `spy_mission_completed` with
`state: "rigging_election"`. Rigging moves influence by an amount the log
never states directly — a spy mission completing names the kind, not the
effect — so the effect has to be measured.

**Measured against `examples/india-diplo.jsonl`, Ljubljana: eight rigs, ten
turns apart, against a decay of −1.25 per turn.** The influence climb across
those eight instances, with the decay in between subtracted out, averages
**+45** per rig. That is the constant `CityStateStanding::RIG_GAIN`.

Like `BufferCities::NEIGHBOUR_DISTANCE` (17 hexes, `docs/buffer-city.md`),
this is a **first calibration off one game**, not a game-engine constant
looked up in the DLL. `CvMinorCivAI::DoRigElection` scales the swing with the
city-state's population and the spy's rank, so +45 is an average, not a
floor or a ceiling, and it is expected to move once a second game with
rigging in it is imported. Revisit it there.

## What the residual is, and is not

`attribution`'s `unexplained` field is `(gain − decay) − explained`, and it
is deliberately never labelled with a cause. On the reference game about half
of India's total bought influence across its eleven city-states falls here.
Three things are known to live in it, and none of them are logged directly:

- **gold gifts** — `CvDeal` is unreachable from Lua
- **quests** — `MinorCivQuestTypes` is a C++ enum with no database table
- **a successful coup** — `Espionage#coups` can name a specific one, when its
  signature (an alliance changing hands with no rigging event, and two civs'
  influence trading places) matches, but a coup that misses the signature —
  or whose target city-state's log the projection was never asked about —
  still lands here uncredited

The prompt must present `unexplained` as a residual with candidate causes,
never as a single attributed one.
