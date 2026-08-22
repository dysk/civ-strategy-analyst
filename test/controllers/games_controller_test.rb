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

  test "show keeps every key moment section collapsed until it is clicked" do
    game = Game.create!(name: "Collapsed Game")
    war(game, 10)

    get game_url(game)

    assert_select "details summary", "Wars (1)"
    assert_select "details[open]", false
  end

  test "show marks the direction of a happiness swing in the list" do
    game = Game.create!(name: "Swing Game", game_speed: "GAMESPEED_QUICK")
    snapshot(game, "Rome", 100, happiness: 15)
    snapshot(game, "Rome", 101, happiness: 1)

    get game_url(game)

    assert_select "details li .trend--down"
  end

  test "show gathers the religion moments into one section" do
    game = Game.create!(name: "Religion Game")
    event(game, "Rome", "pantheon_founded", 5, "belief" => "BELIEF_A")
    event(game, "Rome", "reformation_added", 60, "religion" => "Christianity", "belief" => "BELIEF_B")

    get game_url(game)

    assert_select "details summary", "Religion (2)"
    assert_select "details summary", text: /Pantheon/, count: 0
  end

  test "show keeps the kinds of religion moment apart inside the section" do
    game = Game.create!(name: "Religion Order Game")
    event(game, "Rome", "pantheon_founded", 5, "belief" => "BELIEF_A")
    event(game, "Rome", "reformation_added", 60, "religion" => "Christianity", "belief" => "BELIEF_B")

    get game_url(game)

    assert_select "details h3", "Pantheon Foundings"
    assert_select "details h3", "Reformations"
  end

  test "show gathers cultural key moments into one section" do
    game = Game.create!(name: "Cultural Game")
    snapshot(game, "Rome", 10, influence: [ { "civ" => "Greece", "points" => 50, "level" => "INFLUENCE_LEVEL_EXOTIC", "trend" => "INFLUENCE_TREND_RISING" } ])
    snapshot(game, "Rome", 30, influence: [ { "civ" => "Greece", "points" => 320, "level" => "INFLUENCE_LEVEL_INFLUENTIAL", "trend" => "INFLUENCE_TREND_RISING" } ])

    get game_url(game)

    assert_select "details summary", "Cultural Standing (1)"
    assert_match "Rome became Influential on Greece", response.body
  end

  test "show gathers Congress key moments into one section" do
    game = Game.create!(name: "Congress Game")
    event(game, nil, "congress_host_changed", 90, "old_host" => nil, "new_host" => "Rome")
    event(game, nil, "united_nations_formed", 220, {})

    get game_url(game)

    assert_select "details summary", "World Congress (2)"
    assert_match "World Congress host passed from no host to Rome", response.body
    assert_match "The United Nations formed", response.body
  end

  test "show gathers victory-progress key moments into one section" do
    game = Game.create!(name: "Victory Progress Game")
    snapshot(game, "Rome", 100, spaceship: { "apollo" => 0, "booster" => 0, "cockpit" => 0, "stasis_chamber" => 0, "engine" => 0 })
    snapshot(game, "Rome", 120, spaceship: { "apollo" => 1, "booster" => 0, "cockpit" => 0, "stasis_chamber" => 0, "engine" => 0 })

    get game_url(game)

    assert_select "details summary", "Victory Progress (1)"
    assert_match "Rome completed the Apollo Program", response.body
  end

  test "show gathers snowballs across every metric into one section" do
    game = Game.create!(name: "Snowball Game")
    (1..30).each do |turn|
      snapshot(game, "Rome", turn, score: turn * 10, science: turn * 10)
      snapshot(game, "Greece", turn, score: turn * 2, science: turn * 2)
    end

    get game_url(game)

    assert_select "details summary", "Snowballs (2)"
    assert_select "details h3", "Score"
    assert_select "details h3", "Science"
  end

  test "show titleizes underscored snowball metric names" do
    game = Game.create!(name: "Snowball Game")
    (1..30).each do |turn|
      snapshot(game, "Rome", turn, gold_per_turn: turn * 10)
      snapshot(game, "Greece", turn, gold_per_turn: turn * 2)
    end

    get game_url(game)

    assert_select "details h3", "Gold Per Turn"
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

  test "show displays the distance between each pair of capitals, closest first" do
    game = Game.create!(name: "Proximity Game", map_width: 46)
    %w[Rome Greece Carthage].each { |civ| game.players.create!(civ: civ) }
    city(game, "Rome", 0, 10, 10)
    city(game, "Greece", 0, 30, 10)
    city(game, "Carthage", 0, 16, 10)

    get game_url(game)

    assert_response :success
    assert_select "table.capital-distances tbody tr" do |rows|
      assert_equal [ "6", "14", "20" ], rows.map { |row| row.css("td").last.text }
    end
  end

  test "show omits the capital distances table for a game with no city coordinates" do
    game = Game.create!(name: "Coordinateless Proximity Game")
    game.players.create!(civ: "Rome")

    get game_url(game)

    assert_response :success
    assert_select "table.capital-distances", false
  end

  test "show flags capital distances measured against an estimated map width" do
    game = Game.create!(name: "Estimated Width Game")
    %w[Rome Greece].each { |civ| game.players.create!(civ: civ) }
    city(game, "Rome", 0, 10, 10)
    city(game, "Greece", 0, 16, 10)

    get game_url(game)

    assert_select ".badge", /map width estimated/
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

  test "show widens the capital layout canvas to match a non-square map's aspect ratio" do
    game = Game.create!(name: "Wide Map Game", map_width: 92, map_height: 46)
    %w[Rome Greece].each { |civ| game.players.create!(civ: civ) }
    city(game, "Rome", 0, 10, 10)
    city(game, "Greece", 0, 30, 10)

    get game_url(game)

    assert_response :success
    assert_select "svg.capital-layout" do |svgs|
      assert_equal "0 0 600 300", svgs.first["viewbox"]
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
      assert_equal "0 0 300 300", svgs.first["viewbox"]
    end
  end

  test "show omits the capital layout diagram for a game with no city coordinates" do
    game = Game.create!(name: "Coordinateless Layout Game")
    game.players.create!(civ: "Rome")

    get game_url(game)

    assert_response :success
    assert_select "svg.capital-layout", false
  end

  test "show displays where each civilization's early game ends" do
    game = Game.create!(name: "Early Game Game", game_speed: "GAMESPEED_QUICK")
    game.players.create!(civ: "Rome")
    game.players.create!(civ: "Greece")
    event(game, nil, "tech_researched", 40, "team" => 1, "civs" => [ "Rome" ], "tech" => "TECH_EDUCATION")
    event(game, "Rome", "building_constructed", 60, "building" => "BUILDING_WORKSHOP", "city" => "Roma")
    snapshot(game, "Greece", 110, score: 10)

    get game_url(game)

    assert_response :success
    assert_equal(
      [
        [ "Rome", "60", "milestone", "EDUCATION + WORKSHOP", "40", "60" ],
        [ "Greece", "100", "deadline", "—", "—", "—" ]
      ],
      css_select("table.early-game tbody tr").map { |row| row.css("td").map(&:text) }
    )
  end

  test "show displays both sides of a corridor, the side without a buffer included" do
    game = pangaea_game("Buffer Game")
    named_city(game, "Rome", "Roma", 0, 10, 20)
    named_city(game, "Greece", "Athenai", 0, 27, 20)
    named_city(game, "Rome", "Ostia", 30, 18, 20)

    get game_url(game)

    assert_response :success
    assert_select "table.buffer-cities tbody tr", 2
    assert_select "table.buffer-cities tbody tr:first-child td", "Ostia"
    assert_select "table.buffer-cities tbody tr:last-child td", "Greece"
  end

  test "show badges the civilization that settled its corridor first" do
    game = pangaea_game("Buffer Race Game")
    named_city(game, "Rome", "Roma", 0, 10, 20)
    named_city(game, "Greece", "Athenai", 0, 27, 20)
    named_city(game, "Rome", "Ostia", 20, 14, 20)
    named_city(game, "Greece", "Sparta", 30, 22, 20)

    get game_url(game)

    assert_select "table.buffer-cities tbody tr:first-child .badge", "first"
  end

  test "show explains that buffer cities are measured on Pangaea alone" do
    game = Game.create!(name: "Continents Game", map_script: "Continents")
    %w[Rome Greece].each { |civ| game.players.create!(civ: civ) }
    named_city(game, "Rome", "Roma", 0, 10, 20)
    named_city(game, "Greece", "Athenai", 0, 27, 20)

    get game_url(game)

    assert_select "table.buffer-cities", false
    assert_select "p.empty-state", /only computed for Pangaea/
  end

  test "show names the order a civilization closed its corridors" do
    game = pangaea_game("Buffer Priority Game", civs: %w[Rome Greece Egypt])
    named_city(game, "Rome", "Roma", 0, 10, 20)
    named_city(game, "Greece", "Athenai", 0, 27, 20)
    named_city(game, "Egypt", "Thebes", 0, 15, 13)
    named_city(game, "Rome", "Neapolis", 20, 14, 17)
    named_city(game, "Rome", "Ostia", 30, 18, 20)

    get game_url(game)

    assert_select "p", /Rome secured its corridors in this order: Egypt, Greece/
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

  test "show displays what each civilization's army is made of" do
    game = Game.create!(name: "Army Game")
    game.players.create!(civ: "Rome")
    snapshot(game, "Rome", 20, military_might: 1300, military_units: 10, gold: 900)

    get game_url(game)

    assert_response :success
    assert_select "table.army" do
      assert_select "td", "Rome"
      assert_select "td", "10"
      assert_select "td", "1300"
      assert_select "td", "1000"
      assert_select "td", "100.0"
    end
  end

  test "show links to the history behind the army table" do
    game = Game.create!(name: "Army History Link Game")
    game.players.create!(civ: "Rome")
    snapshot(game, "Rome", 20, military_might: 1000, military_units: 8, gold: 0)

    get game_url(game)

    assert_select "a[href=?]", game_army_path(game)
  end

  test "show omits the army table for a game whose snapshots carry no military data" do
    game = Game.create!(name: "Peaceful Game")
    game.players.create!(civ: "Rome")
    snapshot(game, "Rome", 20, score: 100)

    get game_url(game)

    assert_select "table.army", false
  end

  test "show displays each civilization's tourism and cultural standing" do
    game = Game.create!(name: "Cultural Table Game")
    game.players.create!(civ: "Rome")
    snapshot(game, "Rome", 30, tourism: 120, civs_influential_on: 1,
      influence: [ { "civ" => "Greece", "points" => 320, "level" => "INFLUENCE_LEVEL_INFLUENTIAL", "trend" => "INFLUENCE_TREND_RISING" } ])

    get game_url(game)

    assert_response :success
    assert_select "table.cultural" do
      assert_select "td", "Rome"
      assert_select "td", "120"
      assert_select "td", "1"
      assert_select "td", "Greece"
    end
  end

  test "show links to the history behind the cultural table" do
    game = Game.create!(name: "Cultural History Link Game")
    game.players.create!(civ: "Rome")
    snapshot(game, "Rome", 20, tourism: 45)

    get game_url(game)

    assert_select "a[href=?]", game_cultural_path(game)
  end

  test "show omits the cultural table for a game with no tourism data" do
    game = Game.create!(name: "No Culture Game")
    game.players.create!(civ: "Rome")
    snapshot(game, "Rome", 20, score: 100)

    get game_url(game)

    assert_select "table.cultural", false
  end

  test "show displays World Congress host, votes needed and each civilization's delegate votes" do
    game = Game.create!(name: "Congress Table Game")
    game.players.create!(civ: "Rome")
    congress_snapshot(game, 30, host: "Rome", delegates: [ { "civ" => "Rome", "votes" => 5 } ], votes_needed: 12)

    get game_url(game)

    assert_response :success
    assert_match "Rome", response.body
    assert_select "table.congress" do
      assert_select "td", "Rome"
      assert_select "td", "5"
    end
    assert_match(/12/, response.body)
  end

  test "show links to the history behind the Congress table" do
    game = Game.create!(name: "Congress History Link Game")
    game.players.create!(civ: "Rome")
    congress_snapshot(game, 30, host: "Rome", delegates: [ { "civ" => "Rome", "votes" => 5 } ], votes_needed: 12)

    get game_url(game)

    assert_select "a[href=?]", game_congress_path(game)
  end

  test "show omits the Congress table for a game with no Congress data" do
    game = Game.create!(name: "No Congress Game")
    game.players.create!(civ: "Rome")

    get game_url(game)

    assert_select "table.congress", false
  end

  test "show displays each civilization's capitals held and spaceship assembly" do
    game = Game.create!(name: "Victory Progress Table Game")
    game.players.create!(civ: "Rome")
    snapshot(game, "Rome", 100, capitals: %w[Rome Greece],
      spaceship: { "apollo" => 1, "booster" => 2, "cockpit" => 1, "stasis_chamber" => 0, "engine" => 1 })

    get game_url(game)

    assert_response :success
    assert_select "table.victory-progress" do
      assert_select "td", "Rome"
      assert_select "td", "2"
      assert_select "td", "4 / 6"
    end
  end

  test "show links to the history behind the victory progress table" do
    game = Game.create!(name: "Victory Progress History Link Game")
    game.players.create!(civ: "Rome")
    snapshot(game, "Rome", 20, capitals: %w[Rome])

    get game_url(game)

    assert_select "a[href=?]", game_victory_progress_path(game)
  end

  test "show omits the victory progress table for a game with no capitals or spaceship data" do
    game = Game.create!(name: "No Victory Progress Game")
    game.players.create!(civ: "Rome")
    snapshot(game, "Rome", 20, score: 100)

    get game_url(game)

    assert_select "table.victory-progress", false
  end

  test "show marks a civilization whose city count the timeline cannot account for" do
    game = Game.create!(name: "Razed City Game", map_width: 46)
    game.players.create!(civ: "Rome")
    city(game, "Rome", 1, 10, 10)
    snapshot(game, "Rome", 20, cities: 0)

    get game_url(game)

    assert_select "table.geometry .badge", /turn 20/
  end

  test "show links to the history behind the geometry table" do
    game = Game.create!(name: "Geometry History Link Game", map_width: 46)
    game.players.create!(civ: "Rome")
    city(game, "Rome", 1, 10, 10)

    get game_url(game)

    assert_select "a[href=?]", game_geometry_path(game)
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

  def war(game, turn)
    event(
      game, nil, "war_declared", turn,
      "attacker_team" => 1, "attacker_civs" => [ "Rome" ],
      "defender_team" => 2, "defender_civs" => [ "Greece" ]
    )
  end

  def event(game, civ, event_type, turn, extra)
    game.game_events.create!(
      seq: game.game_events.count + 1, session_index: 0, turn: turn, event_type: event_type, civ: civ,
      payload: extra.merge("event" => event_type, "turn" => turn)
    )
  end

  def pangaea_game(name, civs: %w[Rome Greece])
    game = Game.create!(name: name, map_script: "Pangaea")
    civs.each { |civ| game.players.create!(civ: civ) }
    game
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

  def congress_snapshot(game, turn, host:, delegates:, votes_needed:)
    game.game_events.create!(
      seq: game.game_events.count + 1, session_index: 0, turn: turn, event_type: "congress_snapshot", civ: nil,
      payload: { "event" => "congress_snapshot", "turn" => turn, "host" => host,
                 "delegates" => delegates, "votes_needed_for_diplo_victory" => votes_needed }
    )
  end

  def snapshot(game, civ, turn, metrics)
    game.game_events.create!(
      seq: game.game_events.count + 1, session_index: 0, turn: turn, event_type: "snapshot", civ: civ,
      payload: metrics.stringify_keys.merge("event" => "snapshot", "turn" => turn, "civ" => civ)
    )
  end
end
