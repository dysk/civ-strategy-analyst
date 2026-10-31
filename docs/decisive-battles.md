# Decisive battles

`KeyMomentDetector#battle_scale` marks a battle `:decisive`. `ChronicleSpine`
gives a decisive battle `ANCHOR_WEIGHT`, the same weight as a border city falling.

## Rule

A battle is decisive when at least one side meets both conditions:

| Condition | Value | Constant |
|---|---|---|
| Share of its soldiers lost | at least 25% | `DECISIVE_BATTLE_SHARE` |
| Soldiers lost | at least 3 | `Battles::MIN_LOSSES` |

- The soldier count comes from `OrderOfBattle#soldiers_at`, on the turn before the battle.
- Civilians count on neither side of the share, and scouts count as soldiers.
- A side with no soldiers on record takes no part in the judgment.
- A battle with no qualifying side stays on the battles page as texture.

## Sample

- 67 battles from 5 unique real games: Babylon domination, Chile vs Vietnam Pangaea, India diplo, Arabia test, and Czechia 6p test (no battles detected).
- 25 of the 67 name a killer and can reach the chronicle: 11 from Chile vs Vietnam Pangaea, 9 from Babylon domination, 5 from India diplo (reconciled).
- Arabia test has no reconciled import, so none of its battles names a killer.
- The sample excludes duplicate imports and the synthetic game.
- All five games run at quick speed and have one human player.
- The hardest-hit side's army has a median of 13 soldiers and a 75th percentile of 20.

## Candidate thresholds

Counts cover the share condition alone.

| Share | Decisive (of 67) | In chronicle (of 25) | In chronicle, even split (of 25) | Largest army where 3 losses qualify |
|---|---|---|---|---|
| 15% | 50 | 19 | 11 | 20 |
| 20% | 44 | 15 | 7 | 15 |
| 25% | 36 | 12 | 6 | 12 |
| 30% | 30 | 11 | 4 | 10 |
| 40% | 22 | 7 | 1 | 7 |

The even-split column halves each battle's share. It is a rough simulation of equal armies trading losses evenly, not a measurement.

Adding the 3-loss condition at 25% leaves 31 of 67 decisive and 11 of 25 in the chronicle.

## Why 25%

- A lower share lets the smallest possible battle qualify too easily. Three losses from the median army are 23%.
- A higher share gains little on these games. Moving to 30% removes one chronicle battle.
- A higher share costs more in even fights. Games between humans spread losses more evenly than games against bots, and `battle_scale` reads only the hardest-hit side. Twelve losses from an army of 20 are 60%, but six losses on each of two such armies are 30%.

## Why 3 losses

Small armies produce large shares from a few deaths. Without this condition, these count as decisive:

- Damascus: the Philippines lost 1 of 4.
- Trieste: a city-state lost 2 of 3.

The condition removes 5 of the 36 battles at 25%. It uses the same floor that makes a cluster a battle at all.

## Why a separate constant

`MILITARY_MIGHT_SWING_THRESHOLD` (15%) detects swings in army power, a different measure. Tuning battles against it would also move `army_power_collapse` and `army_power_surge`.

## Known limits

- **No games between humans:** the sample has none, and bot-only battles do not stand in for them. Bot-only battles put 89% of the dead on one side on average, against 83% in battles with the human player.
- **Quick speed only:** the battle window is 4 turns there. Standard speed merges more clusters, so shares should run higher.
- **City-states:** their garrisons barely reach the ledger, so entries such as 3 of 3 are unreliable. None of these battles names a killer, so they appear on the battles page but not in the chronicle.
- **Reinforcements:** the share compares the whole battle's losses with the opening army, so a long battle can exceed 100%. India lost 13 from a stock of 9 at Vijayanagara.

## When to revisit

- A log of a game between humans arrives.
- A standard-speed game with real wars arrives.
