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
        { turn: 10, city: "Athens", action: :captured, from: "Greece", conquest: nil },
        { turn: 15, city: "Roma", action: :lost, to: "Carthage", conquest: nil }
      ],
      cities
    )
  end

  test "cities records a city handed over without a fight as no conquest" do
    event(nil, "city_captured", 10, city: "Athens", old_owner: "Greece", new_owner: "Rome", conquest: false)

    assert_equal(
      [ { turn: 10, city: "Athens", action: :captured, from: "Greece", conquest: false } ],
      timeline.cities("Rome")
    )
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

  private

  def timeline
    @timeline ||= PlayerTimeline.new(@game)
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
