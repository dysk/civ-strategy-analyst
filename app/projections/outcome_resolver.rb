class OutcomeResolver
  def initialize(game, winner_civ: nil, victory_type: nil)
    @game = game
    @winner_civ = winner_civ
    @victory_type = victory_type
  end

  def call
    return declared_result if @winner_civ.present?
    return logged_result if @game.completed?

    inferred_result
  end

  private

  def declared_result
    { winner_civ: @winner_civ, victory_type: @victory_type, in_progress: false, source: :declared }
  end

  # ImportGame writes the winner, victory type and completion off the
  # logger's game_ended record. A scrapped game leaves both winner columns
  # nil - it is over, and nobody won it, so there is nothing to infer.
  def logged_result
    { winner_civ: @game.winner_civ, victory_type: @game.victory_type, in_progress: false, source: :logged }
  end

  def inferred_result
    ranking = MetricSeries.for(@game).ranking("score")
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

    timeline = CapitalsTimeline.for(@game)
    roster.find { |civ| (roster - capitals_held(civ, timeline)).empty? }
  end

  # A game can end on the very capture that completes a domination victory,
  # before another snapshot is logged to report it, so on top of the last
  # known snapshot we credit any capital captured since. The captured
  # capital's old_owner stands in for its original civ, which holds as long
  # as that capital hadn't already changed hands earlier in the same gap.
  def capitals_held(civ, timeline)
    latest_snapshot = @game.event_log.by("snapshot", :civ).fetch(civ, []).last
    capitals = latest_snapshot&.payload&.[]("capitals")
    known = capitals.is_a?(Hash) ? [] : Array(capitals)
    since_seq = latest_snapshot&.seq || -1

    gained = @game.event_log.of_type("city_captured")
      .select { |e| e.seq > since_seq && e.payload["capital"] && e.payload["new_owner"] == civ }
      .map { |e| e.payload["old_owner"] }
      .compact

    known | gained
  end

  def science_victor
    timeline = SpaceshipTimeline.for(@game)
    @game.players.pluck(:civ).find { |civ| SpaceshipTimeline.complete?(timeline.latest(civ)&.[](:spaceship)) }
  end

  # Compares the last known Congress snapshot's delegate votes against
  # that same snapshot's threshold, not a later one - the threshold
  # itself moves as delegates enter with later eras.
  def diplomatic_victor
    last_snapshot = @game.event_log.of_type("congress_snapshot").max_by { |e| [ e.turn, e.seq ] }
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
    events = @game.event_log.of_type("snapshot").select { |e| e.turn == turn && e.civ }
    living_majors = events.map(&:civ).uniq.size
    return nil if living_majors < 2

    events.select { |e| e.payload["civs_influential_on"] && e.payload["civs_influential_on"] >= living_majors - 1 }
      .max_by { |e| e.payload["civs_influential_on"] }
      &.civ
  end
end
