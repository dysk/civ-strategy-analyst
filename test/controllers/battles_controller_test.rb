require "test_helper"

class BattlesControllerTest < ActionDispatch::IntegrationTest
  setup do
    @game = Game.create!(name: "Battles Controller Game")
    @seq = 0
  end

  test "lists a detected battle with its city and turn span" do
    battle("Roma", 10, 10, turns: [ 40, 41, 42 ], civ: "Rome", stock: 3)

    get game_battles_url(@game)

    assert_response :success
    assert_select "table.battles tbody tr", 1
    assert_select "table.battles tbody td", "Roma"
    assert_select "table.battles tbody td", "40–42"
  end

  test "names how many each side lost" do
    battle("Roma", 10, 10, turns: [ 40, 41, 42 ], civ: "Rome", stock: 3)

    get game_battles_url(@game)

    assert_select "table.battles tbody td", text: "Rome: 3"
  end

  test "flags a battle that broke an army's stock as decisive" do
    battle("Roma", 10, 10, turns: [ 40, 41, 42 ], civ: "Rome", stock: 3)

    get game_battles_url(@game)

    assert_select "table.battles tbody td.decisive", "Yes"
  end

  test "leaves a battle nobody's stock measured against unflagged" do
    battle("Roma", 10, 10, turns: [ 40, 41, 42 ], civ: "Zurich", stock: 0)

    get game_battles_url(@game)

    assert_select "table.battles tbody td.decisive", text: "Yes", count: 0
  end

  test "shows an empty state when the log has no battle" do
    get game_battles_url(@game)

    assert_response :success
    assert_select "p.empty-state"
  end

  test "links back to the game" do
    get game_battles_url(@game)

    assert_select "a[href=?]", game_path(@game)
  end

  test "404s for an unknown game id" do
    get game_battles_url(game_id: 999_999)

    assert_response :not_found
  end

  private

  def battle(city, x, y, turns:, civ:, stock:)
    founded(civ, city, x, y)
    stock.times { created(civ) }
    turns.each { |turn| lost(civ, turn, x, y) }
  end

  def founded(civ, city, x, y)
    event(civ, "city_founded", 1, city: city, x: x, y: y)
  end

  def created(civ)
    event(civ, "unit_created", 1, unit: "UNIT_WARRIOR")
  end

  def lost(civ, turn, x, y)
    event(civ, "unit_lost", turn, unit: "UNIT_WARRIOR", x: x, y: y)
  end

  def event(civ, event_type, turn, **extra)
    @seq += 1
    payload = extra.stringify_keys.merge("event" => event_type, "turn" => turn)
    payload["civ"] = civ if civ
    @game.game_events.create!(
      seq: @seq, session_index: 0, turn: turn, event_type: event_type, civ: civ, payload: payload
    )
  end
end
