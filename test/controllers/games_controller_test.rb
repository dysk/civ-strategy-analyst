require "test_helper"

class GamesControllerTest < ActionDispatch::IntegrationTest
  test "index lists games with their analysis status" do
    analyzed = Game.create!(name: "Analyzed Game")
    analyzed.analyses.create!(model: "m", report: "r", digest: {})
    not_analyzed = Game.create!(name: "Fresh Game")

    get games_url

    assert_response :success
    assert_match "Analyzed Game", response.body
    assert_match "Fresh Game", response.body
  end

  test "show displays standings inferred from the latest snapshots" do
    game = Game.create!(name: "Show Test Game", max_turns: 100)
    snapshot(game, "Rome", 10, score: 300)
    snapshot(game, "Greece", 10, score: 100)

    get game_url(game)

    assert_response :success
    assert_match "Rome", response.body
    assert_match(/in progress/i, response.body)
  end

  test "show displays key moments detected from the game's events" do
    game = Game.create!(name: "War Game")
    game.game_events.create!(
      seq: 1, session_index: 0, turn: 10, event_type: "war_declared",
      payload: { "event" => "war_declared", "turn" => 10, "attacker_team" => 1,
                 "attacker_civs" => [ "Rome" ], "defender_team" => 2, "defender_civs" => [ "Greece" ] }
    )

    get game_url(game)

    assert_response :success
    assert_match "Rome", response.body
    assert_match "Greece", response.body
  end

  test "show renders the latest analysis report as markdown" do
    game = Game.create!(name: "Reported Game")
    game.analyses.create!(model: "m", report: "# Verdict\n\nRome **wins**.", digest: {})

    get game_url(game)

    assert_response :success
    assert_select "h1", "Verdict"
    assert_select "strong", "wins"
  end

  test "show links to the analyses list even when there is only one analysis" do
    game = Game.create!(name: "Single Analysis Game")
    game.analyses.create!(model: "m", report: "report", digest: {})

    get game_url(game)

    assert_response :success
    assert_select "a[href=?]", game_analyses_path(game), text: /View all 1 analysis\b/
  end

  test "show links to the analyses list when there is more than one analysis" do
    game = Game.create!(name: "Multi Analysis Game")
    game.analyses.create!(model: "m1", report: "older", digest: {})
    game.analyses.create!(model: "m2", report: "newer", digest: {})

    get game_url(game)

    assert_response :success
    assert_select "a[href=?]", game_analyses_path(game), text: /View all 2 analyses/
  end

  test "show tells the user no analysis exists yet" do
    game = Game.create!(name: "Unanalyzed Game")

    get game_url(game)

    assert_response :success
    assert_match(/not.{0,20}analyzed/i, response.body)
  end

  test "show displays each civilization's empire geometry" do
    game = Game.create!(name: "Geometry Game", map_width: 46)
    game.players.create!(civ: "Rome")
    city(game, "Rome", 1, 10, 10)
    city(game, "Rome", 5, 14, 10)

    get game_url(game)

    assert_response :success
    assert_select "table.geometry" do
      assert_select "td", "Rome"
      assert_select "td", "2"
      assert_select "td", "4"
      assert_select "td", "4.0"
      assert_select "td", "1.0"
    end
  end

  test "show says the map width was inferred rather than reported" do
    game = Game.create!(name: "Inferred Width Game")
    game.players.create!(civ: "Rome")
    city(game, "Rome", 1, 45, 10)

    get game_url(game)

    assert_select ".geometry-note", /inferred/i
  end

  test "show marks a civilization whose city count the timeline cannot account for" do
    game = Game.create!(name: "Razed City Game", map_width: 46)
    game.players.create!(civ: "Rome")
    city(game, "Rome", 1, 10, 10)
    snapshot(game, "Rome", 20, cities: 0)

    get game_url(game)

    assert_select "table.geometry .badge", /turn 20/
  end

  test "show omits the geometry table for a game with no city coordinates" do
    game = Game.create!(name: "Coordinateless Game")
    game.players.create!(civ: "Rome")

    get game_url(game)

    assert_response :success
    assert_select "table.geometry", false
  end

  test "show 404s for an unknown game id" do
    get game_url(id: 999_999)

    assert_response :not_found
  end

  test "show links to the raw event data" do
    game = Game.create!(name: "Linked Game")

    get game_url(game)

    assert_response :success
    assert_select "a[href=?]", game_events_path(game)
  end

  private

  def city(game, civ, turn, x, y)
    game.game_events.create!(
      seq: game.game_events.count + 1, session_index: 0, turn: turn, event_type: "city_founded", civ: civ,
      payload: { "event" => "city_founded", "turn" => turn, "civ" => civ, "x" => x, "y" => y }
    )
  end

  def snapshot(game, civ, turn, metrics)
    game.game_events.create!(
      seq: game.game_events.count + 1, session_index: 0, turn: turn, event_type: "snapshot", civ: civ,
      payload: metrics.stringify_keys.merge("event" => "snapshot", "turn" => turn, "civ" => civ)
    )
  end
end
