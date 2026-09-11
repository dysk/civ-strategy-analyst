require "test_helper"

class PlayerTimelineTest < ActiveSupport::TestCase
  setup do
    @game = Game.create!(name: "Timeline Test Game")
    @seq = 0
    @timeline = nil
  end

  test "cities lists founded, captured and lost with turns" do
    event("Rome", "city_founded", 1, city: "Roma", x: 1, y: 1)
    event(nil, "city_captured", 10, city: "Athens", old_owner: "Greece", new_owner: "Rome")
    event(nil, "city_captured", 15, city: "Roma", old_owner: "Rome", new_owner: "Carthage")

    cities = timeline.cities("Rome")

    assert_equal(
      [
        { turn: 1, city: "Roma", action: :founded },
        { turn: 10, city: "Athens", action: :captured, from: "Greece", conquest: nil, valuation: nil },
        { turn: 15, city: "Roma", action: :lost, to: "Carthage", conquest: nil, valuation: nil }
      ],
      cities
    )
  end

  test "cities records a city handed over without a fight as no conquest" do
    event(nil, "city_captured", 10, city: "Athens", old_owner: "Greece", new_owner: "Rome", conquest: false)

    assert_equal(
      [ { turn: 10, city: "Athens", action: :captured, from: "Greece", conquest: false, valuation: nil } ],
      timeline.cities("Rome")
    )
  end

  test "a captured city carries what it was worth to the empire that lost it" do
    city_snapshot("Iroquois", 151, "Onondaga", population: 18, buildings: 18, yield_science: 54)
    city_snapshot("Iroquois", 151, "Cattaraugus", population: 6, buildings: 6, yield_science: 6)
    city_snapshot("India", 153, "Onondaga", population: 9, buildings: 10, yield_science: 0)
    event(nil, "city_captured", 152, city: "Onondaga", old_owner: "Iroquois", new_owner: "India", conquest: true)

    valuation = timeline.cities("India").find { |c| c[:city] == "Onondaga" }[:valuation]

    assert_in_delta 0.9, valuation[:value][:science_share], 0.001
    assert_equal 1, valuation[:value][:population_rank]
    assert_equal({ population: 18, buildings: 18 }, valuation[:before])
    assert_equal({ population: 9, buildings: 10 }, valuation[:after])
  end

  test "the same valuation reaches the losing civ's timeline" do
    city_snapshot("Iroquois", 151, "Onondaga", population: 18, buildings: 18)
    city_snapshot("India", 153, "Onondaga", population: 9, buildings: 10)
    event(nil, "city_captured", 152, city: "Onondaga", old_owner: "Iroquois", new_owner: "India", conquest: true)

    lost = timeline.cities("Iroquois").find { |c| c[:city] == "Onondaga" }

    assert_equal :lost, lost[:action]
    assert_equal({ population: 18, buildings: 18 }, lost[:valuation][:before])
  end

  test "valuation observes the resistance that followed, capture turn through its end" do
    event(nil, "city_captured", 152, city: "Onondaga", old_owner: "Iroquois", new_owner: "India", conquest: true)
    city_snapshot("India", 152, "Onondaga", population: 9, buildings: 10, resistance_turns: 3, puppet: true)
    city_snapshot("India", 153, "Onondaga", population: 9, buildings: 10, resistance_turns: 2, puppet: true)
    city_snapshot("India", 154, "Onondaga", population: 10, buildings: 10, resistance_turns: 0, puppet: true)
    city_snapshot("India", 160, "Onondaga", population: 15, buildings: 12, resistance_turns: 0, puppet: true)

    resistance = timeline.cities("India").find { |c| c[:city] == "Onondaga" }[:valuation][:resistance]

    assert_equal [ 152, 153, 154 ], resistance.map { |r| r[:turn] }
    assert_equal [ 3, 2, 0 ], resistance.map { |r| r[:resistance_turns] }
    assert(resistance.all? { |r| r[:puppet] })
  end

  test "valuation names the captor's cultural standing over the former owner at the capture turn" do
    city_snapshot("Iroquois", 151, "Onondaga", population: 18)
    event(nil, "city_captured", 152, city: "Onondaga", old_owner: "Iroquois", new_owner: "India", conquest: true)
    snapshot_with_influence("India", 150, "Iroquois", points: 60, trend: "INFLUENCE_TREND_RISING")
    snapshot_with_influence("India", 155, "Iroquois", points: 90, trend: "INFLUENCE_TREND_RISING")

    influence = timeline.cities("India").find { |c| c[:city] == "Onondaga" }[:valuation][:captor_influence]

    assert_equal 60, influence[:points]
    assert_equal "INFLUENCE_TREND_RISING", influence[:trend]
  end

  test "a city handed over by diplomacy is still valued, and saw no resistance" do
    city_snapshot("Greece", 20, "Athens", population: 10, buildings: 8)
    event(nil, "city_captured", 21, city: "Athens", old_owner: "Greece", new_owner: "Rome", conquest: false)

    captured = timeline.cities("Rome").find { |c| c[:city] == "Athens" }

    assert_equal false, captured[:conquest]
    assert_equal({ population: 10, buildings: 8 }, captured[:valuation][:before])
    assert_empty captured[:valuation][:resistance]
  end

  test "cities carries no valuation when the log has no city snapshot" do
    event(nil, "city_captured", 10, city: "Athens", old_owner: "Greece", new_owner: "Rome")

    assert_nil timeline.cities("Rome").first[:valuation]
    assert_nil timeline.cities("Greece").first[:valuation]
  end

  test "founded cities carry no valuation key" do
    city_snapshot("Rome", 5, "Roma", population: 3)
    event("Rome", "city_founded", 1, city: "Roma", x: 1, y: 1)

    founded = timeline.cities("Rome").first

    assert_equal :founded, founded[:action]
    assert_not founded.key?(:valuation)
  end

  test "techs combines team research and goody hut techs for a civ" do
    event(nil, "tech_researched", 5, team: 1, civs: %w[Rome Egypt], tech: "TECH_POTTERY")
    event(nil, "tech_researched", 8, team: 2, civs: %w[Greece], tech: "TECH_BRONZE_WORKING")
    event("Rome", "tech_from_ruins", 6, tech: "TECH_WRITING")

    techs = timeline.techs("Rome")

    assert_equal(
      [
        { turn: 5, tech: "TECH_POTTERY", source: :research },
        { turn: 6, tech: "TECH_WRITING", source: :ruins }
      ],
      techs
    )
  end

  test "policies combines adopted policies and branch unlocks/adoptions" do
    event("Rome", "policy_branch_unlocked", 20, branch: "POLICY_BRANCH_HONOR")
    event("Rome", "policy_adopted", 21, policy: "POLICY_WARRIOR_CODE")
    event("Rome", "policy_branch_adopted", 25, branch: "POLICY_BRANCH_HONOR")
    event("Greece", "policy_adopted", 22, policy: "POLICY_LEGALISM")

    policies = timeline.policies("Rome")

    assert_equal(
      [
        { turn: 20, type: :branch_unlocked, name: "POLICY_BRANCH_HONOR" },
        { turn: 21, type: :policy_adopted, name: "POLICY_WARRIOR_CODE" },
        { turn: 25, type: :branch_adopted, name: "POLICY_BRANCH_HONOR" }
      ],
      policies
    )
  end

  test "religion tracks pantheon through reformation" do
    event("Rome", "pantheon_founded", 10, city: "Roma", belief: "BELIEF_GODDESS_OF_HARVEST")
    event("Rome", "religion_founded", 30, holy_city: "Roma", religion: "RELIGION_POLYTHEISM", beliefs: [ "BELIEF_X" ])
    event("Rome", "religion_enhanced", 60, religion: "RELIGION_POLYTHEISM", beliefs: [ "BELIEF_Y" ])
    event("Rome", "reformation_added", 90, religion: "RELIGION_POLYTHEISM", belief: "BELIEF_Z")

    religion = timeline.religion("Rome")

    assert_equal(
      [
        { turn: 10, type: :pantheon_founded, city: "Roma", belief: "BELIEF_GODDESS_OF_HARVEST" },
        { turn: 30, type: :religion_founded, holy_city: "Roma", religion: "RELIGION_POLYTHEISM", beliefs: [ "BELIEF_X" ] },
        { turn: 60, type: :religion_enhanced, religion: "RELIGION_POLYTHEISM", beliefs: [ "BELIEF_Y" ] },
        { turn: 90, type: :reformation_added, religion: "RELIGION_POLYTHEISM", belief: "BELIEF_Z" }
      ],
      religion
    )
  end

  test "great_people, eras and golden_ages list a civ's own events" do
    event("Rome", "great_person_expended", 40, great_person: "UNIT_GREAT_SCIENTIST")
    event("Greece", "great_person_expended", 41, great_person: "UNIT_GREAT_WRITER")
    event(nil, "era_entered", 50, team: 1, civs: %w[Rome Egypt], era: "ERA_CLASSICAL")
    event("Rome", "golden_age_started", 55)

    assert_equal [ { turn: 40, great_person: "UNIT_GREAT_SCIENTIST" } ], timeline.great_people("Rome")
    assert_equal [ { turn: 50, era: "ERA_CLASSICAL" } ], timeline.eras("Rome")
    assert_equal [ { turn: 55 } ], timeline.golden_ages("Rome")
  end

  test "wonders lists world and national wonders built by a civ, ignoring regular buildings" do
    event("Rome", "building_constructed", 33, building: "BUILDING_PYRAMID", city: "Roma", wonder: "world")
    event("Rome", "building_constructed", 70, building: "BUILDING_WRITERS_GUILD", city: "Roma", wonder: "national")
    event("Rome", "building_constructed", 12, building: "BUILDING_GRANARY", city: "Roma")
    event("Greece", "building_constructed", 40, building: "BUILDING_GREAT_LIBRARY", city: "Athens", wonder: "world")

    assert_equal(
      [
        { turn: 33, building: "BUILDING_PYRAMID", city: "Roma", class: :world },
        { turn: 70, building: "BUILDING_WRITERS_GUILD", city: "Roma", class: :national }
      ],
      timeline.wonders("Rome")
    )
  end

  test "buildings lists every building a civ finished, in turn order, wonders included" do
    event("Rome", "building_constructed", 33, building: "BUILDING_PYRAMID", city: "Roma", wonder: "world")
    event("Rome", "building_constructed", 12, building: "BUILDING_GRANARY", city: "Roma")
    event("Rome", "building_constructed", 25, building: "BUILDING_WORKSHOP", city: "Ostia")
    event("Greece", "building_constructed", 20, building: "BUILDING_UNIVERSITY", city: "Athens")

    assert_equal(
      [
        { turn: 12, building: "BUILDING_GRANARY", city: "Roma", class: nil },
        { turn: 25, building: "BUILDING_WORKSHOP", city: "Ostia", class: nil },
        { turn: 33, building: "BUILDING_PYRAMID", city: "Roma", class: :world }
      ],
      timeline.buildings("Rome")
    )
  end

  test "city_states tracks friendship, alliance and ally changes involving a civ" do
    event("Rome", "city_state_friendship_changed", 12, city_state: "Cahokia", friends: true, old_friendship: 20, new_friendship: 35)
    event("Rome", "city_state_alliance_changed", 20, city_state: "Cahokia", allied: true, old_friendship: 60, new_friendship: 94)
    event(nil, "city_state_ally_changed", 20, city_state: "Cahokia", old_ally: nil, new_ally: "Rome")
    event(nil, "city_state_ally_changed", 40, city_state: "Cahokia", old_ally: "Rome", new_ally: "Greece")

    city_states = timeline.city_states("Rome")

    assert_equal(
      [
        { turn: 12, type: :friendship_changed, city_state: "Cahokia", friends: true, old_friendship: 20, new_friendship: 35 },
        { turn: 20, type: :alliance_changed, city_state: "Cahokia", allied: true, old_friendship: 60, new_friendship: 94 },
        { turn: 20, type: :ally_gained, city_state: "Cahokia" },
        { turn: 40, type: :ally_lost, city_state: "Cahokia" }
      ],
      city_states
    )
  end

  test "wars lists periods with role, opponents and an ongoing war when no peace followed" do
    event(nil, "war_declared", 30, attacker_team: 1, attacker_civs: %w[Rome], defender_team: 2, defender_civs: %w[Greece])
    event(nil, "peace_made", 45, team_a: 1, team_a_civs: %w[Rome], team_b: 2, team_b_civs: %w[Greece])
    event(nil, "war_declared", 100, attacker_team: 3, attacker_civs: %w[Carthage], defender_team: 1, defender_civs: %w[Rome])

    wars = timeline.wars("Rome")

    assert_equal 2, wars.size

    first_war = wars.first
    assert_equal 30, first_war[:turn_declared]
    assert_equal 45, first_war[:turn_peace]
    assert_equal :attacker, first_war[:role]
    assert_equal %w[Greece], first_war[:opponents]

    second_war = wars.second
    assert_equal 100, second_war[:turn_declared]
    assert_nil second_war[:turn_peace]
    assert_equal :defender, second_war[:role]
    assert_equal %w[Carthage], second_war[:opponents]
  end

  test "wars computes the balance of units and cities against the opponent within the war window" do
    event(nil, "war_declared", 10, attacker_team: 1, attacker_civs: %w[Rome], defender_team: 2, defender_civs: %w[Greece])
    event(nil, "peace_made", 30, team_a: 1, team_a_civs: %w[Rome], team_b: 2, team_b_civs: %w[Greece])

    # Rome kills a Greek unit and captures a Greek city during the war.
    event(nil, "unit_killed", 12, killer: "Rome", victim: "Greece", unit: "UNIT_WARRIOR")
    event(nil, "city_captured", 15, city: "Athens", old_owner: "Greece", new_owner: "Rome")
    # Rome loses a unit to Greece too.
    event(nil, "unit_killed", 20, killer: "Greece", victim: "Rome", unit: "UNIT_ARCHER")
    # Unrelated combat against a third civ outside this war must not count.
    event(nil, "unit_killed", 22, killer: "Rome", victim: "Carthage", unit: "UNIT_SPEARMAN")
    # Outside the war window (after peace) must not count.
    event(nil, "unit_killed", 35, killer: "Rome", victim: "Greece", unit: "UNIT_CATAPULT")

    war = timeline.wars("Rome").first

    assert_equal 1, war[:units_killed]
    assert_equal 1, war[:units_lost]
    assert_equal 1, war[:cities_captured]
    assert_equal 0, war[:cities_lost]
  end

  test "wars carries the diplomatic ties still standing with the opponent when war was declared" do
    event("Rome", "embassy_established", 86, other_civ: "Greece")
    event("Greece", "embassy_established", 86, other_civ: "Rome")
    event(nil, "war_declared", 144, attacker_team: 1, attacker_civs: %w[Rome], defender_team: 2, defender_civs: %w[Greece])
    event("Rome", "embassy_ended", 145, other_civ: "Greece")
    event("Greece", "embassy_ended", 145, other_civ: "Rome")

    war = timeline.wars("Rome").first

    assert_equal(
      [ { type: "embassy", from_turn: 86, to_turn: 145, with: "Greece" } ],
      war[:ties_at_declaration]
    )
  end

  test "wars carries no ties at declaration when none were standing" do
    event(nil, "war_declared", 30, attacker_team: 1, attacker_civs: %w[Rome], defender_team: 2, defender_civs: %w[Greece])

    assert_equal [], timeline.wars("Rome").first[:ties_at_declaration]
  end

  test "wars excludes a tie that had already ended before the war was declared" do
    event("Rome", "embassy_established", 10, other_civ: "Greece")
    event("Greece", "embassy_established", 10, other_civ: "Rome")
    event("Rome", "embassy_ended", 20, other_civ: "Greece")
    event("Greece", "embassy_ended", 20, other_civ: "Rome")
    event(nil, "war_declared", 30, attacker_team: 1, attacker_civs: %w[Rome], defender_team: 2, defender_civs: %w[Greece])

    assert_equal [], timeline.wars("Rome").first[:ties_at_declaration]
  end

  test "irrelevance returns the vote that removed the civ from contention" do
    event(nil, "mp_proposal_result", 120, type: "irrelevance", status: "passed",
      owner: "India", subject: "Rome", yes_votes: 4, no_votes: 1)

    assert_equal(
      { turn: 120, proposer: "India", yes_votes: 4, no_votes: 1 },
      timeline.irrelevance("Rome")
    )
  end

  test "irrelevance is nil for a civ that was never voted irrelevant" do
    event(nil, "mp_proposal_result", 120, type: "irrelevance", status: "passed",
      owner: "India", subject: "Rome", yes_votes: 4, no_votes: 1)

    assert_nil timeline.irrelevance("India")
  end

  private

  def timeline
    @timeline ||= PlayerTimeline.new(@game)
  end

  def city_snapshot(civ, turn, city, population:, buildings: 0, yield_science: 0, resistance_turns: 0,
                    occupied: false, puppet: false, razing: false)
    event(civ, "city_snapshot", turn, city: city, population: population, buildings: buildings,
          yield_science: yield_science, yield_production: 0, yield_gold: 0, yield_culture: 0,
          yield_faith: 0, resistance_turns: resistance_turns, occupied: occupied, puppet: puppet,
          razing: razing)
  end

  def snapshot_with_influence(civ, turn, opponent, points:, trend:, level: "INFLUENCE_LEVEL_UNKNOWN")
    event(civ, "snapshot", turn,
          influence: [ { "civ" => opponent, "points" => points, "level" => level, "trend" => trend } ])
  end

  def event(civ, event_type, turn, extra = {})
    @seq += 1
    payload = extra.stringify_keys.merge("event" => event_type, "turn" => turn)
    payload["civ"] = civ if civ
    @game.game_events.create!(
      seq: @seq,
      session_index: 0,
      turn: turn,
      event_type: event_type,
      civ: civ,
      payload: payload
    )
  end
end
