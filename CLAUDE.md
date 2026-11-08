# Project map

Rails app. Analyzes Civ 5 + LEKMOD game logs (JSONL from civ-narrative-logger).

## Where things live
- app/projections/<name>.rb — projections: classes that derive one thing from the event log, most of them `extend Projection`.
  Most files open with a comment saying what they compute. Read it before the rest of the file.
- test/projections/<name>_test.rb — the projection's test, same file name.
- app/controllers, app/views/<name>, app/helpers — the projection's UI, named in the plural.
- app/services — log import, LLM analysis, CLI (bin/civ).
- app/prompts/analyze_game.md — prompt for the strategy report: how each player played and why they won or lost.
- app/prompts/chronicle_game.md — prompt for the chronicle: the game told as a narrative.
- docs/<topic>.md — design decisions behind individual projections, and plans for changes that cut across them (e.g. game-speed.md).
- docs/plan.md — full design, ~2200 lines; read it only for questions about overall architecture.

## Projections with similar names
- battles.rb (Battles) — battles: clusters of unit deaths close in time and near one city.
- order_of_battle.rb (OrderOfBattle) — what each civilization had under arms, turn by turn. Not battles.
- war_casualties.rb (WarCasualties) — what a war cost each side: units killed and units captured.
- unit_losses.rb (UnitLosses) — why a unit left the map (cause, confidence, killer), when the log records it.
- army_composition.rb (ArmyComposition) — what an army is made of, not how strong it is.
