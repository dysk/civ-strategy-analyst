require "digest"
require "json"
require "set"

class ImportGame
  # Every event the logger emits. test/fixtures/files/logger_event_types.jsonl
  # carries one line per name, so a type added there and forgotten here fails a
  # test instead of drowning the import log in warnings.
  KNOWN_EVENT_TYPES = %w[
    session_started snapshot city_snapshot logger_error
    unit_created unit_trained unit_lost unit_killed unit_promoted unit_upgraded
    unit_rebased paradrop
    city_founded city_captured city_destroyed city_converted population_changed
    building_constructed building_sold project_completed
    plot_acquired plot_bought improvement_built improvement_pillaged
    tech_researched tech_from_ruins era_entered golden_age_started
    policy_adopted policy_branch_unlocked policy_branch_adopted
    great_person_expended natural_wonder_discovered globe_circumnavigated
    pantheon_founded religion_founded religion_enhanced reformation_added
    trade_route_plundered nuclear_detonation
    teams_met war_declared peace_made diplo_event player_eliminated game_ended
    friendship_declared friendship_ended
    defensive_pact_signed defensive_pact_ended
    trade_agreement_signed trade_agreement_ended
    open_borders_granted open_borders_revoked
    embassy_established embassy_ended
    city_state_friendship_changed city_state_ally_changed
    city_state_alliance_changed
    congress_snapshot congress_founded congress_host_changed
    resolution_proposed resolution_passed resolution_failed
    resolution_undetermined resolution_repealed
    mp_vote mp_proposal_result united_nations_formed
  ].freeze

  Result = Struct.new(:game, :imported_count, :skipped_count, :logger_error_count, keyword_init: true)

  # Rows are written in batches rather than one at a time: a full game is
  # tens of thousands of records, most of them city snapshots.
  BATCH_SIZE = 1000

  def self.call(path, name: nil, lekmod_version: nil)
    new(path, name: name, lekmod_version: lekmod_version).call
  end

  def initialize(path, name: nil, lekmod_version: nil)
    @path = path.to_s
    @name = name.presence || File.basename(@path, ".*")
    @lekmod_version = lekmod_version
  end

  def call
    game = Game.create!(name: @name, completed: false, lekmod_version: @lekmod_version)

    @session_index = -1
    @seq = 0
    @imported_count = 0
    @skipped_count = 0
    @logger_error_count = 0
    @rows = []
    @signatures_from_earlier_sessions = Set.new
    @signatures_in_current_session = Set.new

    File.foreach(@path).with_index(1) do |line, line_number|
      import_line(game, line, line_number)
    end
    flush_rows

    Result.new(
      game: game,
      imported_count: @imported_count,
      skipped_count: @skipped_count,
      logger_error_count: @logger_error_count
    )
  end

  private

  def import_line(game, line, line_number)
    line = line.strip
    return if line.empty?

    payload = JSON.parse(line)
    event_type = payload["event"]

    unless KNOWN_EVENT_TYPES.include?(event_type)
      Rails.logger.warn("ImportGame: unknown event type '#{event_type}' at line #{line_number}")
    end

    handle_session_boundary(game, payload) if event_type == "session_started"
    return if logger_failure?(event_type)

    signature = signature_of(payload)
    return if duplicate_of_earlier_session?(signature)

    @signatures_in_current_session << signature
    buffer_event(game, payload, event_type)
  rescue JSON::ParserError => e
    Rails.logger.warn("ImportGame: skipping malformed line #{line_number}: #{e.message}")
  end

  # A logger_error is the logger reporting that one of its own extractors
  # threw. It is not a fact about the game, and it carries no turn, so the
  # table has no room for it either. The count is what matters.
  def logger_failure?(event_type)
    return false unless event_type == "logger_error"

    @logger_error_count += 1
    true
  end

  def handle_session_boundary(game, payload)
    @signatures_from_earlier_sessions.merge(@signatures_in_current_session)
    @signatures_in_current_session = Set.new
    @session_index += 1

    return unless @session_index.zero?

    apply_game_settings(game, payload)
    create_players(game, payload["players"])
  end

  # A reload replays turns, so the same fact is written again. What decides
  # sameness is the record without t_log: that field is the engine's clock,
  # which restarts with the process and differs on every replay. Digesting
  # the rest keeps a short string per record instead of a whole payload,
  # and the logger writes its keys sorted, so equal records serialise to
  # equal strings.
  def signature_of(payload)
    Digest::SHA256.hexdigest(payload.except("t_log").to_json)
  end

  def duplicate_of_earlier_session?(signature)
    return false unless @session_index.positive?

    @signatures_from_earlier_sessions.include?(signature).tap do |duplicate|
      @skipped_count += 1 if duplicate
    end
  end

  def buffer_event(game, payload, event_type)
    @seq += 1
    now = Time.current
    @rows << {
      game_id: game.id,
      seq: @seq,
      session_index: @session_index,
      turn: payload["turn"],
      event_type: event_type,
      civ: payload["civ"],
      payload: payload,
      created_at: now,
      updated_at: now
    }
    @imported_count += 1
    flush_rows if @rows.size >= BATCH_SIZE
  end

  def flush_rows
    return if @rows.empty?

    GameEvent.insert_all(@rows)
    @rows = []
  end

  def apply_game_settings(game, payload)
    game.update!(
      map_script: payload["map_script"],
      map_size: payload["map_size"],
      map_width: payload["map_width"],
      map_height: payload["map_height"],
      game_speed: payload["game_speed"],
      max_turns: payload["max_turns"],
      start_era: payload["start_era"]
    )
  end

  def create_players(game, players)
    Array(players).each do |player|
      game.players.create!(
        civ: player["civ"],
        leader_name: player["name"],
        human: player["human"],
        handicap: player["handicap"]
      )
    end
  end
end
