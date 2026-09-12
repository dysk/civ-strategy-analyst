require "test_helper"

class YieldAttributionHistoriesControllerTest < ActionDispatch::IntegrationTest
  setup do
    @game = Game.create!(name: "Yield Attribution History Game")
    @game.players.create!(civ: "India")
  end

  test "samples the series every ten turns rather than listing every snapshot" do
    (1..25).each { |turn| snapshot(turn, science: turn, cities: turn) }

    get game_yield_attribution_url(@game)

    assert_response :success
    assert_select "table.yield-attribution-history tbody tr", 3
  end

  test "always ends on the last turn recorded" do
    (1..25).each { |turn| snapshot(turn, science: turn, cities: turn) }

    get game_yield_attribution_url(@game)

    assert_select "table.yield-attribution-history tbody tr:last-child td", "25"
  end

  test "names the yield and the civilization each table belongs to" do
    snapshot(10, science: 40, cities: 40)

    get game_yield_attribution_url(@game)

    assert_select "h2", "India"
    assert_select "h3", "Science"
  end

  test "shows the sources and shortfall behind the total" do
    snapshot(10, culture: 7, cities: 6)

    get game_yield_attribution_url(@game)

    assert_select "table.yield-attribution-history tbody td", "cities: 6"
    assert_select "table.yield-attribution-history tbody td", "1"
  end

  test "links back to the game" do
    snapshot(10, science: 40, cities: 40)

    get game_yield_attribution_url(@game)

    assert_select "a[href=?]", game_path(@game)
  end

  test "reports no data for a game with no yield source breakdown" do
    get game_yield_attribution_url(@game)

    assert_response :success
    assert_select ".empty-state"
  end

  test "404s for an unknown game id" do
    get game_yield_attribution_url(game_id: 999_999)

    assert_response :not_found
  end

  private

  def snapshot(turn, cities:, science: nil, culture: nil)
    sources = {}
    sources["science"] = { "cities" => cities } if science
    sources["culture"] = { "cities" => cities } if culture

    @game.game_events.create!(
      seq: @game.game_events.count + 1, session_index: 0, turn: turn, event_type: "snapshot", civ: "India",
      payload: { "event" => "snapshot", "turn" => turn, "civ" => "India", "science" => science, "culture" => culture,
                 "yield_sources" => sources }
    )
  end
end
