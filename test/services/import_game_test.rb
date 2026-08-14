require "test_helper"

class ImportGameTest < ActiveSupport::TestCase
  SAMPLE_PATH = Rails.root.join("test/fixtures/files/sample_game.jsonl")
  DEDUP_FRAGMENT_PATH = Rails.root.join("test/fixtures/files/dedup_fragment.jsonl")

  test "creates a game with settings from the first session_started" do
    result = ImportGame.call(SAMPLE_PATH, name: "Test Game")

    game = result.game
    assert_equal "Test Game", game.name
    assert_equal "TestMap", game.map_script
    assert_equal "WORLDSIZE_SMALL", game.map_size
    assert_equal "GAMESPEED_QUICK", game.game_speed
    assert_equal 100, game.max_turns
    assert_equal "ERA_ANCIENT", game.start_era
  end

  test "defaults the game name to the file basename when not given" do
    result = ImportGame.call(SAMPLE_PATH)

    assert_equal "sample_game", result.game.name
  end

  test "creates players from the roster in the first session_started" do
    result = ImportGame.call(SAMPLE_PATH, name: "Test Game")

    civs = result.game.players.pluck(:civ)
    assert_equal %w[Rome Greece], civs

    rome = result.game.players.find_by(civ: "Rome")
    assert_equal "Augustus", rome.leader_name
    assert_equal true, rome.human
    assert_equal "HANDICAP_PRINCE", rome.handicap
  end

  test "persists events with type, turn, civ and payload, in file order" do
    result = ImportGame.call(SAMPLE_PATH, name: "Test Game")

    events = result.game.game_events.order(:seq)
    tech_event = events.find_by(event_type: "tech_researched")

    assert_equal 1, tech_event.turn
    assert_equal "Rome", tech_event.civ
    assert_equal "TECH_POTTERY", tech_event.payload["tech"]
    assert_equal 0, tech_event.session_index

    assert_operator tech_event.seq, :<, events.find_by(event_type: "city_founded").seq
  end

  test "skips malformed JSON lines without raising" do
    result = ImportGame.call(SAMPLE_PATH, name: "Test Game")

    assert result.game.game_events.exists?(event_type: "city_founded")
  end

  test "imports unknown event types instead of raising" do
    result = ImportGame.call(SAMPLE_PATH, name: "Test Game")

    assert result.game.game_events.exists?(event_type: "some_future_event_type")
  end

  test "logs a warning for unknown event types" do
    io = StringIO.new
    original_logger = Rails.logger
    Rails.logger = Logger.new(io)

    ImportGame.call(SAMPLE_PATH, name: "Test Game")

    assert_match(/some_future_event_type/, io.string)
  ensure
    Rails.logger = original_logger
  end

  test "reports how many events were imported and skipped" do
    result = ImportGame.call(SAMPLE_PATH, name: "Test Game")

    # 6 lines in the fixture, 1 is malformed JSON and skipped entirely (not a dedup skip)
    assert_equal 5, result.imported_count
    assert_equal 0, result.skipped_count
  end

  test "increments session_index on each session_started and only builds the roster once" do
    result = ImportGame.call(DEDUP_FRAGMENT_PATH, name: "Real Fragment")

    assert_equal 4, result.game.players.count
    assert_equal %w[Bolivia Chile Iroquois Vietnam], result.game.players.pluck(:civ).sort

    session_indices = result.game.game_events.distinct.pluck(:session_index).sort
    assert_equal [ 0, 1 ], session_indices
  end

  test "deduplicates events that are identical to ones from an earlier session" do
    result = ImportGame.call(DEDUP_FRAGMENT_PATH, name: "Real Fragment")

    assert_equal 62, result.imported_count
    assert_equal 40, result.skipped_count
    assert_equal 62, result.game.game_events.count

    # This exact event appears once in the first session and is replayed once
    # more after the restart; only the first-session occurrence should remain.
    duplicated = result.game.game_events.where(
      event_type: "city_converted", turn: 149, civ: "Chile"
    )
    assert_equal 1, duplicated.count
    assert_equal 0, duplicated.first.session_index

    # This one is legitimately duplicated twice within the *same* session
    # (session_index 0) before the restart, so both copies are kept.
    legitimate_duplicate = result.game.game_events.where(
      event_type: "city_converted", turn: 149, civ: "Iroquois", session_index: 0
    )
    assert_equal 2, legitimate_duplicate.count
  end
end
