# Projections at the volume of a full 8-player game

What `/games/:id/projections` and `DigestBuilder` cost as a game grows, and
where that cost comes from. `docs/import-volume.md` covers the write side
of the same question; this file covers the read side. Measured 2026-10-20,
while the first human 8-player standard-speed game stood at turn 56.

All timings are development-machine figures. Production ran the same page
roughly 3.5x slower, measured against a browser wait of just over 4s for
`india-diplo` where this machine took 1077ms.

## How many events a full game produces

Every reference log is `GAMESPEED_QUICK` with `max_turns: 330`. The live
game is the first on standard speed, `max_turns: 500`, and that changes the
mix rather than scaling it, because the events fall into two classes:

| class | share in `india-diplo` | how it grows |
| --- | --- | --- |
| per-turn snapshots (`city_snapshot` is one row per city per turn, `snapshot` one per civ per turn, plus `city_state_snapshot`) | 36% (6646 of 18263) | turns × entities, so standard speed inflates it ~1.5x for the same empire |
| development (buildings, techs, units, plots) | 64% (11617) | the same total for the same empire, spread over more turns |

The per-turn class is why the total is quadratic in turns rather than
linear. `india-diplo` generated 37 events/turn at turn 10 and 166/turn at
turn 150, because the rate tracks city count and city count grows.

Fitting `india-diplo`'s development curve as `12.95·T + 0.272·T²` in quick
turns, scaling it from 6 civs to 8, adding the per-turn class for 350 real
turns, and anchoring the result on the live game's 2919 events at turn 56
(the raw model gave 2468, hence a 1.18 correction) gives:

| turn | events |
| --- | --- |
| 200 | ~19 000 |
| 250 | ~28 000 |
| 300 | ~39 000 |
| 350 | ~50 000 |
| 400 | ~63 000 |

`docs/import-volume.md` put a full game near 40k rows from the write side,
which agrees at turn 300.

Nine event types the logger emits do not appear in `india-diplo` at all:
`mp_vote`, `mp_proposal_result`, `diplo_event`, `nuclear_detonation`,
`player_eliminated`, `spy_evicted`, `spy_surveillance_established`,
`building_sold`, `globe_circumnavigated`. `mp_vote` fires per player per
resolution, so a diplomacy game can add ~1000 rows on that type alone.
Call the turn-350 figure 45–60k.

## Where the page time goes

| | 18k events / 6 civs | 47k events / 8 civs |
| --- | --- | --- |
| projections page | 511ms | 1749ms |
| — `EventLog` load | 195ms | 520ms |
| — `opening_strategy_rows` | 100ms | 430ms |
| — `key_moment_groups` | 106ms | 376ms |
| — `religion_hold_rows` | 43ms | 107ms |
| `DigestBuilder#call` | 580ms | 1843ms |
| digest size | 244 KB | 540 KB |

SQL is not the problem anywhere. The page issues 15 queries for 58ms, and
view rendering is single-digit milliseconds. Everything else is Ruby over
the in-memory log.

Cost per event rises with size — 23 µs at 4540 events, 29 µs at 18k, 37 µs
at 47k. The rise is not a hidden quadratic; it is the per-civ loops in
`opening_strategy_rows` and `key_moment_groups` paying for 8 civs instead
of 6.

Projected to production, a full 8-player game opens its projections page in
5–7 seconds, which is why both pages are cached rather than made faster.

## The cache

The two pages that walk the whole log — `/games/:id/projections` and
`/games/:id` — render through `Rails.cache.fetch` in the controller. The
body is cached and the layout renders every time, so the CSRF token stays
fresh; neither view sets `content_for`, so nothing else needs the layout
and the template to render together.

The key is the log's own version. Events never change once imported, so
the last event's seq and the game record say which page the cache holds:

    [ :projections, @game, @game.game_events.maximum(:seq) ]

