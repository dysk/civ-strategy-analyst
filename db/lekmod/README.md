# LEKMOD reference data

Per-version snapshots of the LEKMOD ruleset, normalized from the mod's
official Google Docs into Markdown that `DigestBuilder` can inject into
analysis digests. Each version directory is a complete snapshot:

```
db/lekmod/<version>/
  civilizations.md   one "## Civ (Leader)" entry per civilization
  general.md         wonders, units, buildings, great people, tiles,
                     city-states, diplomacy, World Congress, technologies
  religion.md        pantheons and beliefs
  ideologies.md      Freedom / Order / Autocracy tenets
  policies.md        the nine policy trees
  ids.yml            POLICY_*/BELIEF_*/RESOLUTION_* -> display name,
                     extracted from the mod's own XML source (optional;
                     see below)
  units.yml          UNIT_* -> display name, extracted the same way
                     (optional; see below)
  buildings.yml      BUILDING_* -> { name, wonder }, extracted the same
                     way (optional; see below)
```

There is no `resolutions.md`: LEKMOD leaves the base game's World
Congress resolutions themselves untouched (`CIV5Resolutions.xml` in the
mod's `Override` is an empty stub - the real `<Resolutions>` table lives,
unmodified from vanilla BNW bar a few tweaked fields, in the
misleadingly-named `CIV5Units.xml`, per the pitfall note below). Only a
handful of resolutions get an actual rule change, called out in
`general.md`'s "World Congress / United Nations" section; `ids.yml`'s
`RESOLUTION_*` entries supply just the display name for every other one,
not an effect description - there is no per-resolution prose to extract.

Format: one `## ` heading per entity, `- **Name:** effect` bullets,
effect text verbatim from the docs. Policies, tenets and beliefs carry
their internal vanilla-Civ5 ID in backticks where known, because game
logs use those IDs and LEKMOD keeps them even where it renames the
displayed item (`POLICY_MERCHANT_NAVY` → "Colonialism",
`POLICY_FREE_RELIGION` → "Religious Tolerance", `BELIEF_WALLS` →
"Goddess of Protection").

Some LEKMOD-original items give their own ID a misspelled or unrelated
suffix (`BELIEF_ZAKATT` → "Zakat", `BELIEF_CRAFTWORKS` → "Jizya"), so
the name can't always be derived from the ID or annotated confidently
by hand. `ids.yml` covers those: `LekmodReference` looks up an ID
there whenever no inline backtick annotation and no ID-derivation
matches, before giving up on it. Manual inline annotation still wins
when both exist - `ids.yml` is a fallback, not an override.

## Unit names

`units.yml` is the same idea for units, and it exists because the ID is
not the name: `UNIT_WWI_TANK` is a Landship, `UNIT_GATLINGGUN` a Gatling
Gun, `UNIT_PROPHET` a Great Prophet, `UNIT_BARBARIAN_WARRIOR` a Brute.
Roughly two in five of the unit types a game logs read wrong when the ID
is taken for the name, and the failures are not guessable - LEKMOD
renamed the Great War Tank to Landship while keeping the vanilla ID.

The mod's `Override/CIV5Units.xml` carries the whole `Units` table rather
than only the mod's additions - the same surprise as the Resolutions note
above - so no base-game install is needed. Every unit resolves: vanilla
units through a `TXT_KEY` in the `Language_en_US` tables, LEKMOD's own
units through an English `Description` written straight into the row.
Generate one with:

```sh
script/extract_lekmod_unit_names /path/to/Lekmod/LEKMOD/Override db/lekmod/35.3/units.yml
```

`UnitNames` resolves a game's version against these files more loosely
than `LekmodReference` resolves the rules: exact version if it has a
`units.yml`, otherwise the newest one that does. A unit keeps its name
across versions far longer than a policy keeps its effect, so a snapshot
predating the extraction is better served by a later snapshot's names
than by none. An ID no snapshot names is read as plain English, which is
what most of them are.

Only English is available. LEKMOD ships `Language_PL_PL`, `Language_DE_DE`
and `Language_RU_RU` tables, but they are empty stubs - all 30,000-odd
text entries are `Language_en_US`.

