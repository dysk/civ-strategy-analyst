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

### 3. `KNOWN_EVENT_TYPES` has been stale for a while

Unknown types are only warned about and still imported
(`app/services/import_game.rb:59-61`), so nothing breaks — but the
warning is per line, and `city_snapshot` alone would write ~29k of them
into the import log.

The list is missing more than the new work. Comparing it against every
`event` the logger emits today:

```
building_sold        city_destroyed       defensive_pact_ended
defensive_pact_signed diplo_event         embassy_ended
embassy_established  friendship_declared  friendship_ended
game_ended           globe_circumnavigated logger_error
mp_proposal_result   mp_vote              open_borders_granted
open_borders_revoked paradrop             project_completed
trade_agreement_ended trade_agreement_signed unit_rebased
```

Eight of those (`city_destroyed`, `diplo_event`,
`globe_circumnavigated`, `mp_vote`, `mp_proposal_result`, `paradrop`,
`project_completed`, `unit_rebased`) predate this round entirely, which
says the list is not maintained by anything and drifts silently. Either
add the names and accept it will drift again, or generate the check from
the logger's own event list and stop hand-maintaining it.

`logger_error` deserves a decision rather than a listing: it is the
logger reporting that an extractor threw, and importing it as an
ordinary game event puts a failure record in the same table as facts
about the game. Skipping it during import and surfacing the count in the
import result would be more honest.

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
