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
  ids.yml            POLICY_*/BELIEF_* -> display name, extracted from
                     the mod's own XML source (optional; see below)
```

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

## Adding a new version

Only add a snapshot when a game imported on that version needs analyzing.
Two paths, by size of the change:

**Small changelog** — copy the nearest existing snapshot and hand-apply
the mod's changelog:

```sh
cp -r db/lekmod/34.15 db/lekmod/34.16
# edit the affected entries, update version numbers in the titles
```

**Large drift** — re-normalize from fresh dumps. Copy each Google Doc
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
# in the mod checkout: find and check out the commit for this version -
# there's no consistent tag/branch naming, so search commit messages
cd /path/to/Lekmod && git log --oneline --all | grep -i '34\.16'
git checkout <that-commit>

cd -  # back to civ-strategy-analyst
script/extract_lekmod_ids /path/to/Lekmod/LEKMOD/Override db/lekmod/34.16/ids.yml
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
