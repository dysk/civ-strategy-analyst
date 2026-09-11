require "test_helper"

# How much work one digest build repeats.
#
# A projection reads the log and indexes it when it is built, so the same
# work is paid for once per read and once per build. Both counts are growing:
# more players and longer games mean more events, per-city snapshots and the
# projections built on them mean more readers. Bounding the repetition here
# keeps the two from multiplying.
class DigestBuilderCostTest < ActiveSupport::TestCase
  CIVS = %w[Rome Greece Egypt].freeze
  TURNS = (1..20).freeze
  MAX_EVENT_LOG_PASSES = 2

  # A digest is read by an LLM with a finite window, so its size is a budget
  # like the two above, and bytes per turn per civ is the measure that moves
  # least: five games between 20 and 203 turns and 3 and 6 civs land between
  # 86 and 187 - espionage-test at 86, chile-vs-vietnam at 140, india-diplo
  # at 145, babylon-domination at 153, this fixture at 187. Counting events
  # instead spreads twice as wide.
  #
  # The fixture sits at the top of that band because it is short. Most of a
  # digest is per civ rather than per turn, and `CHECKPOINT_INTERVAL` means
  # twenty turns pay for a whole checkpoint against very few turns to divide
  # it by: grown to forty turns the same fixture costs only 34 more bytes per
  # turn per civ at the margin. So the constant is calibrated on the fixture,
  # not on the real logs, and 250 is that 187 with room to grow into.
  #
  # What this catches is the mistake the checkpoint sampling exists to
  # prevent: a section carrying a row per city per turn scales with the
  # product and crosses this immediately, while one carrying a row per war,
  # per race or per capture does not move it at all.
  MAX_DIGEST_BYTES_PER_TURN_PER_CIV = 250
  PROJECTIONS = [
    MetricSeries, PlayerTimeline, SpaceshipTimeline, MapBounds, EarlyGame,
    CapitalsTimeline, CapitalProximity, BufferCities, InfluenceTimeline,
    CongressTimeline, EmpireGeometry, ArmyComposition, WonderRaces, CityValue,
    Espionage, TradeRoutes
  ].freeze

  # Capital distances are measured twice on purpose: once on the wrapped map,
  # and once flat for the corridor between two capitals, which no army can
  # reach around the seam. Two maps, two projections.
  BUILDS_ALLOWED = Hash.new(1).merge(CapitalProximity => 2).freeze

  setup do
    @game = Game.create!(
      name: "Cost Test Game", map_script: "Pangaea", map_size: "SMALL",
      game_speed: "QUICK", max_turns: 40, start_era: "ERA_ANCIENT"
    )
    @seq = 0
    CIVS.each { |civ| @game.players.create!(civ: civ, leader_name: "#{civ} Leader", human: false) }
    populate_event_log
  end

  test "reads the event log at most twice over a full digest build" do
    rows = measure_event_loading { DigestBuilder.new(@game).call }
    budget = @game.game_events.count * MAX_EVENT_LOG_PASSES

    assert_operator rows, :<=, budget,
      "materialized #{rows} rows from a #{@game.game_events.count}-event game (budget #{budget})"
  end

  test "keeps the digest within its size budget as a game grows" do
    digest = JSON.generate(DigestBuilder.new(@game).call)
    budget = TURNS.size * CIVS.size * MAX_DIGEST_BYTES_PER_TURN_PER_CIV

    assert_operator digest.bytesize, :<=, budget,
      "digest is #{digest.bytesize} bytes over #{TURNS.size} turns and #{CIVS.size} civs " \
      "(#{digest.bytesize / (TURNS.size * CIVS.size)} per turn per civ, budget #{budget})"
  end

  test "builds each projection once over a full digest build" do
    rebuilt = count_constructions { DigestBuilder.new(@game).call }
      .select { |klass, count| count > BUILDS_ALLOWED[klass] }

    assert_empty rebuilt.map { |klass, count| "#{klass} #{count}x" }
  end

  private

  # A projection indexes the whole log when it is built, so counting
  # constructions counts the indexing a digest repeats.
  def count_constructions
    counts = Hash.new(0)

    PROJECTIONS.each do |klass|
      build = klass.method(:new)
      klass.define_singleton_method(:new) do |*args, **kwargs|
        counts[klass] += 1
        build.call(*args, **kwargs)
      end
    end

    yield
    counts
  ensure
    PROJECTIONS.each { |klass| klass.singleton_class.remove_method(:new) }
  end

  # Uncached so the count reflects the rows actually materialized into
  # GameEvent objects. The query cache spares the round trip but still
  # rebuilds every object, which is where the time goes.
  def measure_event_loading
    rows = 0

    counter = lambda do |event|
      next unless event.payload[:sql]&.include?("game_events")
      next if event.payload[:name] == "SCHEMA"

      rows += event.payload[:row_count].to_i
    end

    ActiveRecord::Base.uncached do
      ActiveSupport::Notifications.subscribed(counter, "sql.active_record") { yield }
    end

    rows
  end

  def populate_event_log
    event(nil, "session_started", 0)
    found_capitals
    snapshot_every_turn
    fight_a_war
    build_a_culture
    hold_a_congress
    log_events_no_projection_reads
  end

  def found_capitals
    CIVS.each_with_index do |civ, index|
      event(civ, "city_founded", 1, city: "#{civ} Capital", x: index * 12, y: 10, capital: true)
    end
  end

  def snapshot_every_turn
    TURNS.each do |turn|
      CIVS.each_with_index { |civ, index| snapshot(civ, turn, index) }
    end
  end

  def fight_a_war
    event(nil, "war_declared", 8, attacker_team: 1, attacker_civs: %w[Rome], defender_team: 2, defender_civs: %w[Greece])
    event(nil, "city_captured", 11, city: "Greece Capital", old_owner: "Greece", new_owner: "Rome", x: 12, y: 10)
    3.times { event("Greece", "unit_lost", 11) }
    3.times { event("Rome", "unit_lost", 12) }
    event("Rome", "unit_killed", 12, unit: "UNIT_SPEARMAN")
    event(nil, "peace_made", 14, team_a: 1, team_a_civs: %w[Rome], team_b: 2, team_b_civs: %w[Greece])
  end

  def build_a_culture
    event(nil, "era_entered", 6, era: "ERA_CLASSICAL", civs: %w[Rome])
    event("Rome", "pantheon_founded", 3, city: "Rome Capital", belief: "BELIEF_GOD_OF_WAR")
    event("Rome", "religion_founded", 7, religion: "RELIGION_CHRISTIANITY", holy_city: "Rome Capital", beliefs: %w[BELIEF_TITHE])
    event("Rome", "policy_branch_adopted", 5, branch: "POLICY_BRANCH_TRADITION")
    KeyMomentDetector::BRANCH_POLICIES["POLICY_BRANCH_TRADITION"].each_with_index do |policy, index|
      event("Rome", "policy_adopted", 6 + index, policy: policy)
    end
    event("Greece", "tech_researched", 4, team: 2, civs: %w[Greece], tech: "TECH_METAL_CASTING")
    event("Greece", "building_constructed", 9, building: "BUILDING_UNIVERSITY", city: "Greece Capital")
    race_a_wonder
  end

  def race_a_wonder
    (7..10).each do |turn|
      event("Rome", "city_snapshot", turn, city: "Rome Capital", producing: "BUILDING_PYRAMID",
            producing_kind: "wonder", production_stored: 30 * turn, production_turns_left: 11 - turn)
      event("Greece", "city_snapshot", turn, city: "Greece Capital", producing: "BUILDING_PYRAMID",
            producing_kind: "wonder", production_stored: 20 * turn, production_turns_left: 14 - turn)
    end
    event("Rome", "building_constructed", 11, building: "BUILDING_PYRAMID", city: "Rome Capital", wonder: "world")
  end

  def hold_a_congress
    event(nil, "congress_host_changed", 12, old_host: nil, new_host: "Rome")
    event(nil, "resolution_proposed", 13, resolution: "RESOLUTION_WORLD_IDEOLOGY", proposer: "Rome")
    event(nil, "resolution_passed", 14, resolution: "RESOLUTION_WORLD_IDEOLOGY")
    TURNS.select { |turn| (turn % 5).zero? }.each do |turn|
      congress_snapshot(turn, host: "Rome", votes_needed: 12,
                              delegates: CIVS.map.with_index { |civ, i| { "civ" => civ, "votes" => 4 + i } })
    end
  end

  # 55% of a real game's events are of types no projection reads. They are
  # here because the bare `game_events.to_a` loads still pay for them.
  def log_events_no_projection_reads
    TURNS.each do |turn|
      CIVS.each do |civ|
        event(civ, "unit_created", turn, unit: "UNIT_WARRIOR")
        event(civ, "plot_acquired", turn, x: turn, y: turn)
        event(civ, "population_changed", turn, city: "#{civ} Capital", population: turn)
      end
    end
  end

  def snapshot(civ, turn, index)
    influence = (CIVS - [ civ ]).map do |opponent|
      { "civ" => opponent, "level" => "INFLUENCE_LEVEL_FAMILIAR", "trend" => "INFLUENCE_TREND_RISING",
        "points" => 100 * turn }
    end

    payload = {
      "score" => 100 * turn + index, "science" => 10 * turn, "production" => 8 * turn,
      "culture" => 5 * turn, "gold" => 200, "gold_per_turn" => 12, "faith" => 3 * turn,
      "happiness" => 10 - index, "military_might" => 1_000 * turn, "military_units" => 5 + index,
      "population" => 4 * turn, "cities" => 2 + index, "techs" => turn, "food" => 20,
      "gross_gold" => 30, "plots" => 20 * turn, "tourism" => 2 * turn, "civs_influential_on" => 0,
      "capitals" => [ "#{civ} Capital" ], "influence" => influence,
      "spaceship" => { "apollo" => 0, "booster" => 0, "cockpit" => 0, "stasis_chamber" => 0, "engine" => 0 }
    }

    create_event(civ, "snapshot", turn, payload)
  end

  def congress_snapshot(turn, host:, delegates:, votes_needed:)
    create_event(nil, "congress_snapshot", turn,
                 "host" => host, "delegates" => delegates, "votes_needed_for_diplo_victory" => votes_needed)
  end

  def event(civ, event_type, turn, extra = {})
    create_event(civ, event_type, turn, extra.stringify_keys)
  end

  def create_event(civ, event_type, turn, payload)
    @seq += 1
    payload = payload.merge("event" => event_type, "turn" => turn)
    payload["civ"] = civ if civ

    @game.game_events.create!(
      seq: @seq, session_index: 0, turn: turn, event_type: event_type, civ: civ, payload: payload
    )
  end
end
