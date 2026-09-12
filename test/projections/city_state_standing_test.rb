require "test_helper"

class CityStateStandingTest < ActiveSupport::TestCase
  setup do
    @game = Game.create!(name: "City-State Standing Test Game")
    @seq = 0
  end

  test "applicable? is false with no city_state_snapshot in the log" do
    assert_not CityStateStanding.new(@game).applicable?
  end

  test "applicable? is true once a city_state_snapshot exists" do
    city_state("Ljubljana", 1)

    assert CityStateStanding.new(@game).applicable?
  end

  test "series returns turn/influence/level/per_turn/protected for a city-state and civ" do
    city_state("Ljubljana", 48, relations: [
      { civ: "India", influence: 5, per_turn: 1.25 },
      { civ: "Netherlands", influence: 5, per_turn: 1.25, protected: true }
    ])
    city_state("Ljubljana", 99, ally: "India", relations: [
      { civ: "India", influence: 60, level: "ally", per_turn: -1.25 }
    ])

    assert_equal(
      [
        { turn: 48, influence: 5, level: nil, per_turn: 1.25, protected: false },
        { turn: 99, influence: 60, level: "ally", per_turn: -1.25, protected: false }
      ],
      CityStateStanding.new(@game).series("Ljubljana", "India")
    )
  end

  test "series keeps one point per turn when a turn was snapshotted twice, the later payload winning" do
    city_state("Ljubljana", 99, relations: [ { civ: "India", influence: 55, per_turn: -1.25 } ])
    city_state("Ljubljana", 99, relations: [ { civ: "India", influence: 60, per_turn: -1.25 } ])

    assert_equal [ 60 ], CityStateStanding.new(@game).series("Ljubljana", "India").map { |point| point[:influence] }
  end

  test "series is empty for a civ the city-state has no relation with" do
    city_state("Ljubljana", 48, relations: [ { civ: "India", influence: 5, per_turn: 1.25 } ])

    assert_equal [], CityStateStanding.new(@game).series("Ljubljana", "Netherlands")
  end

  test "alliances reports a held span from the gaining change to the losing one" do
    ally_changed("Ljubljana", 98, new_ally: "India")
    ally_changed("Ljubljana", 131, old_ally: "India")

    assert_equal(
      [ { city_state: "Ljubljana", from_turn: 98, until_turn: 131, origin: :event } ],
      CityStateStanding.new(@game).alliances("India")
    )
  end

  test "alliances leaves until_turn nil for an alliance still held at the end of the log" do
    ally_changed("Ljubljana", 98, new_ally: "India")

    span = CityStateStanding.new(@game).alliances("India").first
    assert_equal 98, span[:from_turn]
    assert_nil span[:until_turn]
  end

  test "alliances only reports spans for the requested civ" do
    ally_changed("Ljubljana", 98, new_ally: "India")
    ally_changed("Zurich", 40, new_ally: "Netherlands")

    assert_equal [ "Ljubljana" ], CityStateStanding.new(@game).alliances("India").map { |span| span[:city_state] }
  end

  test "alliances covers every city-state a civ has held, across separate ally_changed histories" do
    ally_changed("Ljubljana", 98, new_ally: "India")
    ally_changed("Ljubljana", 131, old_ally: "India")
    ally_changed("Tashkent", 40, new_ally: "India")

    spans = CityStateStanding.new(@game).alliances("India").sort_by { |span| span[:from_turn] }
    assert_equal [ "Tashkent", "Ljubljana" ], spans.map { |span| span[:city_state] }
  end

  test "alliances backdates a span already open at the first snapshot with no dated start" do
    city_state("Ljubljana", 1, ally: "India", relations: [ { civ: "India", influence: 20, per_turn: 1.25 } ])
    ally_changed("Ljubljana", 60, old_ally: "India")

    assert_equal(
      [ { city_state: "Ljubljana", from_turn: 1, until_turn: 60, origin: :observed } ],
      CityStateStanding.new(@game).alliances("India")
    )
  end

  test "traits reports trait, personality and unique_unit per city-state from session_started" do
    session_started(city_states: [
      { civ: "Ljubljana", personality: "MINOR_CIV_PERSONALITY_THEOCRATIC", trait: "MINOR_TRAIT_CULTURED" },
      { civ: "Harappa", personality: "MINOR_CIV_PERSONALITY_THEOCRATIC", trait: "MINOR_TRAIT_MILITARISTIC",
        unique_unit: "UNIT_BOERS_GREAT_WAR_INFANTRY" }
    ])

    assert_equal(
      [
        { city_state: "Ljubljana", trait: "MINOR_TRAIT_CULTURED", personality: "MINOR_CIV_PERSONALITY_THEOCRATIC", unique_unit: nil },
        { city_state: "Harappa", trait: "MINOR_TRAIT_MILITARISTIC", personality: "MINOR_CIV_PERSONALITY_THEOCRATIC", unique_unit: "UNIT_BOERS_GREAT_WAR_INFANTRY" }
      ],
      CityStateStanding.new(@game).traits
    )
  end

  test "attribution splits the observed change into decay, rig-explained gain and a residual" do
    city_state("Ljubljana", 10, relations: [ { civ: "India", influence: 20, per_turn: 2.0 } ])
    city_state("Ljubljana", 60, relations: [ { civ: "India", influence: 100, per_turn: -1.0 } ])
    mission("India", 30, spy: "INDIA_1", city: "Ljubljana", city_civ: "Ljubljana", state: "rigging_election")

    assert_equal(
      { gain: 80, decay: 100.0, rigs: 1, explained: 45, unexplained: -65.0, cs_routes: 0, merchant_confederacy: false },
      CityStateStanding.new(@game).attribution("Ljubljana", "India")
    )
  end

  test "attribution counts only rigging_election missions completed against this city-state by this civ" do
    mission("India", 30, spy: "INDIA_1", city: "Ljubljana", city_civ: "Ljubljana", state: "rigging_election")
    mission("India", 40, spy: "INDIA_1", city: "Ljubljana", city_civ: "Ljubljana", state: "gathering_intel")
    mission("India", 50, spy: "INDIA_2", city: "Zurich", city_civ: "Zurich", state: "rigging_election")
    mission("England", 60, spy: "ENGLAND_1", city: "Ljubljana", city_civ: "Ljubljana", state: "rigging_election")

    assert_equal 1, CityStateStanding.new(@game).attribution("Ljubljana", "India")[:rigs]
  end

  test "attribution counts trade routes established from this civ to this city-state" do
    trade_route("India", 47, to_civ: "Ljubljana")
    trade_route("India", 59, to_civ: "Ljubljana")
    trade_route("India", 84, to_civ: "Zurich")
    trade_route("England", 90, to_civ: "Ljubljana")

    assert_equal 2, CityStateStanding.new(@game).attribution("Ljubljana", "India")[:cs_routes]
  end

  test "attribution reports merchant_confederacy true only for the civ that adopted the policy" do
    policy_adopted("India", 81, policy: "POLICY_MERCHANT_CONFEDERACY")

    assert CityStateStanding.new(@game).attribution("Ljubljana", "India")[:merchant_confederacy]
    assert_not CityStateStanding.new(@game).attribution("Ljubljana", "England")[:merchant_confederacy]
  end

  # A relation the log carries with no per_turn at all - seen for real in
  # india-diplo.jsonl - must not crash decay_across; the unmeasured stretch
  # falls into `unexplained` like every other unlogged cause, rather than
  # being treated as a NoMethodError.
  test "attribution treats a snapshot with no per_turn as zero decay for that stretch" do
    city_state("Ljubljana", 10, relations: [ { civ: "India", influence: 20, per_turn: 2.0 } ])
    city_state("Ljubljana", 30, relations: [ { civ: "India", influence: 25 } ])
    city_state("Ljubljana", 50, relations: [ { civ: "India", influence: 40, per_turn: -1.0 } ])

    result = CityStateStanding.new(@game).attribution("Ljubljana", "India")

    assert_equal 20, result[:gain]
    assert_equal 40.0, result[:decay]
  end

  # Also real in india-diplo.jsonl: a relation logged with no influence value
  # at all (still carrying per_turn and protected). Gain falls back to the
  # nearest snapshots that do carry influence, rather than crashing on nil.
  test "attribution falls back to the nearest known influence when a boundary snapshot omits it" do
    city_state("Ljubljana", 10, relations: [ { civ: "India", per_turn: 1.25, protected: true } ])
    city_state("Ljubljana", 20, relations: [ { civ: "India", influence: 20, per_turn: 2.0 } ])
    city_state("Ljubljana", 60, relations: [ { civ: "India", influence: 100, per_turn: -1.0 } ])

    result = CityStateStanding.new(@game).attribution("Ljubljana", "India")

    assert_equal 80, result[:gain]
    assert_equal 92.5, result[:decay]
  end

  test "attribution reports zero gain and decay when the pair has fewer than two snapshot points" do
    city_state("Ljubljana", 10, relations: [ { civ: "India", influence: 20, per_turn: 2.0 } ])

    result = CityStateStanding.new(@game).attribution("Ljubljana", "India")
    assert_equal 0, result[:gain]
    assert_equal 0, result[:decay]
  end

  private

  def city_state(name, turn, ally: nil, relations: [])
    payload = { "event" => "city_state_snapshot", "turn" => turn, "city_state" => name,
                "relations" => relations.map { |r| r.stringify_keys } }
    payload["ally"] = ally if ally
    event("city_state_snapshot", nil, turn, payload)
  end

  def ally_changed(city_state, turn, new_ally: nil, old_ally: nil)
    payload = { "event" => "city_state_ally_changed", "turn" => turn, "city_state" => city_state }
    payload["new_ally"] = new_ally if new_ally
    payload["old_ally"] = old_ally if old_ally
    event("city_state_ally_changed", nil, turn, payload)
  end

  def session_started(city_states:)
    payload = { "event" => "session_started", "turn" => 0, "players" => [], "city_states" => city_states.map(&:stringify_keys) }
    event("session_started", nil, 0, payload)
  end

  def mission(civ, turn, spy:, city:, city_civ:, state:)
    payload = { "event" => "spy_mission_completed", "turn" => turn, "civ" => civ, "spy" => spy,
                "city" => city, "city_civ" => city_civ, "state" => state }
    event("spy_mission_completed", civ, turn, payload)
  end

  def trade_route(civ, turn, to_civ:)
    payload = { "event" => "trade_route_established", "turn" => turn, "civ" => civ, "to_civ" => to_civ }
    event("trade_route_established", civ, turn, payload)
  end

  def policy_adopted(civ, turn, policy:)
    payload = { "event" => "policy_adopted", "turn" => turn, "civ" => civ, "policy" => policy }
    event("policy_adopted", civ, turn, payload)
  end

  def event(type, civ, turn, payload)
    @game.game_events.create!(seq: @seq += 1, session_index: 0, turn: turn, event_type: type, civ: civ, payload: payload)
  end
end
