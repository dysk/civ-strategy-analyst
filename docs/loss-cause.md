# Reading `cause` and `confidence` on `unit_lost`

Execution plan for one feature. `docs/plan.md` keeps the project-wide
iteration history; this file is the detailed plan for this change alone.

## Context

`unit_lost` fires on every unit removal, whatever the reason — a combat
death, a great person spent, a settler founding a city, a caravan
completing its route. Both `PlayerTimeline` and `WarCasualties` work
around that with heuristics of their own, and both say so in their
comments.

Some logs already carry the answer. `cause` and `confidence` are **not**
written by the in-game logger; `civ-narrative-logger`'s
`tools/reconcile-unit-lost.jq`, run through `tools/pipeline.sh`, adds them
after the fact. Presence is therefore per-file and all-or-nothing — in
`examples/`, `babylon-domination` and `chile-vs-vietnam` carry them on
every `unit_lost` row, while `india-diplo`, `espionage-test` and
`run-b-test` carry none. `docs/reading-the-new-log.md` measured everything
against `india-diplo`, which is why this never came up.

What the tool writes, across the two reconciled logs:

| `cause` | `confidence` | Rows | How it was decided |
|---|---|---|---|
| `killed` | `confirmed` | 336 | `killed_by` present, or matched one-for-one against a `unit_killed` record |
| `killed` | `inferred` | 198 | By elimination: a combat unit matching no other rule, so `killer: "Barbarians"` |
| `used_up` | `confirmed` | 391 | Caravan, cargo ship, work boat or missionary finishing its one job |
| `expended` | `confirmed` | 107 | A `great_person_expended` for the same `(civ, turn, unit)` |
| `founded_city` | `confirmed` | 51 | A settler and a `city_founded` on the same tile |
| `city_captured` | `confirmed` | 1 | A `city_captured` on the same tile, this civ as `old_owner` |

Two facts about the fields the code does not read:

- **`killer`, not `killed_by`.** Every killed row carries `killer`. Only
  75 of the 336 confirmed kills also carry `killed_by`, because the hook
  populates that one for civilian capture alone. The analyst reads
  `killed_by` exclusively, so 261 named killers are invisible to it, and
  `lost_row`'s `fate: killed_by ? :killed : :disbanded` calls those deaths
  disbandments.
- **`cause: expended` is exact for great people.** 107 rows, and
  great-person units account for all 107. The upstream join matched the
  unit as well as the turn, which is the one thing
  `PlayerTimeline#great_people` cannot do.

## Is it worth using

Yes, as a correctness and simplification change, not as a flood of new
data. Measured, not estimated:

1. **The expend/loss echo stops being a guess.** `great_people` drops a
   loss that falls on an expend turn for the same civilization, because
   the log gives no per-unit identity. Against the reconciled logs that
   rule is wrong once in 111 great-person loss rows — Austria's scientist,
   killed by Babylon on turn 192, discarded as an echo because Austria
   expended another great person that turn. One case, but the correct
   answer is sitting in the file, and taking it deletes the compromise.
2. **A killer with no `killed_by` stops being a disbandment.** No great
   person in these two logs takes that path, but 261 ordinary units do, so
   the path is live and the fate is simply wrong when it fires.
3. **Barbarians become countable.** 198 inferred kills, 195 of them combat
   units, so the inference is clean. They do not change
   `WarCasualties#during`, because `across_the_front?` counts a casualty
   only when the killer sits on the other side of a war between majors.
   They answer what the barbarians cost an empire, which nothing answers
   today.
4. **Three more guesses retire.** `used_up` and `founded_city` confirm
   which `unit_lost` rows are not casualties at all — the risk
   `WarCasualties`' own header warns about. `city_captured` names a
   capture outright, where `CIVILIAN_UNITS` currently infers it from the
   unit type.
5. **`confidence` lets the prose hedge** instead of asserting a barbarian
   kill as flatly as a logged one.

## Risk

The tool's `great_person_types` list holds the nine vanilla great people
and omits `UNIT_DALAILAMA`, `UNIT_MABA`, `UNIT_FAKEPROPHET`,
`UNIT_ITALARTIST`, `UNIT_LEU_COMPARSA_FOLKLORICA` and
`UNIT_VENETIAN_MERCHANT`. An expend of one of those matches no rule and
falls through to the barbarian branch, arriving as
`cause: killed, killer: "Barbarians", confidence: "inferred"`. India's two
Dalai Lama expends would read as barbarian kills if that log were
reconciled. So `cause` is authoritative except on units outside that list,
and the list needs fixing upstream.

## Steps

Each step is one TDD cycle — failing tests first, left unstaged for
review, then the smallest implementation that greens them, then one commit
holding both.

### 1. One place that reads the fields

- A `UnitLosses` projection: `applicable?` is true when any `unit_lost`
  carries `cause`, and it answers `cause`, `confidence` and `killer` per
  event, following the existing `applicable?` convention
  (`CityCensus`, `Religion`, `TradeRoutes`).
