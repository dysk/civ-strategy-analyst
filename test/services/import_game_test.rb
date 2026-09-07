require "test_helper"

class ImportGameTest < ActiveSupport::TestCase
  SAMPLE_PATH = Rails.root.join("test/fixtures/files/sample_game.jsonl")
  DEDUP_FRAGMENT_PATH = Rails.root.join("test/fixtures/files/dedup_fragment.jsonl")
  EVENT_TYPES_FIXTURE_PATH = Rails.root.join("test/fixtures/files/logger_event_types.jsonl")
  LOGGER_EVENT_TYPES_PATH = Rails.root.join("../civ-narrative-logger/dist/event-types.json")

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

  test "records the map dimensions when the log reports them" do
    game = ImportGame.call(SAMPLE_PATH, name: "Test Game").game

    assert_equal 48, game.map_width
    assert_equal 42, game.map_height
  end

  # The logger generates dist/event-types.json from the records its own suite
  # watches it write, so that file is the authority on what arrives here.
  # KNOWN_EVENT_TYPES is a copy of it and this is what catches the copy going
  # stale - twice now it has, silently, one warning per imported line.
  test "knows exactly the event types the logger publishes" do
    unless File.exist?(LOGGER_EVENT_TYPES_PATH)
      skip "civ-narrative-logger is not checked out beside this repository"
    end

    published = JSON.parse(File.read(LOGGER_EVENT_TYPES_PATH))

    assert_equal published.sort, ImportGame::KNOWN_EVENT_TYPES.sort
  end

  test "the event type fixture carries one line per known type" do
    events = File.readlines(EVENT_TYPES_FIXTURE_PATH).map { JSON.parse(_1)["event"] }

    assert_equal ImportGame::KNOWN_EVENT_TYPES.sort, events.sort
  end

  # One line per event the logger emits today. When the logger grows a new
  # record, this fixture and KNOWN_EVENT_TYPES are what has to grow with it.
  test "recognises every event type the logger emits" do
    io = StringIO.new
    original_logger = Rails.logger
    Rails.logger = Logger.new(io)

    ImportGame.call(EVENT_TYPES_FIXTURE_PATH, name: "Test Game")

    refute_match(/unknown event type/, io.string)
  ensure
    Rails.logger = original_logger
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

    # 7 lines in the fixture, 1 is malformed JSON and skipped entirely (not a dedup skip)
    assert_equal 6, result.imported_count
    assert_equal 0, result.skipped_count
  end

  # Every record now carries t_log, the engine's own clock, which restarts
  # with the process. A replayed event is the same fact at a different
  # second, so the clock cannot take part in deciding what is a duplicate.
  test "deduplicates a replayed event whose only difference is the log clock" do
    result = ImportGame.call(Rails.root.join("test/fixtures/files/reloaded_with_clock.jsonl"), name: "Reloaded")

    assert_equal 1, result.skipped_count
    assert_equal 1, result.game.game_events.where(event_type: "city_founded").count
  end

  # logger_error is the logger reporting its own failure, and it carries no
  # turn, so it does not even fit the table.
  test "keeps logger failures out of the game's events and counts them" do
    result = ImportGame.call(Rails.root.join("test/fixtures/files/logger_failure.jsonl"), name: "Broken Logger")

    refute result.game.game_events.exists?(event_type: "logger_error")
    assert result.game.game_events.exists?(event_type: "city_founded")
    assert_equal 1, result.logger_error_count
  end

  test "numbers events contiguously across insert batches" do
    path = Tempfile.new([ "long_game", ".jsonl" ])
    path.puts(File.readlines(SAMPLE_PATH).first)
    2500.times { |i| path.puts({ event: "unit_created", turn: i, civ: "Rome", unit: "UNIT_WARRIOR", n: i }.to_json) }
    path.close

    result = ImportGame.call(path.path, name: "Long Game")
    events = result.game.game_events.order(:seq)

    assert_equal 2501, result.imported_count
    assert_equal (1..2501).to_a, events.pluck(:seq)
    assert_equal (0...2500).to_a, events.where(event_type: "unit_created").pluck(:turn)
  ensure
    path&.unlink
  end

  test "stores the given lekmod_version on the game" do
    result = ImportGame.call(SAMPLE_PATH, name: "Test Game", lekmod_version: "34.15")

    assert_equal "34.15", result.game.lekmod_version
  end

  test "leaves lekmod_version nil when not given" do
    result = ImportGame.call(SAMPLE_PATH, name: "Test Game")

    assert_nil result.game.lekmod_version
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

  # The logger now ends the game with a record of its own, so the winner is
  # read rather than inferred. VICTORY_SPACE_RACE is the logger's id for what
  # the rest of the codebase already calls a science victory.
  test "writes the winner, victory type and completion from game_ended" do
    game = import_with_ending(
      { event: "game_ended", turn: 300, victory: "VICTORY_SPACE_RACE",
        winner_civs: [ "Rome" ], winner_team: 1, winning_turn: 300 }
    )

    assert game.completed?
    assert_equal "Rome", game.winner_civ
    assert_equal [ "Rome" ], game.winner_civs
    assert_equal "science", game.victory_type
  end

  # winner_civs is an array because a team can win together; flattening it to
  # one civ would lose the other members of the winning team.
  test "keeps every civ of a team victory, with winner_civ as the first" do
    game = import_with_ending(
      { event: "game_ended", turn: 250, victory: "VICTORY_DOMINATION",
        winner_civs: [ "Rome", "Carthage" ], winner_team: 1, winning_turn: 250 }
    )

    assert_equal [ "Rome", "Carthage" ], game.winner_civs
    assert_equal "Rome", game.winner_civ
    assert_equal "domination", game.victory_type
  end

  # A passed scrap vote sets VICTORY_SCRAP with an arbitrary winner_team - the
  # client that happened to resolve the vote - so the game is over but nobody
  # won it, and the meaningless winner must not be stored or later inferred.
  test "records a scrap vote as a completed game with no winner" do
    game = import_with_ending(
      { event: "game_ended", turn: 140, victory: "VICTORY_SCRAP",
        winner_civs: [ "Greece" ], winner_team: 0, winning_turn: 140 }
    )

    assert game.completed?
    assert_nil game.winner_civ
    assert_nil game.winner_civs
    assert_equal "scrapped", game.victory_type
  end

  test "leaves the game in progress when no game_ended is logged" do
    game = ImportGame.call(SAMPLE_PATH, name: "Test Game").game

    refute game.completed?
    assert_nil game.winner_civ
    assert_nil game.winner_civs
    assert_nil game.victory_type
  end

  # Reading the winner off game_ended must not consume the event: the key
  # moment detector and the chronicle spine read it too.
  test "still persists the game_ended event itself" do
    game = import_with_ending(
      { event: "game_ended", turn: 300, victory: "VICTORY_SPACE_RACE",
        winner_civs: [ "Rome" ], winner_team: 1, winning_turn: 300 }
    )

    assert game.game_events.exists?(event_type: "game_ended")
  end

  private

  # The first line of the sample fixture is a session_started; append an
  # ending to it and import the pair.
  def import_with_ending(ending)
    path = Tempfile.new([ "ended_game", ".jsonl" ])
    path.puts(File.readlines(SAMPLE_PATH).first)
    path.puts(ending.to_json)
    path.close

    ImportGame.call(path.path, name: "Ended Game").game
  ensure
    path&.close!
  end
end
