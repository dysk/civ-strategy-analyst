class KeyMomentDetector
  UNIT_LOST_SPIKE_THRESHOLD = 3
  LEADER_CHANGE_METRICS = %w[score science production].freeze
  INFLUENCE_TARGET_LEVELS = %w[INFLUENCE_LEVEL_INFLUENTIAL INFLUENCE_LEVEL_DOMINANT].freeze
  EARLY_GAME_GRACE_PERIOD_QUICK = 67
  EARLY_GAME_GRACE_PERIOD_DEFAULT = 100
  MILITARY_MIGHT_SWING_THRESHOLD = 0.15
  HAPPINESS_SWING_THRESHOLD = 10
  SNOWBALL_WINDOW = 10
  SNOWBALL_MIN_STRETCH = 15
  IDEOLOGY_BRANCHES = %w[POLICY_BRANCH_FREEDOM POLICY_BRANCH_ORDER POLICY_BRANCH_AUTOCRACY].freeze

  # LEKMOD keeps the underlying policy IDs from vanilla Civ5 BNW even where it
  # renames the displayed policy (e.g. POLICY_MERCHANT_NAVY is shown in-game
  # as "Colonialism" under Exploration), so these are internal constant names.
  BRANCH_POLICIES = {
    "POLICY_BRANCH_TRADITION" => %w[POLICY_LEGALISM POLICY_LANDED_ELITE POLICY_MONARCHY POLICY_OLIGARCHY POLICY_ARISTOCRACY],
    "POLICY_BRANCH_LIBERTY" => %w[POLICY_REPUBLIC POLICY_COLLECTIVE_RULE POLICY_CITIZENSHIP POLICY_REPRESENTATION POLICY_MERITOCRACY],
    "POLICY_BRANCH_HONOR" => %w[POLICY_WARRIOR_CODE POLICY_PROFESSIONAL_ARMY POLICY_MILITARY_CASTE POLICY_DISCIPLINE POLICY_MILITARY_TRADITION],
    "POLICY_BRANCH_PIETY" => %w[POLICY_ORGANIZED_RELIGION POLICY_REFORMATION POLICY_MANDATE_OF_HEAVEN POLICY_FREE_RELIGION POLICY_THEOCRACY],
    "POLICY_BRANCH_EXPLORATION" => %w[POLICY_NAVAL_TRADITION POLICY_MARITIME_INFRASTRUCTURE POLICY_MERCHANT_NAVY POLICY_NAVIGATION_SCHOOL POLICY_TREASURE_FLEETS],
    "POLICY_BRANCH_RATIONALISM" => %w[POLICY_SOVEREIGNTY POLICY_FREE_THOUGHT POLICY_HUMANISM POLICY_SCIENTIFIC_REVOLUTION POLICY_SECULARISM],
    "POLICY_BRANCH_PATRONAGE" => %w[POLICY_MERCHANT_CONFEDERACY POLICY_SCHOLASTICISM POLICY_CULTURAL_DIPLOMACY POLICY_PHILANTHROPY POLICY_CONSULATES],
    "POLICY_BRANCH_COMMERCE" => %w[POLICY_SILK_ROAD POLICY_MERCENARY_ARMY POLICY_ENTREPRENEURSHIP POLICY_MERCANTILISM POLICY_PROTECTIONISM],
    "POLICY_BRANCH_AESTHETICS" => %w[POLICY_CULTURAL_CENTERS POLICY_CULTURAL_EXCHANGE POLICY_ARTISTIC_GENIUS POLICY_FLOURISHING_OF_THE_ARTS POLICY_FINE_ARTS]
  }.freeze

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
          holy_city: e.payload["holy_city"], beliefs: e.payload["beliefs"], order: index + 1 }
      end
  end

  def pantheon_foundings
    of_type("pantheon_founded")
      .sort_by(&:turn)
      .map { |e| { type: :pantheon_founded, turn: e.turn, civ: e.civ, city: e.payload["city"], belief: e.payload["belief"] } }
  end

  def religion_enhancements
    of_type("religion_enhanced")
      .sort_by(&:turn)
      .map { |e| { type: :religion_enhanced, turn: e.turn, civ: e.civ, religion: e.payload["religion"], beliefs: e.payload["beliefs"] } }
  end

  def reformations
    of_type("reformation_added")
      .sort_by(&:turn)
      .map { |e| { type: :reformation_added, turn: e.turn, civ: e.civ, religion: e.payload["religion"], belief: e.payload["belief"] } }
  end

  def ideology_unlocks
    of_type("policy_branch_unlocked")
      .select { |e| IDEOLOGY_BRANCHES.include?(e.payload["branch"]) }
      .sort_by(&:turn)
      .map { |e| { type: :ideology_unlocked, turn: e.turn, civ: e.civ, ideology: e.payload["branch"] } }
  end

  def ideology_adoptions
    of_type("policy_branch_adopted")
      .select { |e| IDEOLOGY_BRANCHES.include?(e.payload["branch"]) }
      .sort_by(&:turn)
      .map { |e| { type: :ideology_adopted, turn: e.turn, civ: e.civ, ideology: e.payload["branch"] } }
  end

  def tenet_adoptions
    ideology_by_civ = ideology_adoptions.index_by { |moment| moment[:civ] }

    of_type("policy_adopted")
      .select { |e| ideology_by_civ[e.civ] && e.turn >= ideology_by_civ[e.civ][:turn] }
      .sort_by(&:turn)
      .map do |e|
        { type: :tenet_adopted, turn: e.turn, civ: e.civ, ideology: ideology_by_civ[e.civ][:ideology], tenet: e.payload["policy"] }
      end
  end

  def policy_branch_adoptions
    of_type("policy_branch_adopted")
      .reject { |e| IDEOLOGY_BRANCHES.include?(e.payload["branch"]) }
      .sort_by(&:turn)
      .map { |e| { type: :policy_branch_adopted, turn: e.turn, civ: e.civ, branch: e.payload["branch"] } }
  end

  def policy_branch_completions
    of_type("policy_adopted")
      .group_by(&:civ)
      .flat_map do |civ, events|
        adopted_policies = events.map { |e| e.payload["policy"] }

        BRANCH_POLICIES.filter_map do |branch, policies|
          next unless (policies - adopted_policies).empty?

          completion_turn = events.select { |e| policies.include?(e.payload["policy"]) }.map(&:turn).max
          { type: :policy_branch_completed, turn: completion_turn, civ: civ, branch: branch }
        end
      end
      .sort_by { |moment| moment[:turn] }
  end

  # Measured on army power rather than the game's own military might,
  # which the treasury inflates - a civilization banking gold would
  # otherwise show a build-up it never built.
  def army_power_swings
    armies = ArmyComposition.new(@game)

    civs_with_snapshots.flat_map do |civ|
      candidates = army_power_values(armies, civ).each_cons(2).filter_map do |(prev_turn, prev), (turn, value)|
        next if prev.to_i.zero?

        pct_change = (value - prev).to_f / prev
        next if pct_change.abs < MILITARY_MIGHT_SWING_THRESHOLD

        type = pct_change.negative? ? :army_power_collapse : :army_power_surge
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

  def influence_level_reached
    timeline = InfluenceTimeline.new(@game)

    civs_with_snapshots.flat_map do |civ|
      timeline.opponents(civ).flat_map do |opponent|
        timeline.level_changes(civ, opponent)
          .select { |change| INFLUENCE_TARGET_LEVELS.include?(change[:to]) }
          .map { |change| { type: :influence_level_reached, turn: change[:turn], civ: civ, opponent: opponent, level: change[:to] } }
      end
    end.sort_by { |moment| moment[:turn] }
  end

  # Living majors is the count of civs a turn's snapshots actually cover -
  # the logger emits no elimination event, so a civ dropping out of the
  # snapshot round is the only signal that it's gone.
  def cultural_victory_imminent
    of_type("snapshot").group_by(&:turn).sort.each_with_object([]) do |(turn, events), moments|
      living_majors = events.map(&:civ).uniq.size
      next if living_majors < 2

      events.each do |e|
        civs_influential_on = e.payload["civs_influential_on"]
        next unless civs_influential_on && civs_influential_on >= living_majors - 1
        next if moments.any? { |moment| moment[:civ] == e.civ }

        moments << { type: :cultural_victory_imminent, turn: turn, civ: e.civ,
                      civs_influential_on: civs_influential_on, living_majors: living_majors }
      end
    end.sort_by { |moment| moment[:turn] }
  end

  def congress_host_changes
    of_type("congress_host_changed")
      .map { |e| { type: :congress_host_change, turn: e.turn, from: e.payload["old_host"], to: e.payload["new_host"] } }
      .sort_by { |moment| moment[:turn] }
  end

  def united_nations_formed
    of_type("united_nations_formed")
      .map { |e| { type: :united_nations_formed, turn: e.turn } }
      .sort_by { |moment| moment[:turn] }
  end

  # Compares each snapshot's delegate votes against that same snapshot's
  # votes_needed, not the latest known threshold - the threshold itself
  # can move (more delegates enter as civs reach later eras).
  def diplomatic_victory_imminent
    of_type("congress_snapshot").sort_by(&:turn).each_with_object([]) do |e, moments|
      votes_needed = e.payload["votes_needed_for_diplo_victory"]
      next unless votes_needed

      Array(e.payload["delegates"]).each do |delegate|
        next if delegate["votes"].nil? || delegate["votes"] < votes_needed
        next if moments.any? { |moment| moment[:civ] == delegate["civ"] }

        moments << { type: :diplomatic_victory_imminent, turn: e.turn, civ: delegate["civ"],
                      votes: delegate["votes"], votes_needed: votes_needed }
      end
    end.sort_by { |moment| moment[:turn] }
  end

  def resolutions_passed
    CongressTimeline.new(@game).resolutions
      .select { |resolution| resolution[:outcome] == :passed }
      .map { |resolution| { type: :resolution_passed, turn: resolution[:outcome_turn],
                             resolution: resolution[:resolution], proposer: resolution[:proposer] } }
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

  # A snapshot with no treasury cannot have the multiplier divided out,
  # so it takes no part in the comparison rather than being guessed at.
  def army_power_values(armies, civ)
    armies.series(civ).filter_map { |entry| [ entry[:turn], entry[:army_power] ] if entry[:army_power] }
  end

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
    values.reject { |_turn, value| value.nil? }.each_cons(SNOWBALL_WINDOW + 1).each_with_object({}) do |window, slopes|
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
