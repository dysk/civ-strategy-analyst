class KeyMomentDetector
  UNIT_LOST_SPIKE_THRESHOLD = 3
  LEADER_CHANGE_METRICS = %w[score science].freeze
  EARLY_GAME_GRACE_PERIOD_QUICK = 67
  EARLY_GAME_GRACE_PERIOD_DEFAULT = 100
  MILITARY_MIGHT_SWING_THRESHOLD = 0.15
  HAPPINESS_SWING_THRESHOLD = 10
  SNOWBALL_WINDOW = 10
  SNOWBALL_MIN_STRETCH = 15

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
    end.select { |moment| moment[:turn] > early_game_grace_period }.sort_by { |moment| moment[:turn] }
  end

  def era_leads
    of_type("era_entered")
      .group_by { |e| e.payload["era"] }
      .map do |era, events|
        first_turn = events.map(&:turn).min
        civs = events.select { |e| e.turn == first_turn }.flat_map { |e| Array(e.payload["civs"]) }
        { type: :era_lead, turn: first_turn, era: era, civs: civs }
      end
      .sort_by { |moment| moment[:turn] }
  end

  def religion_foundings
    of_type("religion_founded")
      .sort_by(&:turn)
      .each_with_index.map do |e, index|
        { type: :religion_founded, turn: e.turn, civ: e.civ, religion: e.payload["religion"],
          holy_city: e.payload["holy_city"], order: index + 1 }
      end
  end

  def military_might_swings
    metric_series = MetricSeries.new(@game)

    civs_with_snapshots.flat_map do |civ|
      candidates = metric_series.values("military_might", civ).each_cons(2).filter_map do |(prev_turn, prev), (turn, value)|
        next if prev.to_i.zero?

        pct_change = (value - prev).to_f / prev
        next if pct_change.abs < MILITARY_MIGHT_SWING_THRESHOLD

        type = pct_change.negative? ? :military_might_collapse : :military_might_surge
        { type: type, civ: civ, from_turn: prev_turn, to_turn: turn, from: prev, to: value }
      end

      merge_consecutive_runs(candidates).map do |run|
        { type: run[:type], civ: run[:civ], turn: run[:from_turn], turn_end: run[:to_turn],
          from: run[:from], to: run[:to], pct_change: ((run[:to] - run[:from]).to_f / run[:from]).round(3) }
      end
    end.select { |moment| moment[:turn] > early_game_grace_period }.sort_by { |moment| moment[:turn] }
  end

  def happiness_swings
    metric_series = MetricSeries.new(@game)

    civs_with_snapshots.flat_map do |civ|
      candidates = metric_series.values("happiness", civ).each_cons(2).filter_map do |(prev_turn, prev), (turn, value)|
        next if prev.nil? || value.nil?

        delta = value - prev
        next if delta.abs < HAPPINESS_SWING_THRESHOLD

        type = delta.negative? ? :happiness_collapse : :happiness_surge
        { type: type, civ: civ, from_turn: prev_turn, to_turn: turn, from: prev, to: value }
      end

      merge_consecutive_runs(candidates).map do |run|
        { type: run[:type], civ: run[:civ], turn: run[:from_turn], turn_end: run[:to_turn],
          from: run[:from], to: run[:to], delta: run[:to] - run[:from] }
      end
    end.select { |moment| moment[:turn] > early_game_grace_period }.sort_by { |moment| moment[:turn] }
  end

  def unhappiness_periods
    metric_series = MetricSeries.new(@game)

    civs_with_snapshots.flat_map do |civ|
      metric_series.values("happiness", civ)
        .reject { |_turn, value| value.nil? }
        .chunk_while { |(_, v1), (_, v2)| v1.negative? == v2.negative? }
        .select { |chunk| chunk.first.last.negative? }
        .map { |chunk| { type: :unhappiness_period, civ: civ, turn: chunk.first.first, turn_end: chunk.last.first } }
    end.sort_by { |moment| moment[:turn] }
  end

  def snowballs(metric)
    metric_series = MetricSeries.new(@game)
    rolling = civs_with_snapshots.each_with_object({}) do |civ, h|
      h[civ] = rolling_slope(metric_series.values(metric, civ))
    end

    common_turns = rolling.values.map(&:keys).reduce(:&) || []
    return [] if common_turns.empty?

    pace_leader_runs(common_turns.sort, rolling)
      .select { |run| run[:end_turn] - run[:start_turn] >= SNOWBALL_MIN_STRETCH }
      .map do |run|
        { type: :snowball, civ: run[:civ], turn: run[:start_turn], turn_end: run[:end_turn],
          duration_turns: run[:end_turn] - run[:start_turn] }
      end
  end

  def nuclear_detonations
    of_type("nuclear_detonation")
      .map do |e|
        { type: :nuclear_detonation, turn: e.turn, civ: e.civ, city: e.payload["city"],
          bystander_war: e.payload["bystander_war"] }
      end
      .sort_by { |moment| moment[:turn] }
  end

  def city_state_ally_takeovers
    of_type("city_state_ally_changed")
      .select { |e| e.payload["old_ally"].present? && e.payload["new_ally"].present? }
      .map do |e|
        { type: :city_state_ally_takeover, turn: e.turn, city_state: e.payload["city_state"],
          from: e.payload["old_ally"], to: e.payload["new_ally"] }
      end
      .sort_by { |moment| moment[:turn] }
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

  def civs_with_snapshots
    of_type("snapshot").map(&:civ).uniq
  end

  def rolling_slope(values)
    values.each_cons(SNOWBALL_WINDOW + 1).each_with_object({}) do |window, slopes|
      first_turn, first_value = window.first
      last_turn, last_value = window.last
      slopes[last_turn] = (last_value - first_value).to_f / (last_turn - first_turn)
    end
  end

  def pace_leader_runs(turns, rolling)
    runs = []

    turns.each do |turn|
      leader = rolling.max_by { |_civ, slopes| slopes[turn] }.first

      if runs.any? && runs.last[:civ] == leader
        runs.last[:end_turn] = turn
      else
        runs << { civ: leader, start_turn: turn, end_turn: turn }
      end
    end

    runs
  end

  def team_pair(a, b)
    [ a, b ].sort
  end

  def merge_consecutive_runs(candidates)
    runs = []

    candidates.each do |candidate|
      last = runs.last

      if last && last[:type] == candidate[:type] && last[:to_turn] == candidate[:from_turn]
        last[:to_turn] = candidate[:to_turn]
        last[:to] = candidate[:to]
      else
        runs << candidate.dup
      end
    end

    runs
  end

  def early_game_grace_period
    @game.game_speed.to_s.upcase.include?("QUICK") ? EARLY_GAME_GRACE_PERIOD_QUICK : EARLY_GAME_GRACE_PERIOD_DEFAULT
  end
end
