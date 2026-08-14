class OutcomeResolver
  def initialize(game, winner_civ: nil, victory_type: nil)
    @game = game
    @winner_civ = winner_civ
    @victory_type = victory_type
  end

  def call
    return declared_result if @winner_civ.present?

    inferred_result
  end

  private

  def declared_result
    { winner_civ: @winner_civ, victory_type: @victory_type, in_progress: false, source: :declared }
  end

  def inferred_result
    ranking = MetricSeries.new(@game).ranking("score")
    last_turn = ranking.keys.max

    return { winner_civ: nil, victory_type: nil, in_progress: true, source: :inferred } if last_turn.nil?

    leader = ranking[last_turn].first
    in_progress = @game.max_turns.nil? || last_turn < @game.max_turns

    { winner_civ: leader, victory_type: nil, in_progress: in_progress, source: :inferred }
  end
end
