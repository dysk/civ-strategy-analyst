require "test_helper"

class CityCensusesControllerTest < ActionDispatch::IntegrationTest
  setup do
    @game = Game.create!(name: "City Value History Game")
    @game.players.create!(civ: "Rome")
  end

  test "samples a city's value every ten turns rather than listing every snapshot" do
    (1..25).each { |turn| city_snapshot("Rome", turn, "Roma", population: turn) }

    get game_city_census_url(@game)

    assert_response :success
    assert_select "table.city-value-history tbody tr", 3
  end

  test "always ends on the last turn recorded" do
    (1..25).each { |turn| city_snapshot("Rome", turn, "Roma", population: turn) }

    get game_city_census_url(@game)

    assert_select "table.city-value-history tbody tr:last-child td", "25"
  end

  test "names the civilization and city each table belongs to" do
    @game.players.create!(civ: "Greece")
    city_snapshot("Rome", 10, "Roma", population: 10)
    city_snapshot("Greece", 10, "Athens", population: 10)

    get game_city_census_url(@game)

    assert_select "h2", "Rome"
    assert_select "h3", "Roma"
    assert_select "h2", "Greece"
    assert_select "h3", "Athens"
  end

  test "carries a city's history under its current owner across a capture" do
    @game.players.create!(civ: "England")
    city_snapshot("Rome", 10, "Roma", population: 10)
    city_snapshot("England", 20, "Roma", population: 6)

    get game_city_census_url(@game)

    assert_select "h2", text: "England", count: 1
    assert_select "h2", text: "Rome", count: 0
    assert_select "h3", "Roma"
    assert_select "table.city-value-history td", "Rome"
    assert_select "table.city-value-history td", "England"
  end

  test "leaves out a civilization with no city snapshot" do
    @game.players.create!(civ: "Greece")
    city_snapshot("Rome", 10, "Roma", population: 10)

    get game_city_census_url(@game)

    assert_select "h2", text: "Greece", count: 0
  end

  test "links back to the game" do
    city_snapshot("Rome", 10, "Roma", population: 10)

    get game_city_census_url(@game)

    assert_select "a[href=?]", game_path(@game)
  end

  test "404s for an unknown game id" do
    get game_city_census_url(game_id: 999_999)

    assert_response :not_found
  end

  private

  def within_h2(text)
    node = css_select("h2").find { |h2| h2.text == text }
    yield Nokogiri::HTML::DocumentFragment.parse(node.to_s) if node
  end

  def city_snapshot(civ, turn, city, population:)
    @game.game_events.create!(
      seq: @game.game_events.count + 1, session_index: 0, turn: turn, event_type: "city_snapshot", civ: civ,
      payload: { "event" => "city_snapshot", "turn" => turn, "civ" => civ, "city" => city,
                 "population" => population }
    )
  end
end