- It treats a unit outside the reconciler's great-person list as
  unclassified rather than trusting `inferred` on it, and names the reason
  in a comment.
- Tests: applicable on a reconciled fragment, not on a raw one; a Dalai
  Lama expend labelled `killed/inferred` upstream comes back unclassified.

### 2. Great-person fates

- `great_people` asks `UnitLosses` first — `expended`, `used_up` and
  `founded_city` are not losses, `killed` is a kill whether or not
  `killed_by` is set, and `killer` fills `killed_by` in the row where the
  payload has none.
- The same-turn dedup stays as the fallback for unreconciled logs, and its
  comment says that it is the fallback.
- Tests: Austria's turn-192 scientist survives as `fate: :killed`; an
  expend on a turn with a loss of a different kind yields one expend and
  one kill; an unreconciled fragment behaves exactly as it does today.

### 3. Casualties and barbarians

- `WarCasualties` admits a kill whose killer came from `killer`, and
  carries `confidence` on the casualty row so a chronicle can hedge.
- `cause` decides captured against killed where it is present, with
  `CIVILIAN_UNITS` as the fallback.
- Barbarian losses get their own tally per civilization, outside
  `#during`, because they belong to no war, and `DigestBuilder` exposes it
  as `barbarian_losses` beside the wars.
- Tests: an inferred barbarian kill counts in the barbarian tally and in
  no war; a `used_up` caravan counts nowhere; a `city_captured` row counts
  as captured without consulting `CIVILIAN_UNITS`.

### 4. Moments and weight

- `KeyMomentDetector#great_people_lost` picks up a kill with no
  `killed_by`, carrying `killer` and `confidence`.
- `ChronicleSpine` weighs an inferred kill the same as a confirmed one;
  the hedging belongs in the prose, not the weight.
- Tests: a great person killed by barbarians with no `killed_by` becomes a
  moment.

### 5. Prompts

Three passages. Drafts below, in each prompt's own voice.

#### 5.1 `analyze_game.md` lines 498-507, a war's toll

> - `toll` gives, per side, `losses`/`loss_types` (units that died),
>   `kills`/`kill_types` (units it destroyed), and `captured`/`seized` with
>   their types (civilians lost and taken). Only combat deaths and captures
>   count. The types say what fell, never what killed it. Read the two
>   sides' `loss_types` against each other. Riflemen dying to a side that
>   lost nothing explains an outcome better than any power figure.
> - `confidence`, where a casualty carries it, says how the death was
>   established. `confirmed` means the game's own combat record or the
>   loss itself named the killer. `inferred` means no record named one and
>   the attribution follows by elimination. Weigh an inferred casualty the
>   same as a confirmed one in a count, and hedge it in a sentence that
>   turns on it alone.
> - `toll` absent `confidence` on every casualty means the log was never
>   reconciled, not that the deaths are in doubt. Never remark on its
>   absence.

#### 5.2 `analyze_game.md`, a new field beside the wars

`barbarian_losses` belongs with the empire's costs rather than inside any
war, since no war holds it:

> **`barbarian_losses`.** Per civilization, the units lost to barbarians
> and the turns they fell, where the log carries attributed losses at all.
> Barbarians are terrain, not a rival — never give them an intent, a
> strategy or a campaign. A run of them early is a start position that cost
> military production a safer one would not have asked for, and that is the
> only verdict they support. Absent for a log without attributed losses,
> which is not the same as a game without barbarians.

#### 5.3 `analyze_game.md` line 333, a great person's fate

> - `fate` is `expended`, `killed` (with `killed_by` where the record names
>   a killer, which includes `Barbarians`) or `disbanded`. A `disbanded`
>   great person left play with nothing recorded against it. On a log that
>   carries attributed losses, `disbanded` is a real disbandment; on one
>   that does not, it may be an unrecorded death, so do not build a verdict
>   on a single disbandment there.

#### 5.4 `chronicle_game.md`, hedging a death

> Where a death is marked `inferred`, no record named the hand that dealt
> it and the attribution follows by elimination. Write it as the chronicle
> writes anything it half-knows — the unit fell, the raiders are the likely
> cause, the record does not say. Never name a rival realm as the killer on
> an inferred death, and never let a passage's turn rest on one alone.

### 6. Upstream, in `civ-narrative-logger`

- Add the six missing units to `great_person_types` in
  `tools/reconcile-unit-lost.jq`, with a test fragment covering a Dalai
  Lama expend.
- Consider widening `consumed_types`, which omits `UNIT_VENEZ_CARAVAN`,
  `UNIT_VENEZ_CARGO_SHIP` and `UNIT_INQUISITOR`; three civilians land in
  the inferred bucket across the two logs, which is the same leak on a
  smaller scale.
- Separate project, separate commit.

## Not in scope

- Re-reconciling the three older example logs. The tool is deterministic
  and the pipeline is one command, but regenerating fixtures changes test
  baselines across several projections, so it is its own change.
- Asking the logger to write `cause` in-game. The post-processing join
  needs the whole file, which a hook running mid-turn does not have.
