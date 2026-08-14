class MetricSeries
  def initialize(game)
    @by_civ_turn = Hash.new { |h, civ| h[civ] = {} }

    game.game_events.where(event_type: "snapshot").where.not(civ: nil).order(:seq).each do |event|
      @by_civ_turn[event.civ][event.turn] = event
    end
  end

  def values(metric, civ)
    turns_for(civ).map { |turn| [ turn, @by_civ_turn[civ][turn].payload[metric] ] }
  end

  def deltas(metric, civ)
    values(metric, civ).each_cons(2).map do |(_prev_turn, prev_value), (turn, value)|
      [ turn, value - prev_value ]
    end
  end

  def ranking(metric)
    all_turns.each_with_object({}) do |turn, result|
      civs_at_turn = @by_civ_turn.keys.select { |civ| @by_civ_turn[civ].key?(turn) }
      result[turn] = civs_at_turn.sort_by { |civ| -@by_civ_turn[civ][turn].payload[metric] }
    end
  end

  def leader_changes(metric)
    previous_leader = nil

    ranking(metric).sort.each_with_object([]) do |(turn, civs), changes|
      leader = civs.first
      changes << { turn: turn, from: previous_leader, to: leader } if previous_leader && leader != previous_leader
      previous_leader = leader
    end
  end

  private

  def turns_for(civ)
    @by_civ_turn[civ].keys.sort
  end

  def all_turns
    @by_civ_turn.values.flat_map(&:keys).uniq.sort
  end
end
