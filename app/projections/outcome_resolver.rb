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

    domination_winner = domination_victor
    return { winner_civ: domination_winner, victory_type: "domination", in_progress: false, source: :inferred } if domination_winner

    science_winner = science_victor
    return { winner_civ: science_winner, victory_type: "science", in_progress: false, source: :inferred } if science_winner

    diplomatic_winner = diplomatic_victor
    return { winner_civ: diplomatic_winner, victory_type: "diplomatic", in_progress: false, source: :inferred } if diplomatic_winner

    cultural_winner = cultural_victor_at(last_turn)
    return { winner_civ: cultural_winner, victory_type: "cultural", in_progress: false, source: :inferred } if cultural_winner

    leader = ranking[last_turn].first
    in_progress = @game.max_turns.nil? || last_turn < @game.max_turns

    { winner_civ: leader, victory_type: nil, in_progress: in_progress, source: :inferred }
  end

  # Checked against the whole original roster, not just currently-living
  # majors like the cultural check - an eliminated rival's original
  # capital still counts toward domination once captured.
  def domination_victor
    roster = @game.players.pluck(:civ)
    return nil if roster.size < 2

    timeline = CapitalsTimeline.new(@game)
    roster.find do |civ|
      capitals = timeline.latest(civ)&.[](:capitals)
      capitals && (roster - capitals).empty?
    end
  end

  def science_victor
    timeline = SpaceshipTimeline.new(@game)
    @game.players.pluck(:civ).find { |civ| SpaceshipTimeline.complete?(timeline.latest(civ)&.[](:spaceship)) }
  end

  # Compares the last known Congress snapshot's delegate votes against
  # that same snapshot's threshold, not a later one - the threshold
  # itself moves as delegates enter with later eras.
  def diplomatic_victor
    last_snapshot = @game.game_events.where(event_type: "congress_snapshot").order(:turn).last
    return nil unless last_snapshot

    votes_needed = last_snapshot.payload["votes_needed_for_diplo_victory"]
    return nil unless votes_needed

    Array(last_snapshot.payload["delegates"])
      .select { |delegate| delegate["votes"] && delegate["votes"] >= votes_needed }
      .max_by { |delegate| delegate["votes"] }
      &.[]("civ")
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
