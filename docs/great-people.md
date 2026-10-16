# Great people: what the ruleset actually allows

Execution plan for one feature. `docs/plan.md` keeps the project-wide
iteration history; this file is the detailed plan for this change alone.

## Context

`PlayerTimeline` labels every great-person expend with an `action`, and the
label is wrong for three of the twelve units. The map was written from
memory of BNW rather than from LEKMOD's own tables, and the errors all
land on the culture great people, where the analysis is thinnest already.

Ground truth, extracted from `Unit_Builds` joined to `Builds` in
`/Users/dysk/projects/Lekmod/LEKMOD/Override/CIV5Units.xml`:

| Unit | Build | Improvement | In `TARGETED_ACTIONS` |
|---|---|---|---|
| `UNIT_SCIENTIST` | `BUILD_ACADEMY` | `ACADEMY` | correct |
| `UNIT_ENGINEER` | `BUILD_MANUFACTORY` | `MANUFACTORY` | correct |
| `UNIT_MERCHANT` | `BUILD_CUSTOMS_HOUSE` | `CUSTOMS_HOUSE` | correct |
| `UNIT_PROPHET` | `BUILD_HOLY_SITE` | `HOLY_SITE` | correct |
| `UNIT_PROPHET` | `BUILD_SACRED_GROVE` | `SACRED_GROVE` | missing (Lithuania) |
| `UNIT_GREAT_GENERAL` | `BUILD_CITADEL` | `CITADEL` | correct |
| `UNIT_MUSICIAN` | `BUILD_CONCERT` | `CONCERT` | **missing** |
| `UNIT_GREAT_ADMIRAL` | `BUILD_DOCK` | `DOCK` | **missing** |
| `UNIT_DALAILAMA` | `BUILD_HOLY_SITE` | `HOLY_SITE` | correct, via `:prophet` |
| `UNIT_VENETIAN_MERCHANT` | `BUILD_CUSTOMS_HOUSE` | `CUSTOMS_HOUSE` | unit unknown |
| `UNIT_ARTIST` | none | — | **`LANDMARK`, invented** |
| `UNIT_WRITER` | none | — | correct (none) |

`BUILD_LANDMARK` belongs to `UNIT_ARCHAEOLOGIST` alone. The artist plants
nothing; its second use is a golden age, `<GoldenAgeTurns>8</GoldenAgeTurns>`
on the `UNIT_ARTIST` row. Archaeologists are out of scope here.

Consequences in the current code:

- **Golden ages read as great works.** 13 of 31 artist expends in
  `examples/` share a turn with `golden_age_started` for the same
  civilization. A civilization starts a golden age on 3.6% of its turns on
  average, so the coincidence is the artist's doing in nearly all 13.
- **Festivals read as concert tours.** India planted `IMPROVEMENT_CONCERT`
  on turns 122 and 133 and expended a musician on exactly those turns.
  Both count as consumption today.
- **Docks read as nothing.** The one admiral expend in `examples/` planted
  `IMPROVEMENT_CHILE_DOCK` on turn 149 on the tile the `unit_lost` names.
  `action` is null, and the prompt states the admiral has no planted form.
- **Three units are invisible.** `GREAT_PERSON_UNITS` lacks
  `UNIT_ITALARTIST` (Pittore), `UNIT_LEU_COMPARSA_FOLKLORICA` and
  `UNIT_VENETIAN_MERCHANT`, all three already named in
  `WarCasualties::CIVILIAN_UNITS`. For those civilizations there are no
  births, no kind, no action and no `first_of_kind` entry. No example log
  exercises it, so the defect is latent.
- **Two instant uses are guesses.** A writer's great work and its culture
  boost leave the same trace, as do a musician's great work and its
  concert tour. The code names one of each pair outright — `treatise` for
  25 writer expends, `concert_tour` for 14 musician expends.
- **The investment axis measures the wrong thing.**
  `INFRASTRUCTURE_ACTIONS` is defined as `TARGETED_ACTIONS.values`, so it
  separates "leaves a tile" from "leaves no tile". A great work is a
  permanent yield with no tile, and it is counted as consumption.

## The rule

