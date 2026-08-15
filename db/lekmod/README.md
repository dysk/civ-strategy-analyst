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
```

Format: one `## ` heading per entity, `- **Name:** effect` bullets,
effect text verbatim from the docs. Policies, tenets and beliefs carry
their internal vanilla-Civ5 ID in backticks where known, because game
logs use those IDs and LEKMOD keeps them even where it renames the
displayed item (`POLICY_MERCHANT_NAVY` → "Colonialism",
`POLICY_FREE_RELIGION` → "Religious Tolerance", `BELIEF_WALLS` →
"Goddess of Protection").

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
  changelog, and add them inline as `- **Name** (`ID`):`.
