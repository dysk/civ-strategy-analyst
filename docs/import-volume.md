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

### 1. Cross-session dedup held every payload in memory — done

`duplicate_of_earlier_session?` asked a `Set` of **whole parsed payload
hashes** whether it had seen a record before, and
`@signatures_from_earlier_sessions` accumulated every payload from every
session that came before. Each line deep-hashed a Hash against a set whose
entries were themselves Hashes: at 40k records that is hundreds of
megabytes of retained Ruby objects.

Dedup now compares a SHA-256 digest per record, which is a short string
instead of a live object graph.

Writing the change turned up a second, worse problem. Every record now
carries `t_log`, the engine's own clock, and that clock restarts with the
process. A replayed record therefore has a different `t_log` and the same
facts, so payload equality had **stopped matching anything at all** — the
cross-session dedup was silently doing nothing for any log produced by the
current parser. The digest is taken over the payload without `t_log`,
which is the question the code meant to ask all along.

Digesting the raw line, as this document first proposed, would have
preserved that bug.

### 2. One INSERT per line — done

`persist_event` called `game.game_events.create!` per record. Rows are now
buffered and written with `insert_all` in batches of 1000, with
`created_at`/`updated_at` set explicitly because `insert_all` skips
timestamps. `seq` was already assigned in Ruby, so ordering never depended
on the database.

The cost was not only the round trips. `GameEvent` validates `seq` unique
per game, so every `create!` issued a SELECT against a table with no index
on `(game_id, seq)` — a scan whose cost grew with the rows already
imported, which is why the old path degrades superlinearly rather than
merely slowly.

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

`logger_error` is listed as known but is not stored; see below.

## Measured

A synthetic log at the shape a real game will produce: 8 civs, 300 turns,
12 cities each, one `snapshot` and twelve `city_snapshot` records per civ
per turn, plus a reload replaying the last ten turns — 37,202 lines,
7.6 MB. Same machine, same database, same file, `RAILS_ENV=test`.

| lines  | before   | after  |
| ------ | -------- | ------ |
| 4,000  | 4.64 s, +52 MB  | 0.19 s, +5 MB  |
| 12,000 | 23.47 s, +149 MB | 0.61 s, +12 MB |
| 37,202 | killed after 9 min | 2.12 s |

Three times the lines cost the old path five times the time; the new one
stays linear. The full file was never imported by the old code at all,
which is the practical form of the problem: a full multiplayer game would
not have imported.

The 37,202-line run deduplicated 1,200 replayed records. The old code
would have deduplicated none of them, `t_log` being part of what it
compared.

`test/services/import_game_test.rb` keeps the cross-session cases green
and adds one for the clock, one for a log that contains a logger failure,
and one import larger than a single batch.

## Still open

`logger_error` is no longer imported: it is the logger reporting that one
of its extractors threw, it carries no `turn`, and the column is `NOT
NULL`, so `create!` used to raise `RecordInvalid` and abort the whole
import on the first such line. The count is reported in `Result` and
printed by `civ import`. What remains open is whether those failures
deserve a home of their own rather than a number.

## Not in scope

Nothing about the analysis layer. Whether `city_snapshot` should feed a
projection — city production is the first thing in the log that shows a
wonder race and the moment somebody lost it — is a separate question,
and worth answering only once a real game has produced the records.
