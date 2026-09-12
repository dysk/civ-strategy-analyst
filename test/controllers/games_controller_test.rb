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

  test "show places the Strategy Report section right after the capital layout graphic" do
    game = Game.create!(name: "Report Placement Game", map_width: 46)
    %w[Rome Greece].each { |civ| game.players.create!(civ: civ) }
    city(game, "Rome", 0, 10, 10)
    city(game, "Greece", 0, 30, 10)
    game.analyses.create!(model: "m", report: "# Verdict", digest: {})

    get game_url(game)

    body = response.body
    assert_operator body.index('svg class="capital-layout"'), :<, body.index('id="strategy-report"')
  end

  test "show draws a point and label for every capital in the layout diagram" do
    game = Game.create!(name: "Layout Game", map_width: 46)
    %w[Rome Greece Carthage].each { |civ| game.players.create!(civ: civ) }
    city(game, "Rome", 0, 10, 10)
    city(game, "Greece", 0, 30, 10)
    city(game, "Carthage", 0, 16, 20)

    get game_url(game)

    assert_response :success
    assert_select "svg.capital-layout circle", 3
    assert_select "svg.capital-layout text" do |labels|
      assert_equal %w[Rome Greece Carthage], labels.map(&:text)
    end
  end

  test "show marks a city-state's capital apart from the players' in the layout diagram" do
    game = Game.create!(name: "City-State Layout Game", map_width: 46)
    %w[Rome Greece].each { |civ| game.players.create!(civ: civ) }
    city_states(game, "Zurich")
    city(game, "Rome", 0, 10, 10)
    city(game, "Greece", 0, 30, 10)
    city(game, "Zurich", 0, 20, 20)

    get game_url(game)

    assert_response :success
    assert_select "svg.capital-layout .capital--major text" do |labels|
      assert_equal %w[Rome Greece], labels.map(&:text)
    end
    assert_select "svg.capital-layout .capital--minor text", "Zurich"
  end

  test "show widens the capital layout canvas to match a non-square map's aspect ratio" do
    game = Game.create!(name: "Wide Map Game", map_width: 92, map_height: 46)
    %w[Rome Greece].each { |civ| game.players.create!(civ: civ) }
    city(game, "Rome", 0, 10, 10)
    city(game, "Greece", 0, 30, 10)

    get game_url(game)

    assert_response :success
    assert_select "svg.capital-layout" do |svgs|
      assert_equal "0 0 1200 600", svgs.first["viewbox"]
    end
  end

  test "show keeps a square capital layout canvas when the map's dimensions match" do
    game = Game.create!(name: "Square Map Game", map_width: 46, map_height: 46)
    %w[Rome Greece].each { |civ| game.players.create!(civ: civ) }
    city(game, "Rome", 0, 10, 10)
    city(game, "Greece", 0, 30, 10)

    get game_url(game)

    assert_response :success
    assert_select "svg.capital-layout" do |svgs|
      assert_equal "0 0 600 600", svgs.first["viewbox"]
    end
  end

  test "show omits the capital layout diagram for a game with no city coordinates" do
    game = Game.create!(name: "Coordinateless Layout Game")
    game.players.create!(civ: "Rome")

    get game_url(game)

    assert_response :success
    assert_select "svg.capital-layout", false
  end

  test "show colours each civilization's capital with its own palette slot" do
    game = pangaea_game("Coloured Layout Game", civs: %w[Rome Greece])
    named_city(game, "Rome", "Roma", 0, 10, 20)
    named_city(game, "Greece", "Athenai", 0, 24, 20)

    get game_url(game)

    assert_response :success
    assert_select "svg.capital-layout g.capital--major.map-civ-0 text", "Rome"
    assert_select "svg.capital-layout g.capital--major.map-civ-1 text", "Greece"
  end

  test "show plots a buffer city as a small point in its civ's colour, labelled with its name" do
    game = pangaea_game("Buffer Map Game", civs: %w[Rome Greece])
    named_city(game, "Rome", "Roma", 0, 10, 20)
    named_city(game, "Greece", "Athenai", 0, 24, 20)
    named_city(game, "Rome", "Ostia", 30, 17, 20)

    get game_url(game)

    assert_select "svg.capital-layout g.buffer-city.map-civ-0 circle[r='4']"
    assert_select "svg.capital-layout g.buffer-city.map-civ-0 text", "Ostia"
  end

  test "show draws a corridor line between each neighbouring pair of capitals" do
    game = pangaea_game("Corridor Line Game", civs: %w[Rome Greece])
    named_city(game, "Rome", "Roma", 0, 10, 20)
    named_city(game, "Greece", "Athenai", 0, 24, 20)

    get game_url(game)

    assert_select "svg.capital-layout line.corridor", 1
  end

  test "show keeps an off-line buffer city inside the layout canvas" do
    game = pangaea_game("Off-line Buffer Game", civs: %w[Rome Greece])
    named_city(game, "Rome", "Roma", 0, 10, 20)
    named_city(game, "Greece", "Athenai", 0, 24, 20)
    named_city(game, "Rome", "Ostia", 30, 17, 23)

    get game_url(game)

    buffer_cy = css_select("svg.capital-layout g.buffer-city circle").first["cy"].to_f
    assert buffer_cy.between?(0, GamesController::CAPITAL_LAYOUT_HEIGHT), "buffer city clipped at cy=#{buffer_cy}"
  end

  test "show draws no corridor lines or buffer points when the map is not Pangaea" do
    game = Game.create!(name: "Continents Map Game", map_script: "Continents", map_width: 46)
    %w[Rome Greece].each { |civ| game.players.create!(civ: civ) }
    city(game, "Rome", 0, 10, 20)
    city(game, "Greece", 0, 24, 20)

    get game_url(game)

    assert_select "svg.capital-layout line.corridor", false
    assert_select "svg.capital-layout g.buffer-city", false
    assert_select "svg.capital-layout g.capital--major circle", 2
  end

  test "show gives each major section a self-linking anchor" do
    game = Game.create!(name: "Anchored Game")
    game.players.create!(civ: "Rome")

    get game_url(game)

    %w[capital-distances strategy-report].each do |id|
      assert_select "h2##{id} a.heading-anchor[href=?]", "##{id}"
    end
  end

  test "show marks a winner read from the game's own end-of-game record" do
    game = Game.create!(name: "Logged Outcome Game", completed: true,
      winner_civ: "India", winner_civs: [ "India" ], victory_type: "diplomatic")

    get game_url(game)

    assert_response :success
    assert_match "India", response.body
    assert_match "diplomatic", response.body
    assert_match "from game log", response.body
    assert_no_match(/declared winner/, response.body)
    assert_select ".badge", /complete/
  end

  test "show names every civilization of a team victory" do
    game = Game.create!(name: "Team Victory Game", completed: true,
      winner_civ: "India", winner_civs: [ "India", "Carthage" ], victory_type: "domination")

    get game_url(game)

    assert_match "India, Carthage", response.body
  end

  test "show reports a scrapped game as abandoned with no winner" do
    game = Game.create!(name: "Scrapped Game", completed: true,
      winner_civ: nil, winner_civs: nil, victory_type: "scrapped")

    get game_url(game)

    assert_response :success
    assert_match(/scrapped/i, response.body)
    assert_no_match(/No leader yet/, response.body)
    assert_select ".badge", /complete/
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

  test "show links to all projections" do
    game = Game.create!(name: "Linked Game")

    get game_url(game)

    assert_response :success
    assert_select "a[href=?]", game_projections_path(game)
  end

  private

  def pangaea_game(name, civs: %w[Rome Greece])
    game = Game.create!(name: name, map_script: "Pangaea")
    civs.each { |civ| game.players.create!(civ: civ) }
    game
  end

  def event(game, civ, event_type, turn, extra)
    game.game_events.create!(
      seq: game.game_events.count + 1, session_index: 0, turn: turn, event_type: event_type, civ: civ,
      payload: extra.merge("event" => event_type, "turn" => turn)
    )
  end

  def city_states(game, *civs)
    event(game, nil, "session_started", 0, "city_states" => civs.map { |civ| { "civ" => civ } })
  end

  def named_city(game, civ, city, turn, x, y)
    event(game, civ, "city_founded", turn, "civ" => civ, "city" => city, "x" => x, "y" => y)
  end

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
