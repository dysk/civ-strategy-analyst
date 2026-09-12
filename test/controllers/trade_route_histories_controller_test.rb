require "test_helper"

class TradeRouteHistoriesControllerTest < ActionDispatch::IntegrationTest
  setup do
    @game = Game.create!(name: "Trade Route History Game")
    @game.players.create!(civ: "India")
  end

  test "lists live route counts at every turn a route starts or stops" do
    established("India", 10, from_city: "Delhi", to_city: "Mumbai", to_civ: "India", turns_left: 20)
    established("India", 15, from_city: "Delhi", to_city: "Agra", to_civ: "India", turns_left: 20)

    get game_trade_routes_url(@game)

    assert_response :success
    # Boundaries fall at both routes' start and estimated end turns: 10, 15, 30, 35.
    assert_select "table.trade-route-concurrency tbody tr", 4
    assert_select "table.trade-route-concurrency tbody tr td", "2"
  end

  test "names the civilization each table belongs to" do
    established("India", 10, from_city: "Delhi", to_city: "Mumbai", to_civ: "India", turns_left: 20)

    get game_trade_routes_url(@game)

    assert_select "h2", "India"
  end

  test "flags a point whose live count fell back to the turns_left estimate" do
    established("India", 10, from_city: "Delhi", to_city: "Mumbai", to_civ: "India", turns_left: 5)

    get game_trade_routes_url(@game)

    assert_select "table.trade-route-concurrency .badge", "estimated end"
  end

  test "links back to the game" do
    established("India", 10, from_city: "Delhi", to_city: "Mumbai", to_civ: "India", turns_left: 20)

    get game_trade_routes_url(@game)

    assert_select "a[href=?]", game_path(@game)
  end

  test "reports no data for a game with no trade route activity" do
    get game_trade_routes_url(@game)

    assert_response :success
    assert_select ".empty-state"
  end

  test "404s for an unknown game id" do
    get game_trade_routes_url(game_id: 999_999)

    assert_response :not_found
  end

  private

  def established(civ, turn, from_city:, to_city:, to_civ:, turns_left:)
    @game.game_events.create!(
      seq: @game.game_events.count + 1, session_index: 0, turn: turn, event_type: "trade_route_established", civ: civ,
      payload: { "event" => "trade_route_established", "turn" => turn, "from_city" => from_city, "to_city" => to_city,
                 "to_civ" => to_civ, "type" => "food", "turns_left" => turns_left }
    )
  end
end
