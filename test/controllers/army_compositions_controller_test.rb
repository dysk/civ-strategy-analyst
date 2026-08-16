require "test_helper"

class ArmyCompositionsControllerTest < ActionDispatch::IntegrationTest
  setup do
    @game = Game.create!(name: "Army History Game")
    @game.players.create!(civ: "Rome")
  end

  test "samples the army every ten turns rather than listing every snapshot" do
    (1..25).each { |turn| army("Rome", turn, might: turn * 100, units: turn) }

    get game_army_url(@game)

    assert_response :success
    assert_select "table.army tbody tr", 3
  end

  test "always ends on the last turn recorded" do
    (1..25).each { |turn| army("Rome", turn, might: turn * 100, units: turn) }

    get game_army_url(@game)

    assert_select "table.army tbody tr:last-child td", "25"
  end

  test "shows the army power left once the treasury is divided out" do
    army("Rome", 10, might: 1300, units: 10, gold: 900)

    get game_army_url(@game)

    assert_select "table.army tbody td", "1000"
    assert_select "table.army tbody td", "100.0"
  end

  test "names the civilization each table belongs to" do
    @game.players.create!(civ: "Greece")
    army("Rome", 10, might: 100, units: 2)
    army("Greece", 10, might: 300, units: 3)

    get game_army_url(@game)

    assert_select "h2", "Rome"
    assert_select "h2", "Greece"
  end

  test "leaves out a civilization whose snapshots carry no military data" do
    @game.players.create!(civ: "Greece")
    army("Rome", 10, might: 100, units: 2)
    @game.game_events.create!(
      seq: 99, session_index: 0, turn: 10, event_type: "snapshot", civ: "Greece",
      payload: { "event" => "snapshot", "turn" => 10, "civ" => "Greece", "score" => 50 }
    )

    get game_army_url(@game)

    assert_select "h2", text: "Greece", count: 0
  end

  test "links back to the game" do
    army("Rome", 10, might: 100, units: 2)

    get game_army_url(@game)

    assert_select "a[href=?]", game_path(@game)
  end

  test "404s for an unknown game id" do
    get game_army_url(game_id: 999_999)

    assert_response :not_found
  end

  private

  def army(civ, turn, might:, units:, gold: 0)
    @game.game_events.create!(
      seq: @game.game_events.count + 1, session_index: 0, turn: turn, event_type: "snapshot", civ: civ,
      payload: { "event" => "snapshot", "turn" => turn, "civ" => civ, "gold" => gold,
                 "military_might" => might, "military_units" => units }
    )
  end
end
