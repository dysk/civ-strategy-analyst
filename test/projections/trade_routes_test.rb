require "test_helper"

class TradeRoutesTest < ActiveSupport::TestCase
  setup do
    @game = Game.create!(name: "Trade Routes Test Game")
    @seq = 0
  end

  test "applicable? is false when the log has no trade route events" do
    assert_not TradeRoutes.new(@game).applicable?
  end

  test "applicable? is true once a route is established" do
    established("India", 10, from_city: "Delhi", to_city: "Mumbai", to_civ: "India", type: "food", turns_left: 15)

    assert TradeRoutes.new(@game).applicable?
  end

  # -- by_destination --

  test "by_destination splits a civ's own routes into food and production" do
    established("India", 10, from_city: "Delhi", to_city: "Mumbai", to_civ: "India", type: "food", turns_left: 15)
    established("India", 12, from_city: "Delhi", to_city: "Agra", to_civ: "India", type: "production", turns_left: 15)
    established("India", 14, from_city: "Delhi", to_city: "Agra", to_civ: "India", type: "production", turns_left: 15)

    assert_equal({ food: 1, production: 2 }, TradeRoutes.new(@game).by_destination("India")[:own])
  end

  test "by_destination counts routes sent to a city-state separately from majors" do
    session_started(city_states: [ { civ: "Tashkent" } ])
    established("India", 10, from_city: "Delhi", to_city: "Tashkent", to_civ: "Tashkent",
                 type: "international", turns_left: 15, from_gold: 3)
    established("India", 20, from_city: "Delhi", to_city: "London", to_civ: "England",
                 type: "international", turns_left: 15, from_gold: 3)

    result = TradeRoutes.new(@game).by_destination("India")
    assert_equal 1, result[:city_state]
    assert_equal 1, result[:major]
  end

  test "by_destination ignores another civ's routes" do
    session_started(city_states: [ { civ: "Tashkent" } ])
    established("Netherlands", 10, from_city: "Amsterdam", to_city: "Tashkent", to_civ: "Tashkent",
                 type: "international", turns_left: 15, from_gold: 3)

    result = TradeRoutes.new(@game).by_destination("India")
    assert_equal({}, result[:own])
    assert_equal 0, result[:city_state]
    assert_equal 0, result[:major]
  end

  # -- one_sided --

  test "one_sided reports a yield one side of a major-to-major route received and the other did not" do
    established("India", 156, from_city: "Delhi", to_city: "Amsterdam", to_civ: "Netherlands",
                 type: "international", turns_left: 39, from_gold: 18.96, to_gold: 1.25, to_science: 13)

    science = TradeRoutes.new(@game).one_sided.find { |r| r[:yield] == "science" }

    assert_equal(
      { civ: "India", other_civ: "Netherlands", from_city: "Delhi", to_city: "Amsterdam",
        turn: 156, yield: "science", civ_value: 0, other_civ_value: 13 },
      science
    )
  end

  test "one_sided says nothing about a yield both sides of a route carry" do
    established("England", 51, from_city: "York", to_city: "Vijayanagara", to_civ: "India",
                 type: "international", turns_left: 17, from_gold: 2.56, from_science: 2, to_gold: 1.25, to_science: 2)

    assert_empty TradeRoutes.new(@game).one_sided.select { |r| r[:yield] == "science" }
  end

  test "one_sided ignores a civ's own food and production routes" do
    established("India", 10, from_city: "Delhi", to_city: "Mumbai", to_civ: "India", type: "food", turns_left: 15)

    assert_empty TradeRoutes.new(@game).one_sided
  end

  test "one_sided ignores a route sent to a city-state" do
    session_started(city_states: [ { civ: "Tashkent" } ])
    established("India", 10, from_city: "Delhi", to_city: "Tashkent", to_civ: "Tashkent",
                 type: "international", turns_left: 15, from_gold: 3)

    assert_empty TradeRoutes.new(@game).one_sided
  end

  # -- concurrency --

  test "concurrency falls back to turn + turns_left when no end was ever recorded" do
    established("India", 100, from_city: "Delhi", to_city: "Mumbai", to_civ: "India", type: "food", turns_left: 10)

    assert_equal(
      [ { turn: 100, count: 1, flagged: true }, { turn: 110, count: 0, flagged: false } ],
      TradeRoutes.new(@game).concurrency("India")
    )
  end

  test "concurrency uses the matched end when it falls inside the stated expiry" do
    established("India", 50, from_city: "Delhi", to_city: "Mumbai", to_civ: "India", type: "food", turns_left: 30)
    ended("India", 60, from_city: "Delhi", to_city: "Mumbai", to_civ: "India")

    assert_equal(
      [ { turn: 50, count: 1, flagged: false }, { turn: 60, count: 0, flagged: false } ],
      TradeRoutes.new(@game).concurrency("India")
    )
  end

  test "concurrency discards a matched end past the stated expiry and flags the point" do
    established("India", 47, from_city: "Mumbai", to_city: "Delhi", to_civ: "India", type: "food", turns_left: 17)
    ended("India", 183, from_city: "Mumbai", to_city: "Delhi", to_civ: "India")

    assert_equal(
      [ { turn: 47, count: 1, flagged: true }, { turn: 64, count: 0, flagged: false } ],
      TradeRoutes.new(@game).concurrency("India")
    )
  end

  test "concurrency counts overlapping routes for the same civ" do
    established("India", 10, from_city: "Delhi", to_city: "Mumbai", to_civ: "India", type: "food", turns_left: 100)
    established("India", 20, from_city: "Delhi", to_city: "Agra", to_civ: "India", type: "production", turns_left: 100)

    assert_equal(
      [ 1, 2, 1, 0 ],
      TradeRoutes.new(@game).concurrency("India").map { |p| p[:count] }
    )
  end

  test "concurrency ignores another civ's routes" do
    established("Netherlands", 10, from_city: "Amsterdam", to_city: "Tashkent", to_civ: "Tashkent",
                 type: "international", turns_left: 15, from_gold: 3)

    assert_empty TradeRoutes.new(@game).concurrency("India")
  end

  private

  def session_started(city_states:)
    payload = { "event" => "session_started", "turn" => 0, "players" => [],
                "city_states" => city_states.map(&:stringify_keys) }
    event("session_started", nil, 0, payload)
  end

  def established(civ, turn, from_city:, to_city:, to_civ:, type:, turns_left:, **yields)
    payload = { "from_city" => from_city, "to_city" => to_city, "to_civ" => to_civ,
                "type" => type, "turns_left" => turns_left, "domain" => "land" }
    payload.merge!(yields.stringify_keys)
    event("trade_route_established", civ, turn, payload)
  end

  def ended(civ, turn, from_city:, to_city:, to_civ:)
    event("trade_route_ended", civ, turn, "from_city" => from_city, "to_city" => to_city, "to_civ" => to_civ)
  end

  def event(type, civ, turn, extra)
    payload = extra.merge("event" => type, "turn" => turn)
    payload["civ"] = civ if civ
    @game.game_events.create!(seq: @seq += 1, session_index: 0, turn: turn, event_type: type, civ: civ, payload: payload)
  end
end
