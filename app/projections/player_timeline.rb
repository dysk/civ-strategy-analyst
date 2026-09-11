class PlayerTimeline
  extend Projection

  def initialize(game)
    @game = game
    @log = game.event_log
  end

  def cities(civ)
    founded = of_type("city_founded").select { |e| e.civ == civ }.map do |e|
      { turn: e.turn, city: e.payload["city"], action: :founded }
    end

    captured = of_type("city_captured").select { |e| e.payload["new_owner"] == civ }.map do |e|
      { turn: e.turn, city: e.payload["city"], action: :captured,
        from: e.payload["old_owner"], conquest: e.payload["conquest"], valuation: valuation(e) }
    end

    lost = of_type("city_captured").select { |e| e.payload["old_owner"] == civ }.map do |e|
      { turn: e.turn, city: e.payload["city"], action: :lost,
        to: e.payload["new_owner"], conquest: e.payload["conquest"], valuation: valuation(e) }
    end

    sort_events(founded + captured + lost)
  end

  def techs(civ)
    research = of_type("tech_researched").select { |e| Array(e.payload["civs"]).include?(civ) }.map do |e|
      { turn: e.turn, tech: e.payload["tech"], source: :research }
    end

    ruins = of_type("tech_from_ruins").select { |e| e.civ == civ }.map do |e|
      { turn: e.turn, tech: e.payload["tech"], source: :ruins }
    end

    sort_events(research + ruins)
  end

  def policies(civ)
    unlocked = of_type("policy_branch_unlocked").select { |e| e.civ == civ }.map do |e|
      { turn: e.turn, type: :branch_unlocked, name: e.payload["branch"] }
    end

    adopted = of_type("policy_adopted").select { |e| e.civ == civ }.map do |e|
      { turn: e.turn, type: :policy_adopted, name: e.payload["policy"] }
    end

    branch_adopted = of_type("policy_branch_adopted").select { |e| e.civ == civ }.map do |e|
      { turn: e.turn, type: :branch_adopted, name: e.payload["branch"] }
    end

    sort_events(unlocked + adopted + branch_adopted)
  end

  def religion(civ)
    pantheon = of_type("pantheon_founded").select { |e| e.civ == civ }.map do |e|
      { turn: e.turn, type: :pantheon_founded, city: e.payload["city"], belief: e.payload["belief"] }
    end

    founded = of_type("religion_founded").select { |e| e.civ == civ }.map do |e|
      { turn: e.turn, type: :religion_founded, holy_city: e.payload["holy_city"],
        religion: e.payload["religion"], beliefs: e.payload["beliefs"] }
    end

    enhanced = of_type("religion_enhanced").select { |e| e.civ == civ }.map do |e|
      { turn: e.turn, type: :religion_enhanced, religion: e.payload["religion"], beliefs: e.payload["beliefs"] }
    end

    reformation = of_type("reformation_added").select { |e| e.civ == civ }.map do |e|
      { turn: e.turn, type: :reformation_added, religion: e.payload["religion"], belief: e.payload["belief"] }
    end

    sort_events(pantheon + founded + enhanced + reformation)
  end

  def great_people(civ)
    of_type("great_person_expended").select { |e| e.civ == civ }.map do |e|
      { turn: e.turn, great_person: e.payload["great_person"] }
    end
  end

  def eras(civ)
    of_type("era_entered").select { |e| Array(e.payload["civs"]).include?(civ) }.map do |e|
      { turn: e.turn, era: e.payload["era"] }
    end
  end

  def golden_ages(civ)
    of_type("golden_age_started").select { |e| e.civ == civ }.map do |e|
      { turn: e.turn }
    end
  end

  def buildings(civ)
    sort_events(
      of_type("building_constructed").select { |e| e.civ == civ }.map do |e|
        { turn: e.turn, building: e.payload["building"], city: e.payload["city"],
          class: e.payload["wonder"]&.to_sym }
      end
    )
  end

  def wonders(civ)
    buildings(civ).select { |building| building[:class].in?(%i[world national]) }
  end

  def city_states(civ)
    friendship = of_type("city_state_friendship_changed").select { |e| e.civ == civ }.map do |e|
      { turn: e.turn, type: :friendship_changed, city_state: e.payload["city_state"],
        friends: e.payload["friends"], old_friendship: e.payload["old_friendship"],
        new_friendship: e.payload["new_friendship"] }
    end

    alliance = of_type("city_state_alliance_changed").select { |e| e.civ == civ }.map do |e|
      { turn: e.turn, type: :alliance_changed, city_state: e.payload["city_state"],
        allied: e.payload["allied"], old_friendship: e.payload["old_friendship"],
        new_friendship: e.payload["new_friendship"] }
    end

    ally_gained = of_type("city_state_ally_changed").select { |e| e.payload["new_ally"] == civ }.map do |e|
      { turn: e.turn, type: :ally_gained, city_state: e.payload["city_state"] }
    end

    ally_lost = of_type("city_state_ally_changed").select { |e| e.payload["old_ally"] == civ }.map do |e|
      { turn: e.turn, type: :ally_lost, city_state: e.payload["city_state"] }
    end

    sort_events(friendship + alliance + ally_gained + ally_lost)
  end

  def wars(civ)
    war_periods.select { |war| war[:civ] == civ }.map { |war| war.except(:civ) }
  end

  # The single vote, if any, that removed this civ from the game. A passed
  # irrelevance proposal happens once and ends the civ's contention.
  def irrelevance(civ)
    event = of_type("mp_proposal_result").find do |e|
      e.payload["type"] == "irrelevance" && e.payload["status"] == "passed" && e.payload["subject"] == civ
    end
    return unless event

    { turn: event.turn, proposer: event.payload["owner"],
      yes_votes: event.payload["yes_votes"], no_votes: event.payload["no_votes"] }
  end

  private

  # What a capture cost the side that lost it: the city's share of that
  # empire before the transfer, its size before and after, the resistance
  # the captor then sat through, and the captor's cultural standing over
  # the former owner on the capture turn. Nil where the log carries no
  # city snapshot to read any of it from.
  def valuation(capture)
    return unless city_value.applicable?

    city = capture.payload["city"]
    before = last_snapshot(city, capture.turn - 1)
    after = first_snapshot_from(city, capture.turn, capture.payload["new_owner"])

    { value: city_value.at(city, capture.turn - 1),
      before: size_of(before), after: size_of(after),
      resistance: resistance_after(city, capture),
      captor_influence: captor_influence(capture) }
  end

  def size_of(snapshot)
    return unless snapshot

    { population: snapshot.payload["population"].to_i, buildings: snapshot.payload["buildings"].to_i }
  end

  # The captor's snapshots of the city from the capture turn on, up to and
  # including the first turn its resistance had run out.
  def resistance_after(city, capture)
    rows = snapshots_of(city)
      .select { |e| e.turn >= capture.turn && e.civ == capture.payload["new_owner"] }
      .index_by(&:turn).values.sort_by(&:turn)
    settled = rows.index { |e| e.payload["resistance_turns"].to_i.zero? }

    (settled ? rows.first(settled + 1) : rows).map do |e|
      { turn: e.turn, resistance_turns: e.payload["resistance_turns"].to_i,
        occupied: e.payload["occupied"], puppet: e.payload["puppet"], razing: e.payload["razing"] }
    end
  end

  def captor_influence(capture)
    points = InfluenceTimeline.for(@game)
      .series(capture.payload["new_owner"], capture.payload["old_owner"])
      .select { |point| point[:turn] <= capture.turn }.last
    return unless points

    points.slice(:points, :level, :trend)
  end

  def last_snapshot(city, turn)
    snapshots_of(city).select { |e| e.turn <= turn }.max_by(&:turn)
  end

  def first_snapshot_from(city, turn, civ)
    snapshots_of(city).select { |e| e.turn >= turn && e.civ == civ }.min_by(&:turn)
  end

  def snapshots_of(city) = snapshots_by_city.fetch(city, [])

  def snapshots_by_city = @snapshots_by_city ||= of_type("city_snapshot").group_by { |e| e.payload["city"] }

  def city_value = @city_value ||= CityValue.for(@game)

  def of_type(event_type) = @log.of_type(event_type)

  def sort_events(events)
    events.sort_by { |e| e[:turn] }
  end

  def war_periods
    @war_periods ||= build_war_periods
  end

  def build_war_periods
    declarations = of_type("war_declared").group_by { |e| team_pair(e.payload["attacker_team"], e.payload["defender_team"]) }
    peaces = of_type("peace_made").group_by { |e| team_pair(e.payload["team_a"], e.payload["team_b"]) }

    declarations.flat_map do |pair, wars|
      wars.each_with_index.flat_map do |war_declared, index|
        peace = peaces[pair]&.[](index)
        periods_for(war_declared, peace)
      end
    end
  end

  def periods_for(war_declared, peace)
    attacker_civs = Array(war_declared.payload["attacker_civs"])
    defender_civs = Array(war_declared.payload["defender_civs"])

    (attacker_civs.map { |civ| [ civ, :attacker, defender_civs ] } +
     defender_civs.map { |civ| [ civ, :defender, attacker_civs ] }).map do |civ, role, opponents|
      {
        civ: civ,
        role: role,
        opponents: opponents,
        turn_declared: war_declared.turn,
        turn_peace: peace&.turn,
        ties_at_declaration: ties_at_declaration(civ, opponents, war_declared.turn)
      }.merge(balance(civ, opponents, war_declared.turn, peace&.turn))
    end
  end

  # Diplomacy standing with an opponent at the moment war opened on them -
  # docs/reading-the-new-log.md §6's join, the one the plan called out by
  # name. An embassy or a pact does not prevent a war; it can outlive the
  # declaration that breaks it.
  def ties_at_declaration(civ, opponents, turn)
    opponents.flat_map { |opponent|
      diplomatic_ties.spans(civ, opponent)
        .select { |span| span[:from_turn] <= turn && (span[:to_turn].nil? || span[:to_turn] >= turn) }
        .map { |span| span.merge(with: opponent) }
    }
  end

  def diplomatic_ties = @diplomatic_ties ||= DiplomaticTies.for(@game)

  def balance(civ, opponents, turn_declared, turn_peace)
    in_window = ->(turn) { turn >= turn_declared && (turn_peace.nil? || turn <= turn_peace) }

    kills = of_type("unit_killed").select { |e| in_window.call(e.turn) }
    captures = of_type("city_captured").select { |e| in_window.call(e.turn) }

    {
      units_killed: kills.count { |e| e.payload["killer"] == civ && opponents.include?(e.payload["victim"]) },
      units_lost: kills.count { |e| e.payload["victim"] == civ && opponents.include?(e.payload["killer"]) },
      cities_captured: captures.count { |e| e.payload["new_owner"] == civ && opponents.include?(e.payload["old_owner"]) },
      cities_lost: captures.count { |e| e.payload["old_owner"] == civ && opponents.include?(e.payload["new_owner"]) }
    }
  end

  def team_pair(a, b)
    [ a, b ].sort
  end
end
