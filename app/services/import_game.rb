require "json"
require "set"

class ImportGame
  KNOWN_EVENT_TYPES = %w[
    session_started snapshot unit_created unit_lost plot_acquired plot_bought
    improvement_built building_constructed population_changed unit_trained
    city_converted tech_researched unit_killed unit_promoted
    city_state_friendship_changed unit_upgraded policy_adopted teams_met
    city_state_ally_changed city_state_alliance_changed great_person_expended
    city_founded city_captured improvement_pillaged golden_age_started war_declared
    peace_made natural_wonder_discovered era_entered policy_branch_unlocked
    policy_branch_adopted religion_founded pantheon_founded tech_from_ruins
    religion_enhanced trade_route_plundered reformation_added
    congress_snapshot congress_founded congress_host_changed resolution_proposed
    resolution_passed resolution_failed resolution_undetermined
    resolution_repealed united_nations_formed
    nuclear_detonation
  ].freeze

  Result = Struct.new(:game, :imported_count, :skipped_count, keyword_init: true)

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
    @signatures_from_earlier_sessions = Set.new
    @signatures_in_current_session = Set.new

    File.foreach(@path).with_index(1) do |line, line_number|
      import_line(game, line, line_number)
    end

    Result.new(game: game, imported_count: @imported_count, skipped_count: @skipped_count)
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

    return if duplicate_of_earlier_session?(payload)

    @signatures_in_current_session << payload
    persist_event(game, payload, event_type)
  rescue JSON::ParserError => e
    Rails.logger.warn("ImportGame: skipping malformed line #{line_number}: #{e.message}")
  end

  def handle_session_boundary(game, payload)
    @signatures_from_earlier_sessions.merge(@signatures_in_current_session)
    @signatures_in_current_session = Set.new
    @session_index += 1

    return unless @session_index.zero?

    apply_game_settings(game, payload)
    create_players(game, payload["players"])
  end

  def duplicate_of_earlier_session?(payload)
    return false unless @session_index.positive?

    @signatures_from_earlier_sessions.include?(payload).tap do |duplicate|
      @skipped_count += 1 if duplicate
    end
  end

  def persist_event(game, payload, event_type)
    @seq += 1
    game.game_events.create!(
      seq: @seq,
      session_index: @session_index,
      turn: payload["turn"],
      event_type: event_type,
      civ: payload["civ"],
      payload: payload
    )
    @imported_count += 1
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