1. A kind may plant more than one improvement, and one planted action may
   have more than one improvement name, because civilizations reskin them
   (`IMPROVEMENT_CHILE_DOCK`). The map is `kind -> {improvement => action}`.
2. A golden age is claimed the way a planted improvement is claimed, by
   `(turn, civ)` coincidence, and one `golden_age_started` is claimed by at
   most one expend. Units that can start one, in claim order: artist,
   Pittore, Comparsa Folklórica, Dalai Lama.
3. Where the log cannot separate two instant uses, the row says so rather
   than picking one. `action: :instant` plus the pair named in the prompt.
4. The expend profile counts what an act pays, not whether it touched a
   tile: `permanent`, `one_off`, `unresolved`.

## Steps

Each step is one TDD cycle — failing tests first, left unstaged for
review, then the smallest implementation that greens them, then one
commit holding both.

### 1. Unit catalogue

- `GREAT_PERSON_UNITS` gains `UNIT_ITALARTIST => :artist`,
  `UNIT_LEU_COMPARSA_FOLKLORICA => :musician`,
  `UNIT_VENETIAN_MERCHANT => :merchant`.
- `great_people_profile.by_kind` keys an unmapped unit by its raw id, so
  the next unique replacement shows up as noise instead of vanishing into
  a nil key.
- Tests: a Pittore birth appears in `great_people_born`; a Merchant of
  Venice expend carries `kind: :merchant`; an invented
  `UNIT_SOMETHING_NEW` expend lands in `by_kind` under its own id.

### 2. Planted actions from the mod's own table

- Replace `TARGETED_ACTIONS` with `kind -> {improvement => action}`:
  scientist `academy`, engineer `manufactory`, merchant `customs_house`,
  prophet `holy_site` and `sacred_grove`, general `citadel`, musician
  `festival`, admiral `dock` (`IMPROVEMENT_DOCK`, `IMPROVEMENT_CHILE_DOCK`).
  The artist entry goes.
- `planted_improvement` matches any improvement of the kind and returns
  which one, so `action` can differ per improvement.
- Tests: India's turn-122 musician is `festival`; Chile's turn-149 admiral
  is `dock`; a Lithuanian prophet planting a sacred grove is
  `sacred_grove`, not `religious_action`; an artist expend on the same
  turn as an unrelated landmark is not `landmark`.

### 3. Artist golden age

- A `golden_age_started` for the same `(turn, civ)` makes the expend
  `action: :golden_age`, claimed one-for-one so two artists in one turn
  with one golden age give one `golden_age` and one `great_work`.
- Document the false-positive rate (3.6% base rate against 42% observed)
  in the method comment, the way `planted_improvement` documents its own
  coincidence rule.
- Tests: artist plus golden age that turn is `golden_age`; artist with no
  golden age is `great_work`; two artists and one golden age split; a
  golden age with no artist expend changes nothing.

### 3a. Golden age length per game speed

A golden age does not follow the general turn factor. The mod's
`GameSpeeds` table carries a `GoldenAgePercent` of its own, and for a quick
game the two disagree — turns run at 67% while a golden age runs at 80%:

| Speed | `ResearchPercent` | `GoldenAgePercent` | An artist's 8 turns becomes |
|---|---|---|---|
| Marathon | 300 | 200 | 16 |
| Epic | 150 | 125 | 10 |
| Standard | 100 | 100 | 8 |
| Quick | 67 | 80 | 6 |
| Online | 67 | 50 | 4 |

- `GameSpeed` gains `GOLDEN_AGE_FACTORS` beside `FACTORS`, and a
  `golden_age_turns(base)` that rounds the way `turns` does.
  `GameSpeed#turns` would answer 5 for a quick game, which is wrong.
- `DigestBuilder` carries `golden_age_base_turns` in the `game` section, so
  the prompt reads one number instead of deriving it.
- Tests: 8 at standard, 6 at quick, 4 at online; Pittore's 9 becomes 7 at
  quick.

Separately, and outside this feature: `GameSpeed::FACTORS` holds `QUICK`
alone, so an epic game is read at standard pace (should be 1.5), a marathon
likewise (3), and an online game too (2/3, the same as quick). Every turn
threshold built on `turns` is wrong on those three speeds. Worth its own
change, now that the authoritative table is located.