## Building names and wonder scope

`buildings.yml` maps every `BUILDING_*` to `{ name, wonder }`. `Wonders`
reads it to answer whether a bare `producing` id in a `city_snapshot` is a
world wonder - a race for one that nobody finished never reaches a
`building_constructed` record, so in-game observation alone under-reports.
`wonder` is `world` / `team` / `national` for a building whose *class* the
ruleset caps (`MaxGlobalInstances` / `MaxTeamInstances` /
`MaxPlayerInstances` > 0, checked widest-scope first), absent otherwise -
the same rule the logger applies in `adapter.lua`.

The `<Buildings>` and `<BuildingClasses>` tables sit in
`Override/CIV5Units.xml`, not a file named for them - the same misfiled-table
trap as Resolutions above. Generate one with:

```sh
script/extract_lekmod_buildings /path/to/Lekmod/LEKMOD/Override db/lekmod/35.3/buildings.yml
```

`Wonders` resolves a game's version against these files the loose way
`UnitNames` does: exact `buildings.yml`, else the newest snapshot that has
one; with none anywhere it falls back to the wonders the game was seen to
complete. Names are cleaned of the game's `[COLOR_...]` markup and the
trailing `*` national-wonder marker. A handful of civ-unique regular
buildings resolve to placeholder or non-English text in the mod source
itself (`BUILDING_ARGENTINA_STABLE` -> "Ocupada estable"); none are
wonders, so wonder detection is unaffected.

## Version resolution

`LekmodReference` resolves a game's version against the snapshots present
here: exact match first, otherwise the nearest snapshot from the same
major line — newer included, ties going to the older — and only when that
line has no snapshot at all does it drop to the nearest older line. A game
played on 35.2 therefore reads 35.3's rules rather than 34.15's: within a
line the versions are hotfixes and small tweaks, between lines whole
civilizations and mechanics appear. Every inexact match carries a
`resolution_note` into the digest saying which of the two gaps it is.

That is why a hotfix rarely needs its own snapshot — one per major line,
kept current, serves every game played on it.

## Adding a new version

Only add a snapshot when a game imported on that version needs analyzing.
Two paths, and the first is the usual one:

**From changelogs** — the masterlist Google Docs lag behind the mod, so
for anything they have not caught up with the release changelogs are the
only source. Copy the nearest snapshot and apply every changelog between
it and the target, in release order:

```sh
cp -r db/lekmod/34.15 db/lekmod/35.3
# apply 35.0, then 35.2, then 35.3
```

Enumerate the releases from the mod's own installer manifest rather than
from memory - `LekmodInstaller/github_setup/versions.json` at the target
commit lists every published version, so a skipped release shows up
before it silently ages the snapshot. Applying them in order also
resolves the conflicts for you: an entity touched twice ends up on its
last value, and a bug reported in one release and fixed in the next
leaves no trace, which is correct.

While applying:

- record the **final state, not the delta** - `( 110 > 100 Faith )`
  becomes "100 Faith". The snapshot describes one version's rules, not
  the path taken to them;
- drop "Developer note" commentary (rationale, not rules) but keep notes
  about mechanics being broken, which do affect what happened in a game;
- put a provenance note under each file's title saying which snapshot and
  which changelogs it was built from - otherwise the next reader takes it
  for a masterlist dump and trusts untouched entries too far;
