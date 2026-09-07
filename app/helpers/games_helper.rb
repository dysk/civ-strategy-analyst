module GamesHelper
  # Where the outcome came from: inferred from the score curve, handed in by
  # hand, or read from the logger's own game_ended record.
  OUTCOME_SOURCES = {
    inferred: "inferred leader", declared: "declared winner", logged: "from game log"
  }.freeze

  def outcome_source_label(source) = OUTCOME_SOURCES.fetch(source, source.to_s)

  # A team victory keeps every member; winner_civ is only its first name.
  def outcome_winner_names(game, outcome)
    game.winner_civs.presence&.join(", ") || outcome[:winner_civ]
  end
end