The game page also shows the latest analysis and how many there are, and
analyses come and go, so its key carries
`@game.analyses.cache_key_with_version` as well.

| page | cold | warm |
| --- | --- | --- |
| `/games/:id/projections` | 1664ms | 13–22ms |
| `/games/:id` | 777ms | 21ms |

Measured on the 47k-event synthetic game. The first visit after a deploy
still pays the cold price, 5–7s in production, and each cached page is
~300 KB on disk under `tmp/cache`.

`DigestBuilder` is untouched by this. `bin/civ analyze` runs in its own
process and builds every projection from scratch, so an analysis still
pays the 1843ms in the table above.

`bin/deploy` runs `bin/rails tmp:cache:clear`, because it pulls into the
same checkout. Without that, a change to a projection or to the view
would keep serving the HTML the old code built.

## Two defects the measurement turned up

### `Religion#holds` was quadratic — fixed

`lapsed_between?` and `next_snapshot` each scanned every `city_snapshot` in
the game to answer a question about one city. At 5110 snapshots and 630
conversions that is 3.2M payload comparisons, 581ms of the page's 1077ms,
and it grew as the product of the two counts rather than their sum — 3x the
events would have cost 9x the time.

Snapshots are now indexed per city once, ordered by `[turn, seq]` to keep
the tie-breaking the old `min_by(&:turn)` had. `holds` went from 556ms to
43ms and the digest from 1079ms to 589ms. Verified by hashing
`Religion.for(game).holds` on `india-diplo` before and after; the output is
byte-identical.

### A plot could be held twice — fixed

`transfer` appended to `@owned[civ]` without checking whether the civ
already held that plot. A razed city leaves no event behind, so a civ that
razes a city and later founds its own on the same hex gains that plot
twice. `mean_spacing` then computes `(plots - [plot]).map { ... }.min`,
`Array#-` removes both copies, `min` returns `nil`, and the whole
projections page answers 500 with `TypeError: nil can't be coerced into
Integer`. The inflated `cities` count and the zero-distance pairs skewing
`span` and `elongation` came from the same place.

## Rebuilding the load test

The 47k-event figures come from a synthetic game: `india-diplo` with two
civs cloned under new names and the whole stream replayed at `turn + 166`,
giving 8 civs over 350 turns. It is not a real game — the same cities are
founded twice and the history repeats — so its digest size is perhaps
10–15% high. The builder is not committed; it is twenty lines that clone
`game_events` rows with `insert_all`.

## What an analysis costs

`DigestBuilder` output is JSON, which is token-dense. One measured point
anchors the conversion: `babylon-domination`'s 151 KB digest billed 54 073
input tokens, so ~2.9 bytes per token.

On Claude Opus 5.5 at $4 per MTok input and $20 per MTok output, with 1M
context and no long-context surcharge (unlike Haiku 5.5, which prices
above 100K tokens separately):

| game | digest | input tokens | cost per run |
| --- | --- | --- | --- |
| `babylon-domination` (6.3k events) | 151 KB | 54k | $0.31 |
| `india-diplo` (18k events) | 244 KB | ~87k | $0.44 |
| 8 civs / 350 turns (47k events) | 540 KB | ~190k | **~$0.90** |

Context is not the constraint at 1M. Cost is, mildly, and it doubles when
the chronicle runs on the same digest as the analysis.

Two caveats on the token figures. The 54 073 came from a Sonnet 4.6 run,
and the Opus 4.7-and-later tokenizer can use up to 1.35x as many tokens for
the same bytes, which would put a full game near 250k tokens and $1.15. Use
`messages.count_tokens` against the real digest rather than this table once
the game is long enough to matter.

Running the analysis and the chronicle back to back on one digest is worth
a cache breakpoint on the digest block. Two uncached runs pay $1.52 of
input; a cache write at $5 per MTok plus a read at $0.20 pays $0.99. The
default cache TTL is 5 minutes, with a 1-hour option.
