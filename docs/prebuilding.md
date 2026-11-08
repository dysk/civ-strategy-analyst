# Prebuilding

Execution plan for one feature. `docs/plan.md` keeps the project-wide
iteration history; this file is the detailed plan for this change alone.

## Context

A prebuild banks production in a unit before the moment it is needed, so
the unit appears a turn or two after the decision instead of a full build
later. It matters most where building takes many turns and fighting does
not, which is a slow game speed (see `docs/game-speed.md`): a defender who
starts training when the attack lands may lose a city before the first
unit is out.

The analyzer sees none of it today. A prebuilt army reads as a sudden
`army_power_surge` with no cause attached.

## Ground truth

From `LEKMOD_DLL/CvGameCoreDLL_Expansion2/CvCity.cpp` and
`LEKMOD/Override/CIV5Units.xml`:

| Rule | Source | Value |
|---|---|---|
| Progress is stored per unit type, not per city | `m_paiUnitProduction` | switching away keeps it |
| A unit untouched for this many turns starts decaying | `UNIT_PRODUCTION_DECAY_TIME` | 10 turns |
| Each decaying turn keeps this share | `UNIT_PRODUCTION_DECAY_PERCENT` | 98% |
| A queued unit made obsolete hands its progress to the upgrade | `doCheckProduction_UpgradeUnit` | full transfer |
| Buildings decay after | `BUILDING_PRODUCTION_DECAY_TIME` | 50 turns, 1% a turn |

The decay clock is flat across speeds. On a slow speed a bank waits longer
for the next tech, so decay costs it more, while the turns it saves are
worth more.

The upgrade transfer needs the obsolete unit in the queue
(`getFirstUnitOrder`). It does not fire for a bank left idle.

## What the log carries

`city_snapshot`, one per city per turn, from
`civ-narrative-logger/src/adapter.lua` `cityCore`:

- `producing`, `producing_kind`
- `production_stored` (`city:GetProduction()`, the current item only)
- `production_turns_left`, `yield_production`

Only 15 of 35 imported games carry city snapshots. A projection gated on
them reports `applicable?` the way `WonderRaces` does.

## Two signatures

1. **Upgrade carry-over.** `producing` changes from unit A to unit B on a
   turn the civ researched the tech that obsoletes A, `production_stored`
   does not reset, and B completes within a turn or two.
2. **Bank return.** `producing` switches back to a unit the city worked on
   earlier, and `production_stored` jumps well beyond one turn of
   `yield_production`. The unit completes soon after.

`WonderRaces#rates` and `ACCELERATION_FACTOR` already read jumps in
`production_stored`. Reuse that shape rather than a second definition of
"a jump".

## Known gaps

- **Banks are invisible until they return.** The snapshot reports only
  the current item, so hammers sitting in another unit show up only on
  the turn the city switches back.
- **A forest chop looks like a bank.** It adds hammers to the current item
  and the logger records no feature removal. Signature 2 cannot tell them
  apart unless the switch back happens on the same turn, which a chop
  does not need.
- **Snapshot timing.** Whether a snapshot is taken before or after the
  turn's production is applied decides whether the completion turn shows
  the full bank. Confirm against one game before calibrating anything.
- **Purchases.** A bought unit completes with no production story. It
  must not be mistaken for a prebuild; check how a purchase appears in
  `unit_created`/`unit_trained` first.

## Steps

Each step is one TDD cycle — failing tests first, left unstaged for
review, then the smallest implementation that greens them, then one commit
holding both.

### 1. Confirm the log against the rules

No code. Pick one game with snapshots and one known prebuild, if the
player remembers one, and check snapshot timing, a chop and a purchase by
hand. Record the findings here.

### 2. Upgrade carry-over

- `Prebuilds` projection, `applicable?` gated on city snapshots.
- An entry per carry-over: `civ`, `city`, `turn`, `from_unit`,
  `to_unit`, `carried` (stored production at the switch), `completed_turn`.
- Tests: a carry-over on the tech turn; a switch with stored reset to 0 is
  not one; a switch between unrelated units is not one.

### 3. Bank return

- Same projection, `kind: :bank_return`, with `banked` (the jump beyond
  `yield_production`) and `turns_saved` (`banked / yield_production`).
- Tests: a return with a jump; a return without one is not a prebuild; a
  jump without a return to an earlier item is not one.

### 4. Digest and prompt

- `DigestBuilder` carries `prebuilds.by_civ.<civ>`.
- `analyze_game.md` reads a prebuild as preparation, weighs it more on a
  slow speed, and links a cluster of prebuilds to a following war or
  `army_power_surge`.

## Not in scope

- **Buildings and wonders.** The same per-item storage applies, but the
  question here is military readiness.
- **Gold reserves as readiness.** Treasury held before a war is the other
  half of being ready, and belongs in the prompt's war reading, not here.
