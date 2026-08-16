require "test_helper"

class EmpireGeometriesControllerTest < ActionDispatch::IntegrationTest
  setup do
    @game = Game.create!(name: "Geometry History Game", map_width: 46)
    @game.players.create!(civ: "Rome")
  end

  test "lists every recorded change to an empire's shape" do
    city("Rome", 1, 10, 10)
    city("Rome", 5, 14, 10)
    city("Rome", 9, 10, 16)

    get game_geometry_url(@game)

    assert_response :success
    assert_select "table.geometry tbody tr", 3
  end

  test "shows the turn each change happened on" do
    city("Rome", 1, 10, 10)
    city("Rome", 5, 14, 10)

    get game_geometry_url(@game)

    assert_select "table.geometry tbody tr:last-child td", "5"
  end

  test "names the civilization each table belongs to" do
    @game.players.create!(civ: "Greece")
    city("Rome", 1, 10, 10)
    city("Greece", 2, 20, 20)

    get game_geometry_url(@game)

    assert_select "h2", "Rome"
    assert_select "h2", "Greece"
  end

  test "reports the turns a civilization's city count stopped adding up" do
    city("Rome", 1, 10, 10)
    snapshot("Rome", 20, cities: 0)

    get game_geometry_url(@game)

    assert_select ".mismatches", /turn 20/
  end

  test "leaves out a civilization that never held a city with coordinates" do
    @game.players.create!(civ: "Greece")
    city("Rome", 1, 10, 10)

    get game_geometry_url(@game)

    assert_select "h2", text: "Greece", count: 0
  end

  test "says the map width was inferred rather than reported" do
    game = Game.create!(name: "Inferred Width Game")
    game.players.create!(civ: "Rome")
    game.game_events.create!(
      seq: 1, session_index: 0, turn: 1, event_type: "city_founded", civ: "Rome",
      payload: { "event" => "city_founded", "turn" => 1, "civ" => "Rome", "x" => 45, "y" => 10 }
    )

    get game_geometry_url(game)

    assert_select ".geometry-note", /inferred/i
  end

  test "links back to the game" do
    city("Rome", 1, 10, 10)

    get game_geometry_url(@game)

    assert_select "a[href=?]", game_path(@game)
  end

  test "404s for an unknown game id" do
    get game_geometry_url(game_id: 999_999)

    assert_response :not_found
  end

  private

  def city(civ, turn, x, y)
    event(civ, "city_founded", turn, "x" => x, "y" => y)
  end

  def snapshot(civ, turn, cities:)
    event(civ, "snapshot", turn, "cities" => cities)
  end

  def event(civ, event_type, turn, extra)
    @game.game_events.create!(
      seq: @game.game_events.count + 1, session_index: 0, turn: turn, event_type: event_type, civ: civ,
      payload: extra.merge("event" => event_type, "turn" => turn, "civ" => civ)
    )
  end
end
