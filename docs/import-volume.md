# Import at the volume the logger is about to produce

Execution plan for one feature. `docs/plan.md` keeps the project-wide
iteration history; this file is the detailed plan for this change alone.

## Context

`civ-narrative-logger` is adding two things before the first human
multiplayer game: stock fields on the per-player `snapshot` record, and a
per-city, per-turn `city_snapshot` record. Neither changes the format —
one JSON object per line, `event` and `turn` on every record — but both
change the scale, and `ImportGame` was written against logs an order of
magnitude smaller.

The measuring stick is `examples/babylon-domination.jsonl`: 6349 lines,
1.2 MB, 203 turns, 4 civilizations, of which 813 lines are `snapshot`
records of ~690 bytes each.

What the two additions do to that:

- the stock fields add no rows. The `snapshot` record grows to roughly
  1.3 kB, most of it the per-resource list (strategic and luxury only,
  non-zero entries only). At 8 players × 300 turns that is ~2400
  snapshots, so +1.5 MB.
- `city_snapshot` is one record per city per turn: 8 players × ~12
  cities × 300 turns ≈ 29k rows, ~15 MB.

A full game therefore lands near 40k rows and ~20 MB, against ~6k rows
and ~1 MB today. Postgres does not care — `game_events.payload` is
`jsonb` and the `(game_id, turn)`, `(game_id, event_type)` and
`(game_id, civ)` indexes already exist — and `DigestBuilder` selects by
`event_type` throughout, so nothing downstream silently ingests the new
volume. The import path itself is the part that does not scale.

## What breaks, in order of how much it hurts

### 1. Cross-session dedup holds every payload in memory

`duplicate_of_earlier_session?` (`app/services/import_game.rb:84-90`)
asks a `Set` of **whole parsed payload hashes** whether it has seen this
record before, and `@signatures_from_earlier_sessions` accumulates every
payload from every session that came before (`:74`). Each line therefore
deep-hashes a Hash against a set whose entries are themselves Hashes.

At 6k small records this is invisible. At 40k records where the largest
are city snapshots, it is hundreds of megabytes of retained Ruby objects
and a hash of the full payload per line.

The fix keeps the semantics exactly: dedup on a digest of the raw line
(`Digest::SHA256.hexdigest(line)`) rather than the parsed object. Two
identical lines have identical digests, which is the same question being
asked now, at a fraction of the memory and with string hashing instead
of deep hashing. The logger emits object keys in sorted order precisely
so its output is byte-stable, so equal records really do produce equal
lines.

### 2. One INSERT per line

`persist_event` calls `game.game_events.create!` per record
(`app/services/import_game.rb:92-101`) — 40k individual INSERTs, each
with validations and callbacks. Batch into `insert_all` in chunks of
~1000. `seq` is assigned in Ruby already, so ordering does not depend on
the database, and `created_at`/`updated_at` have to be set explicitly
because `insert_all` skips timestamps.

### 3. `KNOWN_EVENT_TYPES` was stale for a while — done

Unknown types were only warned about and still imported
(`app/services/import_game.rb`), so nothing broke — but the warning is per
line, and `city_snapshot` alone would have written ~29k of them into the
import log.

The list was missing 23 names, only three of which came from the recent
work (`city_snapshot`, `player_eliminated`, `building_sold`); the rest —
`city_destroyed`, `diplo_event`, `globe_circumnavigated`, `mp_vote`,
`mp_proposal_result`, `paradrop`, `project_completed`, `unit_rebased`, the
five diplomacy pairs, `game_ended`, `logger_error` — had accumulated over
several rounds, because nothing checked.

All 70 names the logger emits are now listed, and
`test/fixtures/files/logger_event_types.jsonl` carries one line per name so
the check has something to fail against. That is still two hand-maintained
lists, but a forgotten name now fails a test in a second instead of
surfacing as noise during a real import. Generating both from the logger
would need a shared artefact between the repositories, which is worth
doing only if the fixture turns out to drift anyway.

`logger_error` is listed but still open as a question: it is the logger
reporting that an extractor threw, and importing it as an ordinary game
event puts a failure record in the same table as facts about the game.
Skipping it during import and surfacing the count in `Result` would be
more honest.

## Verification

`test/services/import_game_test.rb` covers the current behaviour; the
dedup change has to keep its cross-session cases green, since that is
the whole point of preserving the semantics.

What the existing tests cannot show is the scaling, so the change wants
one measured import of a real log: rows imported, wall-clock time and
peak RSS before and after. Without that number this document is an
argument, not evidence.

## Not in scope

Nothing about the analysis layer. Whether `city_snapshot` should feed a
projection — city production is the first thing in the log that shows a
wonder race and the moment somebody lost it — is a separate question,
and worth answering only once a real game has produced the records.
