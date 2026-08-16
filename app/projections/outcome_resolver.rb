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

    cultural_winner = cultural_victor_at(last_turn)
    return { winner_civ: cultural_winner, victory_type: "cultural", in_progress: false, source: :inferred } if cultural_winner

    leader = ranking[last_turn].first
    in_progress = @game.max_turns.nil? || last_turn < @game.max_turns

    { winner_civ: leader, victory_type: nil, in_progress: in_progress, source: :inferred }
  end

  # Living majors is the count of civs the final turn's snapshots cover -
  # the logger emits no elimination event, so a civ dropping out of the
  # snapshot round is the only signal that it's gone. Fewer than two
  # living majors means the game already ended by domination, not culture.
  def cultural_victor_at(turn)
    events = @game.game_events.where(event_type: "snapshot", turn: turn).where.not(civ: nil).to_a
    living_majors = events.map(&:civ).uniq.size
    return nil if living_majors < 2

    events.select { |e| e.payload["civs_influential_on"] && e.payload["civs_influential_on"] >= living_majors - 1 }
      .max_by { |e| e.payload["civs_influential_on"] }
      &.civ
  end
end