### 4. Honest instants

- Writer and musician instants become `action: :instant`. The prompt names
  the pair the log cannot separate — great work or culture boost for the
  writer, great work or concert tour for the musician.
- Tests: a writer expend with nothing else that turn is `:instant`; a
  musician expend with no concert improvement is `:instant`.

### 5. Reclassify the expend profile

- `great_people_profile` splits `permanent`, `one_off` and `unresolved`
  instead of `infrastructure` and `consumption`.
  - permanent: academy, manufactory, customs_house, holy_site,
    sacred_grove, citadel, festival, dock, great_work
  - one_off: bulb, hurry, trade_mission, religious_action, golden_age
  - unresolved: `:instant`, and a nil action (general or admiral whose use
    left no trace)
- Keep the early/late split on the played-length midpoint and its existing
  justification.
- Tests: an artist great work counts as permanent, not consumption; a
  writer `:instant` counts as unresolved and in neither other bucket.

### 6. Whose ground a great person fell on

- `lost_row` keeps the `civ` that `TileOwnership#owner` already returns,
  beside `city` and `located`. A killed great person then says whose
  territory it was, with `located` grading the claim
  (`logged` / `owned` / `adjacent` / `nearest`).
- Tests: a great person killed on owned land carries that civ; one killed
  on neutral ground carries the nearest city's civ with `located: :nearest`.

### 7. Prompt rewrite

Four passages in `app/prompts/analyze_game.md` and one in
`app/prompts/chronicle_game.md`. Drafts below, in each prompt's own voice.

#### 7.1 `analyze_game.md` lines 329-350, the field reference

