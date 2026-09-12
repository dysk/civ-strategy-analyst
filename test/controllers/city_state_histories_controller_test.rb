require "test_helper"

class CityStateHistoriesControllerTest < ActionDispatch::IntegrationTest
  setup do
    @game = Game.create!(name: "City-State History Game")
    @game.players.create!(civ: "India")
    event(nil, "session_started", 0, "city_states" => [ { "civ" => "Ljubljana", "trait" => "cultured" } ])
  end

  test "samples the standing series every ten turns rather than listing every snapshot" do
    (1..25).each { |turn| city_state_snapshot(turn, influence: turn) }

    get game_city_states_url(@game)

    assert_response :success
    assert_select "table.city-state-standing tbody tr", 3
  end

  test "always ends on the last turn recorded" do
    (1..25).each { |turn| city_state_snapshot(turn, influence: turn) }

    get game_city_states_url(@game)

    assert_select "table.city-state-standing tbody tr:last-child td", "25"
  end

  test "names the city-state and the civilization each table belongs to" do
    city_state_snapshot(10, influence: 5)

    get game_city_states_url(@game)

    assert_select "h2", "Ljubljana"
    assert_select "h3", "India"
  end

  test "links back to the game" do
    city_state_snapshot(10, influence: 5)

    get game_city_states_url(@game)

    assert_select "a[href=?]", game_path(@game)
  end

  test "reports no data for a game with no city-state snapshots" do
    get game_city_states_url(@game)

    assert_response :success
    assert_select ".empty-state"
  end

  test "404s for an unknown game id" do
    get game_city_states_url(game_id: 999_999)

    assert_response :not_found
  end

  private

  def city_state_snapshot(turn, influence:)
    event(nil, "city_state_snapshot", turn, "city_state" => "Ljubljana",
          "relations" => [ { "civ" => "India", "influence" => influence, "per_turn" => 1.25 } ])
  end

  def event(civ, event_type, turn, extra)
    @game.game_events.create!(
      seq: @game.game_events.count + 1, session_index: 0, turn: turn, event_type: event_type, civ: civ,
      payload: extra.merge("event" => event_type, "turn" => turn)
    )
  end
end
