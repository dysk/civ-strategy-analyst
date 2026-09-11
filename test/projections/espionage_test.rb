require "test_helper"

class EspionageTest < ActiveSupport::TestCase
  setup do
    @game = Game.create!(name: "Espionage Test Game")
    @seq = 0
  end

  test "a run of sightings of one spy in one city is one tenure" do
    moved("India", 100, spy: "INDIA_7", agent: 7, city: "Kyoto", city_civ: "Japan", state: "travelling")
    surveillance("India", 104, spy: "INDIA_7", agent: 7, city: "Kyoto", city_civ: "Japan")
    mission("India", 110, spy: "INDIA_7", agent: 7, city: "Kyoto", city_civ: "Japan", state: "gathering_intel")

    assert_equal(
      [ { civ: "India", spy: "INDIA_7", agent: 7, city: "Kyoto", city_civ: "Japan",
          from_turn: 100, to_turn: 110, visible_from_turn: 104, visible_from_turn_bounded: false,
          states: %w[travelling gathering_intel], ended_by: :log_end } ],
      Espionage.new(@game).tenures("India")
    )
  end

  test "a sighting in another city ends the tenure and opens the next" do
    moved("India", 100, spy: "INDIA_7", city: "Kyoto", city_civ: "Japan", state: "travelling")
    mission("India", 110, spy: "INDIA_7", city: "Kyoto", city_civ: "Japan", state: "gathering_intel")
    moved("India", 120, spy: "INDIA_7", city: "Osaka", city_civ: "Japan", state: "travelling")

    assert_equal [ [ "Kyoto", 100, 110, :moved ], [ "Osaka", 120, 120, :log_end ] ],
      Espionage.new(@game).tenures("India").map { |t| t.values_at(:city, :from_turn, :to_turn, :ended_by) }
  end

  test "a killed spy's tenure ends where it died" do
    moved("India", 100, spy: "INDIA_7", agent: 7, city: "Kyoto", city_civ: "Japan", state: "travelling")
    killed("India", 112, spy: "INDIA_7", agent: 7, city: "Kyoto", city_civ: "Japan")

    assert_equal [ [ 112, :killed ] ],
      Espionage.new(@game).tenures("India").map { |t| t.values_at(:to_turn, :ended_by) }
  end

  test "a kill ends the run even when the same agent returns to the same city" do
    moved("India", 100, spy: "INDIA_7", agent: 7, city: "Kyoto", city_civ: "Japan", state: "travelling")
    killed("India", 112, spy: "INDIA_7", agent: 7, city: "Kyoto", city_civ: "Japan")
    moved("India", 120, spy: "INDIA_9", agent: 7, city: "Kyoto", city_civ: "Japan", state: "travelling")

    assert_equal [ [ 100, 112, :killed ], [ 120, 120, :log_end ] ],
      Espionage.new(@game).tenures("India").map { |t| t.values_at(:from_turn, :to_turn, :ended_by) }
  end

  test "a location-less event does not break a run" do
    moved("India", 100, spy: "INDIA_7", agent: 7, city: "Kyoto", city_civ: "Japan", state: "travelling")
    promoted("India", 105, spy: "INDIA_7", agent: 7)
    mission("India", 110, spy: "INDIA_7", agent: 7, city: "Kyoto", city_civ: "Japan", state: "gathering_intel")

    assert_equal 1, Espionage.new(@game).tenures("India").size
  end

  test "a spy re-announced after a reload does not open a second tenure" do
    created("India", 132, spy: "INDIA_7", agent: 7, city: "Delhi", city_civ: "India")
    surveillance("India", 136, spy: "INDIA_7", agent: 7, city: "Delhi", city_civ: "India")
    created("India", 150, spy: "INDIA_7", agent: 7, city: "Delhi", city_civ: "India")

    assert_equal [ [ 132, 150 ] ],
      Espionage.new(@game).tenures("India").map { |t| t.values_at(:from_turn, :to_turn) }
  end

  test "sightings are keyed on the agent, so a recycled spy name is two tenures" do
    moved("India", 100, spy: "INDIA_3", agent: 1, city: "Kyoto", city_civ: "Japan", state: "travelling")
    moved("India", 102, spy: "INDIA_3", agent: 5, city: "Osaka", city_civ: "Japan", state: "travelling")
    mission("India", 104, spy: "INDIA_3", agent: 1, city: "Kyoto", city_civ: "Japan", state: "gathering_intel")

    assert_equal 2, Espionage.new(@game).tenures("India").size
  end

  test "vision opens on the logged surveillance turn" do
    moved("India", 100, spy: "INDIA_7", agent: 7, city: "Kyoto", city_civ: "Japan", state: "travelling")
    surveillance("India", 106, spy: "INDIA_7", agent: 7, city: "Kyoto", city_civ: "Japan")

    assert_equal [ [ 106, false ] ],
      Espionage.new(@game).tenures("India").map { |t| t.values_at(:visible_from_turn, :visible_from_turn_bounded) }
  end

  test "without the event vision is computed as the posting plus four" do
    moved("India", 100, spy: "INDIA_7", agent: 7, city: "Kyoto", city_civ: "Japan", state: "travelling")
    mission("India", 110, spy: "INDIA_7", agent: 7, city: "Kyoto", city_civ: "Japan", state: "gathering_intel")

    assert_equal [ [ 104, false ] ],
      Espionage.new(@game).tenures("India").map { |t| t.values_at(:visible_from_turn, :visible_from_turn_bounded) }
  end

  test "a tourism lead over the target cuts the computed wait to two turns" do
    influence("India", 99, over: "Japan", level: "INFLUENCE_LEVEL_FAMILIAR")
    moved("India", 100, spy: "INDIA_7", agent: 7, city: "Kyoto", city_civ: "Japan", state: "travelling")
    mission("India", 110, spy: "INDIA_7", agent: 7, city: "Kyoto", city_civ: "Japan", state: "gathering_intel")

    assert_equal [ 102 ], Espionage.new(@game).tenures("India").map { |t| t[:visible_from_turn] }
  end

  test "an influence level below familiar leaves the wait at four turns" do
    influence("India", 99, over: "Japan", level: "INFLUENCE_LEVEL_EXOTIC")
    moved("India", 100, spy: "INDIA_7", agent: 7, city: "Kyoto", city_civ: "Japan", state: "travelling")

    assert_equal [ 104 ], Espionage.new(@game).tenures("India").map { |t| t[:visible_from_turn] }
  end

  test "a counter intelligence posting takes effect the turn after it is ordered" do
    moved("India", 152, spy: "INDIA_7", agent: 7, city: "Delhi", city_civ: "India", state: "counter_intel")

    assert_equal [ [ 153, false ] ],
      Espionage.new(@game).tenures("India").map { |t| t.values_at(:visible_from_turn, :visible_from_turn_bounded) }
  end

  test "a garrison announced a turn after the order is dated from the order" do
    moved("India", 170, spy: "INDIA_7", agent: 7, city: "Delhi", city_civ: "India", state: "travelling")
    moved("India", 171, spy: "INDIA_7", agent: 7, city: "Delhi", city_civ: "India", state: "counter_intel")

    assert_equal [ 171 ], Espionage.new(@game).tenures("India").map { |t| t[:visible_from_turn] }
  end

  test "a tenure with no posting is dated from its first proof of presence and marked bounded" do
    mission("India", 110, spy: "INDIA_7", agent: 7, city: "Kyoto", city_civ: "Japan", state: "gathering_intel")
    mission("India", 118, spy: "INDIA_7", agent: 7, city: "Kyoto", city_civ: "Japan", state: "gathering_intel")

    assert_equal [ [ 110, true ] ],
      Espionage.new(@game).tenures("India").map { |t| t.values_at(:visible_from_turn, :visible_from_turn_bounded) }
  end

  test "tenures are listed in posting order across civs" do
    moved("Japan", 90, spy: "JAPAN_1", agent: 1, city: "Delhi", city_civ: "India", state: "travelling")
    moved("India", 100, spy: "INDIA_7", agent: 7, city: "Kyoto", city_civ: "Japan", state: "travelling")

    assert_equal %w[Japan India], Espionage.new(@game).tenures.map { |t| t[:civ] }
  end

  test "tenures asked for one civ leaves the other civs out" do
    moved("Japan", 90, spy: "JAPAN_1", agent: 1, city: "Delhi", city_civ: "India", state: "travelling")
    moved("India", 100, spy: "INDIA_7", agent: 7, city: "Kyoto", city_civ: "Japan", state: "travelling")

    assert_equal %w[India], Espionage.new(@game).tenures("India").map { |t| t[:civ] }
  end

  test "applicable? is false when the log carries no spy record" do
    influence("India", 99, over: "Japan", level: "INFLUENCE_LEVEL_EXOTIC")

    assert_not Espionage.new(@game).applicable?
  end

  test "applicable? is true once any spy record is present" do
    created("India", 132, spy: "INDIA_7", agent: 7, city: "Delhi", city_civ: "India")

    assert Espionage.new(@game).applicable?
  end

  private

  def moved(civ, turn, **fields) = spy_event("spy_moved", civ, turn, **fields)
  def created(civ, turn, **fields) = spy_event("spy_created", civ, turn, **fields)
  def killed(civ, turn, **fields) = spy_event("spy_killed", civ, turn, **fields)
  def promoted(civ, turn, **fields) = spy_event("spy_promoted", civ, turn, **fields)
  def mission(civ, turn, **fields) = spy_event("spy_mission_completed", civ, turn, **fields)

  def surveillance(civ, turn, **fields)
    spy_event("spy_surveillance_established", civ, turn, **fields)
  end

  def spy_event(type, civ, turn, spy:, agent: nil, city: nil, city_civ: nil, state: nil)
    payload = { "event" => type, "turn" => turn, "civ" => civ, "spy" => spy }
    payload["agent"] = agent if agent
    payload.merge!("city" => city, "city_civ" => city_civ) if city
    payload["state"] = state if state
    event(type, civ, turn, payload)
  end

  def influence(civ, turn, over:, level:)
    payload = { "event" => "snapshot", "turn" => turn, "civ" => civ,
                "influence" => [ { "civ" => over, "points" => 100, "level" => level, "trend" => "up" } ] }
    event("snapshot", civ, turn, payload)
  end

  def event(type, civ, turn, payload)
    @game.game_events.create!(
      seq: @seq += 1, session_index: 0, turn: turn, event_type: type, civ: civ, payload: payload
    )
  end
end