> **`great_people` and `great_people_born`.** `great_people_born` records
> each birth (`great_person`, `turn`, `city`). `great_people` records what
> became of each one:
>
> - `fate` is `expended`, `killed` (with `killed_by`) or `disbanded`.
> - For an expended one, `action` is the choice. A scientist, engineer,
>   merchant, prophet, musician, general or admiral can plant a permanent
>   improvement — `academy`, `manufactory`, `customs_house`, `holy_site`,
>   `sacred_grove` (Lithuania's prophet only), `festival`, `citadel`,
>   `dock`. Each instead has an instant use: `bulb`, `hurry`,
>   `trade_mission`, `religious_action`.
> - An artist either makes a great work (`great_work`) or begins a golden
>   age (`golden_age`). It plants nothing — a landmark is an
>   archaeologist's work, not a great person's.
> - `instant` means the log cannot tell two uses apart, and it is a gap in
>   the record, never a verdict. A writer's `instant` is either a great
>   work or a one-off culture award drawn from the last eight turns of its
>   own output. A musician's is either a great work or a concert tour. Name
>   both readings or neither, and never pick the one that suits the
>   argument.
> - A general or admiral that planted nothing leaves `action` null. That is
>   also a gap in the record, not a wasted great person.
> - A great work pays culture every turn it stands, and a musician's or
>   artist's also pays tourism. A planted improvement pays every turn left
>   in the game, so a late one has few turns to earn back. A golden age, a
>   bulb, a hurry, a trade mission and a concert tour pay once.
>
> `great_people_profile` counts expends `by_kind` and splits `permanent`
> (a planted improvement or a great work), `one_off` (a use that pays at
> once) and `unresolved` (an `instant` or a null action) into `early`/`late`
> halves of the game as logged. A civilization still building permanent
> yield late has turns to recoup it. One that shifted to one-off uses late
> was banking returns before the end. A large `unresolved` count is a limit
> of the record, and no verdict follows from it either way.

#### 7.2 `analyze_game.md` line 354, golden ages

The standing rule there — never state or estimate how long a golden age
lasted — has to survive, because the log carries starts and never an end.
It gains the part the ruleset does fix:

> **`golden_ages`.** The turn each golden age began, and nothing else. The
> log never records a turn one ended. A golden age whose turn matches an
> artist expend in `great_people` was that artist's doing, and
> `game.golden_age_base_turns` is how long an artist's age runs at this
> game's speed before anything stretches it — a golden age keeps its own
> pace, slower than the pace of turns, so never derive it from the speed
> yourself. `lekmod.ideologies` and `lekmod.civilizations` hold what
> stretches it: Universal Suffrage and Persia's Achaemenid Legacy each by
> half, Chichen Itza likewise, Italy's Pittore starting a turn longer than
> an ordinary artist and reaching half again with Chichen Itza or Universal
> Suffrage but no further with both, Italy's Rinascimento adding to an age
> already running. Name the base where nothing stretches it. Where
> something does, say a civilization bought a longer age than its rivals
> did and what paid for it, and never add the modifiers up into a total —
> they interact, they cap, and the record cannot confirm the result. Where
> a second golden age began while the first was plausibly still running,
> say the two ran together and that the overlap is unsettled.

#### 7.3 `analyze_game.md` lines 659-664, killed great people

> **`great_people_first_of_kind`.** The first civilization (or tied
> civilizations, `civs`) to raise each kind of great person. Minor colour,
> worth a clause where it fits. A great person killed in battle is recorded
> in `timelines.<civ>.great_people` (`fate: killed`, `killed_by`, `civ` and
> `located` for the ground it fell on). A lost general is a battle loss and
> a spent investment at once, worth its own line. A lost musician is the
> same thing on the cultural front, because a concert tour spends stored
> tourism for a single large push on one rival's influence, and killing the
> musician cancels that push: read it against the owner's standing over the
> killer in `cultural` and the `tourism` curve either side of the turn. The
> ground it fell on is colour, not a condition — these killings happen on
> neutral land and inside the owner's own borders as readily as on the
> victim's, and `located` says only how confidently the record places it.
> Other kinds lost this way belong inside the war that took them.

#### 7.4 `analyze_game.md` lines 975-978, the verdict rule

> ## Great people
>
> Judge a civilization by what its great people did, never by how many were
> born. One spent well beats three left to die. Weigh the choice against
> the clock: permanent yield wants turns to pay for itself, a one-off use
> wants a game near its end or a crisis in front of it. An `instant` or a
> null `action` is the record's limit, so say the great person was spent
> and leave the use unnamed rather than guessing which it was.

#### 7.5 `chronicle_game.md` lines 426-447, the chronicle

Keeps its two standing rules — write from `kind`, never quote a count —
and gains the artist and the musician:

> A `great_person_lost` moment is a genius killed in battle rather than
> spent on the work they were raised for. A general lost this way is a
> battle loss and a ruined investment at once, and earns an entry the way a
> border town falling does. A musician lost this way earns one too, for a
> different reason: a musician was carried toward a rival's cities to win
> that realm's people over in a single season of song, and the army that
> cut them down denied a victory of renown, not a victory of arms. Every
> other kind lost is a lighter loss, worth a clause in the passage about
> the war that took them.
>
> A golden age that fell in the same year a people spent an artist was that
> artist's gift, and the chronicle may say so — a realm's own painter
> ushering in an age of plenty is a different sentence from an age that
> arrived on its own. Where a people's own abilities or chosen tenets
> stretched such an age, say it ran longer than its neighbours' did; never
> say how many years any of it lasted.
>
> Where the record cannot say what a genius was spent on, the chronicle
> says they were spent and stops. Inventing the deed is the one thing
> worse than omitting it.

### 8. Chronicle weight

- `ChronicleSpine::GREAT_PERSON_LOST_WEIGHTS` gains `musician: 3`. A
  general stays the anchor, everything else stays 1.
- Test: a killed musician outweighs a killed scientist in the spine.

## Later, not now

- **Concert tour detection.** The tour leaves no event, but it moves
  influence on one rival by a step the next `cultural` checkpoint can see.
  A musician `:instant` followed by a single-rival influence jump is
  readable. Needs a calibration pass across more logs first.
- **Generated map.** `script/extract_lekmod_unit_names` and
  `script/extract_lekmod_buildings` already read the mod's XML. A third
  extractor for `Unit_Builds` would keep this map from drifting again, and
  would have caught all three errors above. Worth doing once the map
  stabilizes.
- **Archaeologists.** `BUILD_LANDMARK` and `BUILD_ARCHAEOLOGY_DIG` are a
  separate feature with their own yields and their own theming question.
