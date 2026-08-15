# Prompt: normalize LEKMOD documentation dumps into reference Markdown

Use this prompt when normalizing with a capable cloud LLM (an agentic one
like Claude Code, or a chat model fed one chunk at a time). It describes
the full procedure end to end; `entity-chunk-prompt.txt` and
`section-chunk-prompt.txt` in this directory are the per-chunk variants
of the same format rules.

---

You are given raw text dumps of the LEKMOD (a Civilization 5 mod)
documentation, copied from its official Google Docs: a civilizations
masterlist, a general-changes document (wonders, units, buildings, great
people, tile yields, city-states, diplomacy, World Congress,
technologies), a religion masterlist, ideology tenets, and policy trees.
Produce one normalized Markdown reference file per dump, for the
directory `db/lekmod/<mod-version>/`:

`civilizations.md`, `general.md`, `religion.md`, `ideologies.md`,
`policies.md`.

## Target format

- Each file starts with `# LEKMOD <topic> (<mod-version>)` and a short
  note describing its contents.
- One `## ` heading per entity (a civilization, a section of general
  changes, a policy tree, an ideology); `### ` for subsections (eras,
  tenet levels, individual technologies).
- Each named item becomes `- **Name:** effect text` — for civilizations
  keep the item kind in the label: `- **Unit — Name:** ...`.
- Effect text is copied verbatim; join lines wrapped mid-sentence.

## Cleanup rules

- Drop Google-Docs artifacts: navigation hints, page-break notes, color
  legends ("changes in BLUE/RED/GREEN"), "LekMod Home Document" links.
  Color semantics are already lost in a plain-text dump; the current
  effect text is what matters, not the delta against the base game.
- Strip pure comparison parentheticals: `(vs. 4)`, `(from 70, vs. 70)`,
  `(233 hammers vs. 280)`. Keep parentheticals that carry rules content,
  such as `(instead of Steel)`, `(+30%)`, `(max. 30)`, and keep
  `(unchanged)` markers — they mean "identical to Brave New World".
- Do not paraphrase, shorten, reorder, or add anything.

## Internal ID annotation

Game logs identify policies, tenets and beliefs by internal vanilla-Civ5
IDs, and LEKMOD keeps those IDs even where it renames the displayed
item. Annotate entries with their ID in backticks where the mapping is
known: `- **Colonialism** (`POLICY_MERCHANT_NAVY`): ...`. Known renames
as of 34.15: `POLICY_MERCHANT_NAVY` → Colonialism, `POLICY_FREE_RELIGION`
→ Religious Tolerance, `BELIEF_WALLS` → Goddess of Protection. IDs are
normally the upper-cased display name (`POLICY_LANDED_ELITE`,
`BELIEF_GOD_KING`); to discover new renames, list the IDs appearing in a
game log (`grep -o '"policy":"[A-Z_]*"' <events.jsonl> | sort -u`, same
for `"belief"`) and match any that have no direct name counterpart
against the effects described in the mod's changelog.

## Verify before finishing

- Entity counts match the source (for civilizations, every entry has
  exactly one `Ability:` line — count those; expect ~112 in 34.15).
- Every named item from the source (`Name: effect` lines) appears in the
  output. Watch for entries with irregular headers — leading spaces,
  parenthesized aliases like "Papal States (Vatican)", apostrophes like
  "'Aho'eitu", missing space before the dash like "Bolivia- Tata Belzu".
- Spot-check two or three entries verbatim against the source.
- No leftover `(vs. X)` / `(from X)` comparisons.
