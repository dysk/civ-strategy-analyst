require "test_helper"

class CulturalStandingsControllerTest < ActionDispatch::IntegrationTest
  setup do
    @game = Game.create!(name: "Cultural History Game")
    @game.players.create!(civ: "Rome")
  end

  test "lists tourism and civs influential on over time" do
    snapshot("Rome", 10, tourism: 45, civs_influential_on: 0)
    snapshot("Rome", 30, tourism: 120, civs_influential_on: 1)

    get game_cultural_url(@game)

    assert_response :success
    assert_select "table.tourism tbody tr", 2
    assert_select "table.tourism tbody tr:last-child td", "30"
  end

  test "lists influence over time per opponent" do
    snapshot("Rome", 10, influence: [ { "civ" => "Greece", "points" => 50, "level" => "INFLUENCE_LEVEL_EXOTIC", "trend" => "INFLUENCE_TREND_RISING" } ])
    snapshot("Rome", 30, influence: [ { "civ" => "Greece", "points" => 320, "level" => "INFLUENCE_LEVEL_INFLUENTIAL", "trend" => "INFLUENCE_TREND_RISING" } ])

    get game_cultural_url(@game)

    assert_response :success
    assert_select "table.influence tbody tr", 2
    assert_select "table.influence tbody td", "Greece"
    assert_select "table.influence tbody td", "INFLUENCE_LEVEL_INFLUENTIAL"
  end

  test "names the civilization each history belongs to" do
    @game.players.create!(civ: "Greece")
    snapshot("Rome", 10, tourism: 45)
    snapshot("Greece", 10, tourism: 20)

    get game_cultural_url(@game)

    assert_select "h2", "Rome"
    assert_select "h2", "Greece"
  end

  test "leaves out a civilization with no tourism or influence data" do
    @game.players.create!(civ: "Greece")
    snapshot("Rome", 10, tourism: 45)
    snapshot("Greece", 10, score: 100)

    get game_cultural_url(@game)

    assert_select "h2", text: "Greece", count: 0
  end

  test "reports no data for a game with nothing to show" do
    get game_cultural_url(@game)

    assert_response :success
    assert_select ".empty-state"
  end

  test "links back to the game" do
    snapshot("Rome", 10, tourism: 45)

    get game_cultural_url(@game)

    assert_select "a[href=?]", game_path(@game)
  end

  test "404s for an unknown game id" do
    get game_cultural_url(game_id: 999_999)

    assert_response :not_found
  end

  private

  def snapshot(civ, turn, metrics)
    @game.game_events.create!(
      seq: @game.game_events.count + 1, session_index: 0, turn: turn, event_type: "snapshot", civ: civ,
      payload: metrics.stringify_keys.merge("event" => "snapshot", "turn" => turn, "civ" => civ)
    )
  end
end