- a changelog entry that states no rule ("Improved Trade Route
  Calculations") and one that is purely cosmetic (a new unit model) are
  worth nothing to an analysis - leave them out deliberately rather than
  padding the file.

Verify **both directions** against `git diff --no-index db/lekmod/<old>
db/lekmod/<new>`: every changelog item must appear in the diff (catches
omissions) and every hunk must trace back to a changelog item (catches
invention). This replaces the entity-count check below, which needs a
full source dump to count against.

**From fresh dumps** — when the masterlist has been brought up to date,
re-normalize from it. Copy each Google Doc
(civilizations masterlist, general changes, religion, ideologies,
policies) into a plain-text file, then either:

- *Local model* (LM Studio + `ask-local`): load an instruction-precise
  model (qwen3-coder-30b works well) with a ≥32K context window, then run
  `script/normalize_lekmod` per dump. It chunks the dump at entity
  boundaries (~10 KB — long generations degrade before long inputs do),
  delegates restructuring to `ask-local`, verifies that every named item
  from the source appears in the output, strips `(vs. X)`/`(from X)`
  comparison parentheticals, and assembles the target file:

  ```sh
  script/normalize_lekmod lekmod-civilization.txt db/lekmod/34.16/civilizations.md \
    --prompt entity --title "LEKMOD civilizations (34.16)" --boundary '^Ability:'
  script/normalize_lekmod lekmod-changes.txt db/lekmod/34.16/general.md \
    --prompt section --title "LEKMOD general changes (34.16)"
  ```

  `--boundary` restricts chunk breaks to paragraphs matching the regex —
  for the civilizations file that keeps a civ's header and items in one
  chunk. Interrupted runs resume: finished chunks in `tmp/normalize_lekmod/`
  are skipped.

- *Cloud LLM*: hand the dumps to an agentic model with
  `prompts/cloud-normalize-prompt.md`, which encodes the same procedure
  end to end. For a plain chat model, chunk manually and use
  `prompts/entity-chunk-prompt.txt` / `prompts/section-chunk-prompt.txt`
  per chunk.

**Either path, then generate `ids.yml`** from the mod's own XML source
(ground truth for the display name behind an ID - see the trap note
above; `script/extract_lekmod_ids` explains the extraction mechanics):

```sh
# find the commit for this version - there's no consistent tag/branch
# naming (tagging stopped at v30.7), so search commit messages
git -C /path/to/Lekmod fetch
git -C /path/to/Lekmod log --oneline --all | grep -i '35\.3'

# export that commit's Override tree instead of checking it out, so the
# mod checkout is left on whatever branch its owner had it on
git -C /path/to/Lekmod archive <that-commit> LEKMOD/Override | tar -x -C /tmp/lekmod-35.3
script/extract_lekmod_ids /tmp/lekmod-35.3/LEKMOD/Override db/lekmod/35.3/ids.yml
script/extract_lekmod_unit_names /tmp/lekmod-35.3/LEKMOD/Override db/lekmod/35.3/units.yml
script/extract_lekmod_buildings /tmp/lekmod-35.3/LEKMOD/Override db/lekmod/35.3/buildings.yml
```

Only scan `LEKMOD/Override`, not the whole checkout - a sibling
`LEKMOD/Art/No Quitters Mod (v 11)/` tree carries German/Polish
duplicate `Tag=` entries for the same keys that would silently corrupt
the extracted English names if scanned.

## Verification checklist

The script's name check is necessary but not sufficient. Before
committing:

- Entity counts match the source — for civilizations every entry has
  exactly one `Ability:` line, so `grep -c '^Ability' <dump>` must equal
  `grep -c '^## ' civilizations.md`.
- Spot-check two or three entries verbatim, preferring ones with
  irregular source headers (leading spaces, aliases like "Papal States
  (Vatican)", apostrophes, a missing space before the dash) — those are
  where mechanical checks go blind.
- No leftover comparison parentheticals: `grep '(vs\.\|(from ' *.md`.
- Annotate internal IDs: list IDs from a recent game log
  (`grep -o '"policy":"[A-Z_]*"' <events.jsonl> | sort -u`, same for
  `"belief"`), match any without a direct name counterpart against the
  changelog, and add them inline as `- **Name** (`ID`):`. `ids.yml`
  now covers most of these automatically, so this is mainly worth doing
  for high-traffic IDs where having the mapping visible in the
  Markdown itself (not just `ids.yml`) helps a human skimming the file.
- After generating `ids.yml`, spot-check a couple of entries against
  `LekmodReference`'s `unmatched_ids` for a recent game on this
  version - anything still unmatched either needs a manual inline
  annotation or genuinely has no resolvable text in the mod source.
