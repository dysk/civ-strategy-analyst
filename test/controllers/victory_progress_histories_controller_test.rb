require "test_helper"

class VictoryProgressHistoriesControllerTest < ActionDispatch::IntegrationTest
  setup do
    @game = Game.create!(name: "Victory Progress History Game")
    @game.players.create!(civ: "Rome")
  end

  test "lists capitals held over time" do
    snapshot("Rome", 10, capitals: %w[Rome])
    snapshot("Rome", 30, capitals: %w[Rome Greece])

    get game_victory_progress_url(@game)

    assert_response :success
    assert_select "table.capitals tbody tr", 2
    assert_select "table.capitals tbody tr:last-child td", "2"
  end

  test "lists spaceship assembly over time" do
    snapshot("Rome", 10, spaceship: { apollo: 1, booster: 0, cockpit: 0, stasis_chamber: 0, engine: 0 })
    snapshot("Rome", 30, spaceship: { apollo: 1, booster: 1, cockpit: 0, stasis_chamber: 0, engine: 0 })

    get game_victory_progress_url(@game)

    assert_response :success
    assert_select "table.spaceship tbody tr", 2
    assert_select "table.spaceship tbody tr:last-child td", "1"
  end

  test "names the civilization each history belongs to" do
    @game.players.create!(civ: "Greece")
    snapshot("Rome", 10, capitals: %w[Rome])
    snapshot("Greece", 10, capitals: %w[Greece])

    get game_victory_progress_url(@game)

    assert_select "h2", "Rome"
    assert_select "h2", "Greece"
  end

  test "leaves out a civilization with no capitals or spaceship data" do
    @game.players.create!(civ: "Greece")
    snapshot("Rome", 10, capitals: %w[Rome])
    snapshot("Greece", 10, score: 100)

    get game_victory_progress_url(@game)

    assert_select "h2", text: "Greece", count: 0
  end

  test "reports no data for a game with nothing to show" do
    get game_victory_progress_url(@game)

    assert_response :success
    assert_select ".empty-state"
  end

  test "links back to the game" do
    snapshot("Rome", 10, capitals: %w[Rome])

    get game_victory_progress_url(@game)

    assert_select "a[href=?]", game_path(@game)
  end

  test "404s for an unknown game id" do
    get game_victory_progress_url(game_id: 999_999)

    assert_response :not_found
  end

  private

  def snapshot(civ, turn, metrics)
    @game.game_events.create!(
      seq: @game.game_events.count + 1, session_index: 0, turn: turn, event_type: "snapshot", civ: civ,
      payload: metrics.deep_stringify_keys.merge("event" => "snapshot", "turn" => turn, "civ" => civ)
    )
  end
end
