require "test_helper"

class CongressHistoriesControllerTest < ActionDispatch::IntegrationTest
  setup do
    @game = Game.create!(name: "Congress History Game")
    @game.players.create!(civ: "Rome")
  end

  test "lists the host and votes needed at each Congress snapshot" do
    congress_snapshot(10, host: "Rome", delegates: [], votes_needed: 12)
    congress_snapshot(40, host: "Greece", delegates: [], votes_needed: 14)

    get game_congress_url(@game)

    assert_response :success
    assert_select "table.congress-sessions tbody tr", 2
    assert_select "table.congress-sessions tbody tr:last-child td", "Greece"
  end

  test "lists each civilization's delegate votes over time" do
    congress_snapshot(10, host: "Rome", delegates: [ { "civ" => "Rome", "votes" => 3 } ], votes_needed: 12)
    congress_snapshot(40, host: "Rome", delegates: [ { "civ" => "Rome", "votes" => 5 } ], votes_needed: 12)

    get game_congress_url(@game)

    assert_response :success
    assert_select "h2", "Rome"
    assert_select "table.delegates tbody tr", 2
  end

  test "lists every resolution's lifecycle" do
    event("resolution_proposed", 10, "resolution" => "RESOLUTION_WORLD_FAIR", "proposer" => "Rome", "repeal" => false)
    event("resolution_passed", 15, "resolution" => "RESOLUTION_WORLD_FAIR")

    get game_congress_url(@game)

    assert_response :success
    assert_select "table.resolutions tbody tr", 1
    assert_select "table.resolutions tbody td", "RESOLUTION_WORLD_FAIR"
    assert_select "table.resolutions tbody td", "Rome"
    assert_select "table.resolutions tbody td", "passed"
  end

  # "pending" is what an undecided vote looks like; a vote that concluded
  # with an outcome we could not read has to look different.
  test "distinguishes an unreadable outcome from a vote still in progress" do
    event("resolution_proposed", 10, "resolution" => "RESOLUTION_CHANGE_LEAGUE_HOST", "proposer" => "Rome", "repeal" => false)
    event("resolution_undetermined", 15, "resolution" => "RESOLUTION_CHANGE_LEAGUE_HOST")

    get game_congress_url(@game)

    assert_response :success
    assert_select "table.resolutions tbody td", "undetermined"
  end

  test "reports no data for a game with no Congress activity" do
    get game_congress_url(@game)

    assert_response :success
    assert_select ".empty-state"
  end

  test "links back to the game" do
    congress_snapshot(10, host: "Rome", delegates: [], votes_needed: 12)

    get game_congress_url(@game)

    assert_select "a[href=?]", game_path(@game)
  end

  test "404s for an unknown game id" do
    get game_congress_url(game_id: 999_999)

    assert_response :not_found
  end

  private

  def congress_snapshot(turn, host:, delegates:, votes_needed:)
    @game.game_events.create!(
      seq: @game.game_events.count + 1, session_index: 0, turn: turn, event_type: "congress_snapshot", civ: nil,
      payload: { "event" => "congress_snapshot", "turn" => turn, "host" => host,
                 "delegates" => delegates, "votes_needed_for_diplo_victory" => votes_needed }
    )
  end

  def event(event_type, turn, extra)
    @game.game_events.create!(
      seq: @game.game_events.count + 1, session_index: 0, turn: turn, event_type: event_type, civ: nil,
      payload: extra.merge("event" => event_type, "turn" => turn)
    )
  end
end
