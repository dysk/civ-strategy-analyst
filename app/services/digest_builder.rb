class DigestBuilder
  CHECKPOINT_INTERVAL = 25
  SNAPSHOT_METRICS = %w[
    score science culture gold gold_per_turn faith happiness
    military_might military_units population cities techs
  ].freeze

  # LEKMOD rule: every owned city raises the cost of researching a new tech
  # by +5%, and the cost of a culture-bought policy by +10% (additive per
  # city). These multipliers let the LLM interpret raw tech/policy counts
  # correctly instead of comparing wide and tall empires at face value.
  TECH_COST_PER_CITY = 0.05
  POLICY_COST_PER_CITY = 0.10

  def initialize(game, winner_civ: nil, victory_type: nil)
    @game = game
    @winner_civ = winner_civ
    @victory_type = victory_type
  end

  def call
    {
      game: game_settings,
      roster: roster,
      outcome: outcome,
      standings: standings,
      metrics: metrics_by_civ,
      timelines: timelines_by_civ,
      key_moments: key_moments
    }
  end

  private

  def standings
    MetricSeries.new(@game).final_ranking("score")
  end

  def game_settings
    {
      name: @game.name, map_script: @game.map_script, map_size: @game.map_size,
      game_speed: @game.game_speed, max_turns: @game.max_turns, start_era: @game.start_era
    }
  end

  def roster
    @game.players.order(:id).map do |player|
      { civ: player.civ, leader_name: player.leader_name, human: player.human, handicap: player.handicap }
    end
  end

  def outcome
    OutcomeResolver.new(@game, winner_civ: @winner_civ, victory_type: @victory_type).call
  end

  def metrics_by_civ
    snapshots_by_civ_turn.each_with_object({}) do |(civ, turns), result|
      result[civ] = checkpoints_for(turns)
    end
  end

  def snapshots_by_civ_turn
    @game.game_events.where(event_type: "snapshot").where.not(civ: nil).order(:seq)
      .each_with_object(Hash.new { |h, k| h[k] = {} }) { |e, h| h[e.civ][e.turn] = e.payload }
  end

  def checkpoints_for(turns)
    max_turn = turns.keys.max
    return {} unless max_turn

    checkpoints = (CHECKPOINT_INTERVAL..max_turn).step(CHECKPOINT_INTERVAL).to_a
    checkpoints << max_turn unless checkpoints.last == max_turn

    checkpoints.each_with_object({}) do |checkpoint, result|
      nearest_turn = turns.keys.select { |t| t <= checkpoint }.max
      next unless nearest_turn

      metrics = turns[nearest_turn].slice(*SNAPSHOT_METRICS)
      result[checkpoint] = metrics.merge(cost_multipliers(metrics["cities"]))
    end
  end

  def cost_multipliers(cities)
    return {} unless cities

    cities_beyond_capital = [ cities - 1, 0 ].max

    {
      "tech_cost_multiplier" => (1 + TECH_COST_PER_CITY * cities_beyond_capital).round(3),
      "policy_cost_multiplier" => (1 + POLICY_COST_PER_CITY * cities_beyond_capital).round(3)
    }
  end

  def timelines_by_civ
    timeline = PlayerTimeline.new(@game)

    civs.each_with_object({}) do |civ, result|
      result[civ] = {
        cities: timeline.cities(civ),
        techs: timeline.techs(civ),
        policies: timeline.policies(civ),
        religion: timeline.religion(civ),
        wars: timeline.wars(civ),
        great_people: timeline.great_people(civ),
        eras: timeline.eras(civ),
        golden_ages: timeline.golden_ages(civ),
        wonders: timeline.wonders(civ),
        city_states: timeline.city_states(civ)
      }
    end
  end

  def key_moments
    detector = KeyMomentDetector.new(@game)

    {
      wars: detector.wars,
      leader_changes: detector.leader_changes,
      era_leads: detector.era_leads,
      religion_foundings: detector.religion_foundings,
      military_might_collapses: detector.military_might_collapses,
      snowballs_score: detector.snowballs("score"),
      snowballs_population: detector.snowballs("population"),
      snowballs_science: detector.snowballs("science"),
      nuclear_detonations: detector.nuclear_detonations,
      city_state_ally_takeovers: detector.city_state_ally_takeovers
    }
  end

  def civs
    @game.players.order(:id).pluck(:civ)
  end
end
