require "test_helper"

class GameProjectionsControllerTest < ActionDispatch::IntegrationTest
  test "show 404s for an unknown game id" do
    get game_projections_url(game_id: 999_999)

    assert_response :not_found
  end

  test "show links back to the game page" do
    game = Game.create!(name: "Linked Game")

    get game_projections_url(game)

    assert_response :success
    assert_select "a[href=?]", game_path(game)
  end

  test "show displays the distance between each pair of capitals, closest first" do
    game = Game.create!(name: "Proximity Game", map_width: 46)
    %w[Rome Greece Carthage].each { |civ| game.players.create!(civ: civ) }
    city(game, "Rome", 0, 10, 10)
    city(game, "Greece", 0, 30, 10)
    city(game, "Carthage", 0, 16, 10)

    get game_projections_url(game)

    assert_response :success
    assert_select "table.capital-distances tbody tr" do |rows|
      assert_equal [ "6", "14", "20" ], rows.map { |row| row.css("td").last.text }
    end
  end

  test "show omits the capital distances table for a game with no city coordinates" do
    game = Game.create!(name: "Coordinateless Proximity Game")
    game.players.create!(civ: "Rome")

    get game_projections_url(game)

    assert_response :success
    assert_select "table.capital-distances", false
  end

  test "show keeps the capital distances table behind a collapsed disclosure" do
    game = Game.create!(name: "Collapsed Proximity Game", map_width: 46)
    %w[Rome Greece].each { |civ| game.players.create!(civ: civ) }
    city(game, "Rome", 0, 10, 10)
    city(game, "Greece", 0, 30, 10)

    get game_projections_url(game)

    disclosure = disclosure_wrapping("table.capital-distances")
    assert disclosure, "capital distances table is not inside a details.disclosure"
    assert_nil disclosure["open"], "capital distances table is expanded by default"
    assert_select "details.disclosure summary", "Capital distances table"
  end

  test "show keeps the buffer cities table behind a collapsed disclosure" do
    game = pangaea_game("Collapsed Buffer Game", civs: %w[Rome Greece])
    named_city(game, "Rome", "Roma", 0, 10, 20)
    named_city(game, "Greece", "Athenai", 0, 24, 20)
    named_city(game, "Rome", "Ostia", 30, 17, 20)

    get game_projections_url(game)

    disclosure = disclosure_wrapping("table.buffer-cities")
    assert disclosure, "buffer cities table is not inside a details.disclosure"
    assert_nil disclosure["open"], "buffer cities table is expanded by default"
    assert_select "details.disclosure summary", "Buffer cities table"
  end

  test "show flags capital distances measured against an estimated map width" do
    game = Game.create!(name: "Estimated Width Game")
    %w[Rome Greece].each { |civ| game.players.create!(civ: civ) }
    city(game, "Rome", 0, 10, 10)
    city(game, "Greece", 0, 16, 10)

    get game_projections_url(game)

    assert_select ".badge", /map width estimated/
  end

  test "show keeps the empire geometry table behind a collapsed disclosure" do
    game = Game.create!(name: "Collapsed Geometry Game", map_width: 46)
    game.players.create!(civ: "Rome")
    city(game, "Rome", 1, 10, 10)
    city(game, "Rome", 5, 14, 10)

    get game_projections_url(game)

    disclosure = disclosure_wrapping("table.geometry")
    assert disclosure, "geometry table is not inside a details.disclosure"
    assert_nil disclosure["open"], "geometry table is expanded by default"
    assert_select "details.disclosure summary", "Empire geometry table"
  end

  test "show displays both sides of a corridor, the side without a buffer included" do
    game = pangaea_game("Buffer Game")
    named_city(game, "Rome", "Roma", 0, 10, 20)
    named_city(game, "Greece", "Athenai", 0, 27, 20)
    named_city(game, "Rome", "Ostia", 30, 18, 20)

    get game_projections_url(game)

    assert_response :success
    assert_select "table.buffer-cities tbody tr", 2
    assert_select "table.buffer-cities tbody tr:first-child td", "Ostia"
    assert_select "table.buffer-cities tbody tr:last-child td", "Greece"
  end

  test "show spans a pair's shared cells across its two civ rows" do
    game = pangaea_game("Buffer Span Game")
    named_city(game, "Rome", "Roma", 0, 10, 20)
    named_city(game, "Greece", "Athenai", 0, 27, 20)
    named_city(game, "Rome", "Ostia", 30, 18, 20)

    get game_projections_url(game)

    assert_select "table.buffer-cities tbody tr", 2
    assert_select "table.buffer-cities tbody td[rowspan='2']", 2
  end

  test "show badges the civilization that settled its corridor first" do
    game = pangaea_game("Buffer Race Game")
    named_city(game, "Rome", "Roma", 0, 10, 20)
    named_city(game, "Greece", "Athenai", 0, 27, 20)
    named_city(game, "Rome", "Ostia", 20, 14, 20)
    named_city(game, "Greece", "Sparta", 30, 22, 20)

    get game_projections_url(game)

    assert_select "table.buffer-cities tbody tr:first-child .badge", "first"
  end

  test "show explains that buffer cities are measured on Pangaea alone" do
    game = Game.create!(name: "Continents Game", map_script: "Continents")
    %w[Rome Greece].each { |civ| game.players.create!(civ: civ) }
    named_city(game, "Rome", "Roma", 0, 10, 20)
    named_city(game, "Greece", "Athenai", 0, 27, 20)

    get game_projections_url(game)

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

    get game_projections_url(game)

    assert_select "p", /Rome secured its corridors in this order: Egypt, Greece/
  end

  test "show displays each civilization's empire geometry" do
    game = Game.create!(name: "Geometry Game", map_width: 46)
    game.players.create!(civ: "Rome")
    city(game, "Rome", 1, 10, 10)
    city(game, "Rome", 5, 14, 10)

    get game_projections_url(game)

    assert_response :success
    assert_select "table.geometry" do
      assert_select "td", "Rome"
      assert_select "td", "2"
      assert_select "td", "4"
      assert_select "td", "4.0"
      assert_select "td", "1.0"
    end
  end

  test "show marks a civilization whose city count the timeline cannot account for" do
    game = Game.create!(name: "Razed City Game", map_width: 46)
    game.players.create!(civ: "Rome")
    city(game, "Rome", 1, 10, 10)
    snapshot(game, "Rome", 20, cities: 0)

    get game_projections_url(game)

    assert_select "table.geometry .badge", /turn 20/
  end

  test "show links to the history behind the geometry table" do
    game = Game.create!(name: "Geometry History Link Game", map_width: 46)
    game.players.create!(civ: "Rome")
    city(game, "Rome", 1, 10, 10)

    get game_projections_url(game)

    assert_select "a[href=?]", game_geometry_path(game)
  end

  test "show omits the geometry table for a game with no city coordinates" do
    game = Game.create!(name: "Coordinateless Game")
    game.players.create!(civ: "Rome")

    get game_projections_url(game)

    assert_response :success
    assert_select "table.geometry", false
  end

  test "show keeps every key moment section collapsed until it is clicked" do
    game = Game.create!(name: "Collapsed Game")
    war(game, 10)

    get game_projections_url(game)

    assert_select "details summary", "Wars (1)"
    assert_select "details[open]", false
  end

  test "show marks the direction of a happiness swing in the list" do
    game = Game.create!(name: "Swing Game", game_speed: "GAMESPEED_QUICK")
    snapshot(game, "Rome", 100, happiness: 15)
    snapshot(game, "Rome", 101, happiness: 1)

    get game_projections_url(game)

    assert_select "details li .trend--down"
  end

  test "show gathers the religion moments into one section" do
    game = Game.create!(name: "Religion Game")
    event(game, "Rome", "pantheon_founded", 5, "belief" => "BELIEF_A")
    event(game, "Rome", "reformation_added", 60, "religion" => "Christianity", "belief" => "BELIEF_B")

    get game_projections_url(game)

    assert_select "details summary", "Religion (2)"
    assert_select "details summary", text: /Pantheon/, count: 0
  end

  test "show keeps the kinds of religion moment apart inside the section" do
    game = Game.create!(name: "Religion Order Game")
    event(game, "Rome", "pantheon_founded", 5, "belief" => "BELIEF_A")
    event(game, "Rome", "reformation_added", 60, "religion" => "Christianity", "belief" => "BELIEF_B")

    get game_projections_url(game)

    assert_select "details h3", "Pantheon Foundings"
    assert_select "details h3", "Reformations"
  end

  test "show gathers cultural key moments into one section" do
    game = Game.create!(name: "Cultural Game")
    snapshot(game, "Rome", 10, influence: [ { "civ" => "Greece", "points" => 50, "level" => "INFLUENCE_LEVEL_EXOTIC", "trend" => "INFLUENCE_TREND_RISING" } ])
    snapshot(game, "Rome", 30, influence: [ { "civ" => "Greece", "points" => 320, "level" => "INFLUENCE_LEVEL_INFLUENTIAL", "trend" => "INFLUENCE_TREND_RISING" } ])

    get game_projections_url(game)

    assert_select "details summary", "Cultural Standing (1)"
    assert_match "Rome became Influential on Greece", response.body
  end

  test "show gathers Congress key moments into one section" do
    game = Game.create!(name: "Congress Game")
    event(game, nil, "congress_host_changed", 90, "old_host" => nil, "new_host" => "Rome")
    event(game, nil, "united_nations_formed", 220, {})

    get game_projections_url(game)

    assert_select "details summary", "World Congress (2)"
    assert_match "World Congress host passed from no host to Rome", response.body
    assert_match "The United Nations formed", response.body
  end

  test "show gathers victory-progress key moments into one section" do
    game = Game.create!(name: "Victory Progress Game")
    snapshot(game, "Rome", 100, spaceship: { "apollo" => 0, "booster" => 0, "cockpit" => 0, "stasis_chamber" => 0, "engine" => 0 })
    snapshot(game, "Rome", 120, spaceship: { "apollo" => 1, "booster" => 0, "cockpit" => 0, "stasis_chamber" => 0, "engine" => 0 })

    get game_projections_url(game)

    assert_select "details summary", "Victory Progress (1)"
    assert_match "Rome completed the Apollo Program", response.body
  end

  test "show gathers snowballs across every metric into one section" do
    game = Game.create!(name: "Snowball Game")
    (1..30).each do |turn|
      snapshot(game, "Rome", turn, score: turn * 10, science: turn * 10)
      snapshot(game, "Greece", turn, score: turn * 2, science: turn * 2)
    end

    get game_projections_url(game)

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

    get game_projections_url(game)

    assert_select "details h3", "Gold Per Turn"
  end

  test "show displays key moments detected from the game's events" do
    game = Game.create!(name: "War Game")
    game.game_events.create!(
      seq: 1, session_index: 0, turn: 10, event_type: "war_declared",
      payload: { "event" => "war_declared", "turn" => 10, "attacker_team" => 1,
                 "attacker_civs" => [ "Rome" ], "defender_team" => 2, "defender_civs" => [ "Greece" ] }
    )

    get game_projections_url(game)

    assert_response :success
    assert_match "Rome", response.body
    assert_match "Greece", response.body
  end

  test "show places the Wonder Races section below Early Game" do
    game = Game.create!(name: "Section Order Game")
    game.players.create!(civ: "Rome")

    get game_projections_url(game)

    assert_operator response.body.index('id="early-game"'), :<, response.body.index('id="wonder-races"')
  end

  test "show displays where each civilization's early game ends" do
    game = Game.create!(name: "Early Game Game", game_speed: "GAMESPEED_QUICK")
    game.players.create!(civ: "Rome")
    game.players.create!(civ: "Greece")
    event(game, nil, "tech_researched", 40, "team" => 1, "civs" => [ "Rome" ], "tech" => "TECH_EDUCATION")
    event(game, "Rome", "building_constructed", 60, "building" => "BUILDING_WORKSHOP", "city" => "Roma")
    snapshot(game, "Greece", 110, score: 10)

    get game_projections_url(game)

    assert_response :success
    assert_equal(
      [
        [ "Rome", "60", "milestone", "EDUCATION + WORKSHOP", "40", "60" ],
        [ "Greece", "100", "deadline", "—", "—", "—" ]
      ],
      css_select("table.early-game tbody tr").map { |row| row.css("td").map(&:text) }
    )
  end

  test "show displays what each civilization's army is made of" do
    game = Game.create!(name: "Army Game")
    game.players.create!(civ: "Rome")
    snapshot(game, "Rome", 20, military_might: 1300, military_units: 10, gold: 900)

    get game_projections_url(game)

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

    get game_projections_url(game)

    assert_select "a[href=?]", game_army_path(game)
  end

  test "show omits the army table for a game whose snapshots carry no military data" do
    game = Game.create!(name: "Peaceful Game")
    game.players.create!(civ: "Rome")
    snapshot(game, "Rome", 20, score: 100)

    get game_projections_url(game)

    assert_select "table.army", false
  end

  test "show displays each civilization's tourism and cultural standing" do
    game = Game.create!(name: "Cultural Table Game")
    game.players.create!(civ: "Rome")
    snapshot(game, "Rome", 30, tourism: 120, civs_influential_on: 1,
      influence: [ { "civ" => "Greece", "points" => 320, "level" => "INFLUENCE_LEVEL_INFLUENTIAL", "trend" => "INFLUENCE_TREND_RISING" } ])

    get game_projections_url(game)

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

    get game_projections_url(game)

    assert_select "a[href=?]", game_cultural_path(game)
  end

  test "show omits the cultural table for a game with no tourism data" do
    game = Game.create!(name: "No Culture Game")
    game.players.create!(civ: "Rome")
    snapshot(game, "Rome", 20, score: 100)

    get game_projections_url(game)

    assert_select "table.cultural", false
  end

  test "show displays World Congress host, votes needed and each civilization's delegate votes" do
    game = Game.create!(name: "Congress Table Game")
    game.players.create!(civ: "Rome")
    congress_snapshot(game, 30, host: "Rome", delegates: [ { "civ" => "Rome", "votes" => 5 } ], votes_needed: 12)

    get game_projections_url(game)

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

    get game_projections_url(game)

    assert_select "a[href=?]", game_congress_path(game)
  end

  test "show omits the Congress table for a game with no Congress data" do
    game = Game.create!(name: "No Congress Game")
    game.players.create!(civ: "Rome")

    get game_projections_url(game)

    assert_select "table.congress", false
  end

  test "show displays each civilization's capitals held and spaceship assembly" do
    game = Game.create!(name: "Victory Progress Table Game")
    game.players.create!(civ: "Rome")
    snapshot(game, "Rome", 100, capitals: %w[Rome Greece],
      spaceship: { "apollo" => 1, "booster" => 2, "cockpit" => 1, "stasis_chamber" => 0, "engine" => 1 })

    get game_projections_url(game)

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

    get game_projections_url(game)

    assert_select "a[href=?]", game_victory_progress_path(game)
  end

  test "show omits the victory progress table for a game with no capitals or spaceship data" do
    game = Game.create!(name: "No Victory Progress Game")
    game.players.create!(civ: "Rome")
    snapshot(game, "Rome", 20, score: 100)

    get game_projections_url(game)

    assert_select "table.victory-progress", false
  end

  test "show summarises what each civilization spent on espionage" do
    game = Game.create!(name: "Espionage Summary Game")
    game.players.create!(civ: "Rome")
    spy_event(game, "spy_created", "Rome", 10, spy: "ROME_1", agent: 1)
    spy_event(game, "spy_killed", "Greece", 15, spy: "GREECE_1", agent: 9, city: "Roma", city_civ: "Rome")
    spy_event(game, "spy_moved", "Rome", 5, spy: "ROME_2", agent: 2, city: "Roma", city_civ: "Rome",
              state: "counter_intel")
    spy_event(game, "spy_mission_completed", "Rome", 20, spy: "ROME_1", agent: 1, city: "Athens",
              city_civ: "Greece", state: "gathering_intel")

    get game_projections_url(game)

    assert_response :success
    assert_select "table.espionage" do
      assert_select "td", "Rome"
      assert_select "td", "1" # spies made
      assert_select "td", "1" # missions
      assert_select "td", "Yes" # garrisoned
    end
  end

  test "show links to the history behind the espionage table" do
    game = Game.create!(name: "Espionage Link Game")
    game.players.create!(civ: "Rome")
    spy_event(game, "spy_created", "Rome", 10, spy: "ROME_1", agent: 1)

    get game_projections_url(game)

    assert_select "a[href=?]", game_espionage_path(game)
  end

  test "show omits the espionage table for a game with no spy activity" do
    game = Game.create!(name: "No Espionage Game")
    game.players.create!(civ: "Rome")
    snapshot(game, "Rome", 20, score: 100)

    get game_projections_url(game)

    assert_select "table.espionage", false
  end

  test "show lists diplomatic ties between civs" do
    game = Game.create!(name: "Ties Game")
    %w[Rome Greece].each { |civ| game.players.create!(civ: civ) }
    event(game, "Rome", "embassy_established", 6, "civ" => "Rome", "other_civ" => "Greece")
    event(game, "Greece", "embassy_established", 6, "civ" => "Greece", "other_civ" => "Rome")

    get game_projections_url(game)

    assert_select "table.diplomatic-ties tbody tr td", text: "embassy"
  end

  test "show omits the diplomatic ties table for a game with no tie events" do
    game = Game.create!(name: "No Ties Game")
    game.players.create!(civ: "Rome")

    get game_projections_url(game)

    assert_select "table.diplomatic-ties", false
    assert_select "p.empty-state", /embassy/i
  end

  test "show summarises each civ's trade route destinations" do
    game = Game.create!(name: "Trade Game")
    game.players.create!(civ: "India")
    event(game, "India", "trade_route_established", 10, "from_city" => "Delhi", "to_city" => "Mumbai",
          "to_civ" => "India", "type" => "food", "turns_left" => 15)

    get game_projections_url(game)

    assert_select "table.trade-routes tbody tr td", text: "India"
  end

  test "show omits the trade routes table for a game with no trade route events" do
    game = Game.create!(name: "No Trade Game")
    game.players.create!(civ: "India")

    get game_projections_url(game)

    assert_select "table.trade-routes", false
  end

  test "show lists each city's religious holds" do
    game = Game.create!(name: "Religion Game")
    game.players.create!(civ: "India")
    event(game, "India", "city_converted", 50, "city" => "Delhi", "religion" => "TXT_KEY_RELIGION_HINDUISM")

    get game_projections_url(game)

    assert_select "table.religion-holds tbody tr td", text: "Hinduism"
  end

  test "show omits the religion tables for a game with no conversions" do
    game = Game.create!(name: "No Religion Game")
    game.players.create!(civ: "India")

    get game_projections_url(game)

    assert_select "table.religion-holds", false
  end

  test "show shows the latest yield source breakdown per civ" do
    game = Game.create!(name: "Yield Game")
    game.players.create!(civ: "India")
    snapshot(game, "India", 10, science: 40, yield_sources: { science: { cities: 40 } })

    get game_projections_url(game)

    assert_select "table.yield-attribution tbody tr td", text: "cities: 40"
  end

  test "show omits the yield attribution table for a game with no source data" do
    game = Game.create!(name: "No Yield Game")
    game.players.create!(civ: "India")

    get game_projections_url(game)

    assert_select "table.yield-attribution", false
  end

  test "show lists strategic resource deficits per civ" do
    game = Game.create!(name: "Shortage Game")
    game.players.create!(civ: "Netherlands")
    snapshot(game, "Netherlands", 81, resources: [ { "resource" => "RESOURCE_HORSE", "total" => 0, "used" => 1 } ])

    get game_projections_url(game)

    assert_select "table.resource-shortages tbody tr td", text: "Horse"
  end

  test "show names each exposed unit rather than its internal id" do
    game = Game.create!(name: "Shortage Game")
    game.players.create!(civ: "Netherlands")
    event(game, "Netherlands", "unit_created", 80, "unit" => "UNIT_HORSEMAN")
    snapshot(game, "Netherlands", 81, resources: [ { "resource" => "RESOURCE_HORSE", "total" => 0, "used" => 1 } ])

    get game_projections_url(game)

    assert_select "table.resource-shortages tbody tr td", text: "Horseman"
  end

  test "show omits the resource shortages table for a game with no deficits" do
    game = Game.create!(name: "No Shortage Game")
    game.players.create!(civ: "Netherlands")

    get game_projections_url(game)

    assert_select "table.resource-shortages", false
  end

  test "show lists confirmed resource deals" do
    game = Game.create!(name: "Deals Game")
    %w[Tibet Netherlands].each { |civ| game.players.create!(civ: civ) }
    snapshot(game, "Tibet", 19, resources: [ { "resource" => "RESOURCE_WINE", "total" => 1, "used" => 0, "import" => 0, "export" => 1 } ])
    snapshot(game, "Netherlands", 19, resources: [ { "resource" => "RESOURCE_WINE", "total" => 1, "used" => 0, "import" => 1, "export" => 0 } ])

    get game_projections_url(game)

    assert_select "table.deals tbody tr td", text: "Wine"
  end

  test "show names an unattributed import's resource rather than its internal id" do
    game = Game.create!(name: "Unattributed Import Game")
    game.players.create!(civ: "Zurich")
    snapshot(game, "Zurich", 19, resources: [ { "resource" => "RESOURCE_HORSE", "total" => 1, "used" => 0, "import" => 1, "export" => 0 } ])

    get game_projections_url(game)

    assert_select "table.deals-unattributed tbody tr td", text: "Horse"
  end

  test "show omits the deals table for a game with no resource flow data" do
    game = Game.create!(name: "No Deals Game")
    game.players.create!(civ: "Tibet")

    get game_projections_url(game)

    assert_select "table.deals", false
  end

  test "show lists city-state traits and alliances" do
    game = Game.create!(name: "City-State Game")
    game.players.create!(civ: "India")
    event(game, nil, "session_started", 0, "city_states" => [ { "civ" => "Ljubljana", "trait" => "cultured" } ])
    event(game, nil, "city_state_snapshot", 48, "city_state" => "Ljubljana",
          "relations" => [ { "civ" => "India", "influence" => 5, "per_turn" => 1.25 } ])

    get game_projections_url(game)

    assert_select "table.city-state-traits tbody tr td", text: "Ljubljana"
  end

  test "show names a city-state's trait, personality and unique unit rather than their internal ids" do
    game = Game.create!(name: "City-State Naming Game")
    game.players.create!(civ: "India")
    event(game, nil, "session_started", 0, "city_states" => [
      { "civ" => "Ljubljana", "trait" => "MINOR_TRAIT_CULTURED", "personality" => "MINOR_CIV_PERSONALITY_THEOCRATIC",
        "unique_unit" => "UNIT_HORSEMAN" }
    ])
    event(game, nil, "city_state_snapshot", 48, "city_state" => "Ljubljana",
          "relations" => [ { "civ" => "India", "influence" => 5, "per_turn" => 1.25 } ])

    get game_projections_url(game)

    assert_select "table.city-state-traits tbody tr" do
      assert_select "td", text: "Cultured"
      assert_select "td", text: "Theocratic"
      assert_select "td", text: "Horseman"
    end
  end

  test "show omits the city-state tables for a game with no city-state snapshots" do
    game = Game.create!(name: "No City-State Game")
    game.players.create!(civ: "India")

    get game_projections_url(game)

    assert_select "table.city-state-traits", false
  end

  test "show lists wonder races among the key moments" do
    game = wonder_race_game("Wonder Moments Game")

    get game_projections_url(game)

    assert_select "details summary", "Wonder Races (2)"
    assert_select "details li", /England lost the race for Louvre to Netherlands/
  end

  test "show tabulates each contested wonder and the civ that lost it" do
    game = wonder_race_game("Wonder Table Game")

    get game_projections_url(game)

    assert_select "table.wonder-races tbody td", "Louvre"
    assert_select "table.wonder-races tbody td", text: /England \(London\)/
    assert_select "table.wonder-races tbody td", "lost"
  end

  test "show groups the contenders of a multi-way race under one spanning wonder cell" do
    game = Game.create!(name: "Two Rival Wonder Game")
    (40..50).each do |t|
      event(game, "England", "city_snapshot", t, "city" => "London", "producing" => "BUILDING_GREAT_WALL",
            "producing_kind" => "wonder", "production_stored" => t, "production_turns_left" => 1)
      %w[Zimbabwe Iroquois].each do |civ|
        event(game, civ, "city_snapshot", t, "city" => "#{civ} City", "producing" => "BUILDING_GREAT_WALL",
              "producing_kind" => "wonder", "production_stored" => t * 2, "production_turns_left" => 3)
      end
    end
    event(game, "England", "building_constructed", 51, "city" => "London",
          "building" => "BUILDING_GREAT_WALL", "wonder" => "world")

    get game_projections_url(game)

    assert_select "table.wonder-races tbody td[rowspan='2']", text: "Great Wall"
    assert_select "table.wonder-races tbody tr", 2
  end

  test "show explains that wonder races need city snapshots" do
    game = Game.create!(name: "No Snapshot Wonder Game")
    war(game, 10)

    get game_projections_url(game)

    assert_select "table.wonder-races", false
    assert_select "p.empty-state", /city snapshot/i
  end

  test "show gathers a player ruled out of contention into its own key moment section" do
    game = Game.create!(name: "Irrelevance Game")
    event(game, nil, "mp_proposal_result", 120,
      "type" => "irrelevance", "status" => "passed",
      "owner" => "Rome", "subject" => "Rome", "yes_votes" => 4, "no_votes" => 0)

    get game_projections_url(game)

    assert_select "details summary", "Players Declared Irrelevant (1)"
    assert_match "Rome asked to be ruled out of contention", response.body
  end

  test "show gives each major section a self-linking anchor" do
    game = Game.create!(name: "Anchored Game")
    game.players.create!(civ: "Rome")

    get game_projections_url(game)

    %w[early-game wonder-races military cultural-standing world-congress
       victory-progress key-moments].each do |id|
      assert_select "h2##{id} a.heading-anchor[href=?]", "##{id}"
    end
  end

  private

  def pangaea_game(name, civs: %w[Rome Greece])
    game = Game.create!(name: name, map_script: "Pangaea")
    civs.each { |civ| game.players.create!(civ: civ) }
    game
  end

  def disclosure_wrapping(selector)
    css_select("details.disclosure").find { |node| node.css(selector).any? }
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

  def wonder_race_game(name)
    game = Game.create!(name: name)
    (48..57).each do |t|
      event(game, "England", "city_snapshot", t, "city" => "London", "producing" => "BUILDING_LOUVRE",
            "producing_kind" => "wonder", "production_stored" => t == 57 ? 425 : (t - 48) * 40,
            "production_turns_left" => 58 - t)
    end
    (54..57).each do |t|
      event(game, "Netherlands", "city_snapshot", t, "city" => "Amsterdam", "producing" => "BUILDING_LOUVRE",
            "producing_kind" => "wonder", "production_stored" => 120 * (t - 53), "production_turns_left" => 1)
    end
    event(game, "Netherlands", "building_constructed", 58, "city" => "Amsterdam",
          "building" => "BUILDING_LOUVRE", "wonder" => "world")
    game
  end

  def congress_snapshot(game, turn, host:, delegates:, votes_needed:)
    game.game_events.create!(
      seq: game.game_events.count + 1, session_index: 0, turn: turn, event_type: "congress_snapshot", civ: nil,
      payload: { "event" => "congress_snapshot", "turn" => turn, "host" => host,
                 "delegates" => delegates, "votes_needed_for_diplo_victory" => votes_needed }
    )
  end

  def spy_event(game, type, civ, turn, spy:, agent: nil, city: nil, city_civ: nil, state: nil)
    payload = { "spy" => spy }
    payload["agent"] = agent if agent
    payload.merge!("city" => city, "city_civ" => city_civ) if city
    payload["state"] = state if state
    event(game, civ, type, turn, payload)
  end

  def snapshot(game, civ, turn, metrics)
    game.game_events.create!(
      seq: game.game_events.count + 1, session_index: 0, turn: turn, event_type: "snapshot", civ: civ,
      payload: metrics.stringify_keys.merge("event" => "snapshot", "turn" => turn, "civ" => civ)
    )
  end
end
