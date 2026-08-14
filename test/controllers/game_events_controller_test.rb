require "test_helper"

class GameEventsControllerTest < ActionDispatch::IntegrationTest
  test "index displays raw payloads for each game event in sequence order" do
    game = Game.create!(name: "Raw Events Game")
    game.game_events.create!(
      seq: 1, session_index: 0, turn: 1, event_type: "tech_researched", civ: "Rome",
      payload: { "event" => "tech_researched", "civ" => "Rome", "tech" => "TECH_POTTERY", "turn" => 1 }
    )
    game.game_events.create!(
      seq: 2, session_index: 0, turn: 2, event_type: "city_founded", civ: "Greece",
      payload: { "event" => "city_founded", "civ" => "Greece", "city" => "Athens", "turn" => 2 }
    )

    get game_events_url(game)

    assert_response :success
    assert_match "TECH_POTTERY", response.body
    assert_match "Athens", response.body
    assert_operator response.body.index("TECH_POTTERY"), :<, response.body.index("Athens")
  end

  test "index 404s for an unknown game id" do
    get game_events_url(game_id: 999_999)

    assert_response :not_found
  end

  test "index paginates events, showing only the first page by default" do
    game = create_events(Game.create!(name: "Paginated Game"), GameEventsController::PER_PAGE + 5)

    get game_events_url(game)

    assert_response :success
    assert_select "tbody tr", count: GameEventsController::PER_PAGE
    assert_select "a", text: "Next"
    assert_select "a", text: "Last"
    assert_select "a", text: "Previous", count: 0
    assert_select "a", text: "First", count: 0
  end

  test "index shows the requested page" do
    game = create_events(Game.create!(name: "Paginated Game"), GameEventsController::PER_PAGE + 5)

    get game_events_url(game, page: 2)

    assert_response :success
    assert_select "tbody tr", count: 5
    assert_select "a", text: "Previous"
    assert_select "a", text: "First"
    assert_select "a", text: "Next", count: 0
    assert_select "a", text: "Last", count: 0
  end

  private

  def create_events(game, count)
    count.times do |i|
      game.game_events.create!(
        seq: i + 1, session_index: 0, turn: i + 1, event_type: "tech_researched",
        payload: { "event" => "tech_researched", "turn" => i + 1 }
      )
    end
    game
  end
end
