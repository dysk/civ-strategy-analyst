class KeyMomentDetector
  UNIT_LOST_SPIKE_THRESHOLD = 3
  LEADER_CHANGE_METRICS = %w[score science].freeze

  def initialize(game)
    @game = game
    @events = game.game_events.order(:seq).to_a
  end

  def leader_changes
    metric_series = MetricSeries.new(@game)

    LEADER_CHANGE_METRICS.flat_map do |metric|
      metric_series.leader_changes(metric).map do |change|
        { type: :leader_change, metric: metric, turn: change[:turn], from: change[:from], to: change[:to] }
      end
    end.sort_by { |moment| moment[:turn] }
  end

  def wars
    war_declarations.map do |war_declared, peace|
      attacker_civs = Array(war_declared.payload["attacker_civs"])
      defender_civs = Array(war_declared.payload["defender_civs"])
      turn_declared = war_declared.turn
      turn_peace = peace&.turn
      participants = attacker_civs + defender_civs

      {
        type: :war,
        turn: turn_declared,
        turn_peace: turn_peace,
        attacker_civs: attacker_civs,
        defender_civs: defender_civs,
        cities_captured: cities_captured(participants, turn_declared, turn_peace),
        unit_lost_spikes: unit_lost_spikes(participants, turn_declared, turn_peace)
      }
    end
  end

  private

  def war_declarations
    declarations = of_type("war_declared").group_by { |e| team_pair(e.payload["attacker_team"], e.payload["defender_team"]) }
    peaces = of_type("peace_made").group_by { |e| team_pair(e.payload["team_a"], e.payload["team_b"]) }

    declarations.flat_map do |pair, wars|
      wars.each_with_index.map { |war_declared, index| [ war_declared, peaces[pair]&.[](index) ] }
    end
  end

  def cities_captured(civs, turn_declared, turn_peace)
    of_type("city_captured")
      .select { |e| in_window?(e.turn, turn_declared, turn_peace) && civs.include?(e.payload["new_owner"]) }
      .each_with_object(Hash.new(0)) { |e, counts| counts[e.payload["new_owner"]] += 1 }
  end

  def unit_lost_spikes(civs, turn_declared, turn_peace)
    of_type("unit_lost")
      .select { |e| in_window?(e.turn, turn_declared, turn_peace) && civs.include?(e.civ) }
      .group_by { |e| [ e.civ, e.turn ] }
      .filter_map do |(civ, turn), events|
        next if events.size < UNIT_LOST_SPIKE_THRESHOLD
        { civ: civ, turn: turn, count: events.size }
      end
      .sort_by { |spike| spike[:turn] }
  end

  def in_window?(turn, turn_declared, turn_peace)
    turn >= turn_declared && (turn_peace.nil? || turn <= turn_peace)
  end

  def of_type(event_type)
    @events.select { |e| e.event_type == event_type }
  end

  def team_pair(a, b)
    [ a, b ].sort
  end
end
