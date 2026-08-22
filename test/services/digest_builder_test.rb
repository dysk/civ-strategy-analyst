require "test_helper"

class DigestBuilderTest < ActiveSupport::TestCase
  LEKMOD_FIXTURES_ROOT = Rails.root.join("test/support/lekmod")

  setup do
    @game = Game.create!(
      name: "Digest Test Game", map_script: "TestMap", map_size: "SMALL",
      game_speed: "QUICK", max_turns: 40, start_era: "ERA_ANCIENT"
    )
    @seq = 0
    @rome = @game.players.create!(civ: "Rome", leader_name: "Augustus", human: true, handicap: "PRINCE")
    @greece = @game.players.create!(civ: "Greece", leader_name: "Alexander", human: false, handicap: "KING")
  end

  test "includes game settings and roster" do
    digest = DigestBuilder.new(@game).call

    assert_equal(
      { name: "Digest Test Game", map_script: "TestMap", map_size: "SMALL",
        game_speed: "QUICK", max_turns: 40, start_era: "ERA_ANCIENT",
        map_width: nil, map_width_estimated: false, early_game_deadline_turn: 100 },
      digest[:game]
    )

    assert_equal(
      [
        { civ: "Rome", leader_name: "Augustus", human: true, handicap: "PRINCE" },
        { civ: "Greece", leader_name: "Alexander", human: false, handicap: "KING" }
      ],
      digest[:roster]
    )
  end

  test "includes the resolved outcome, threading winner_civ and victory_type through" do
    snapshot("Rome", 10, score: 100, science: 20)

    digest = DigestBuilder.new(@game, winner_civ: "Rome", victory_type: "domination").call

    assert_equal(
      { winner_civ: "Rome", victory_type: "domination", in_progress: false, source: :declared },
      digest[:outcome]
    )
  end

  test "includes an early game boundary per civ" do
    event(nil, "tech_researched", 10, team: 1, civs: %w[Rome], tech: "TECH_METAL_CASTING")
    event("Rome", "building_constructed", 20, building: "BUILDING_UNIVERSITY", city: "Roma")
    snapshot("Greece", 40, score: 10)

    digest = DigestBuilder.new(@game).call

    assert_equal %w[Rome Greece], digest[:early_game].keys
    assert_equal 20, digest[:early_game]["Rome"][:end_turn]
    assert_equal :milestone, digest[:early_game]["Rome"][:reason]
    assert_equal :game_end, digest[:early_game]["Greece"][:reason]
  end

  test "includes a pre-sorted final standings ranking by score" do
    snapshot("Rome", 10, score: 300)
    snapshot("Greece", 10, score: 500)

    digest = DigestBuilder.new(@game).call

    assert_equal %w[Greece Rome], digest[:standings]
  end

  test "summarizes metrics per civ at ~25-turn checkpoints, using the nearest prior snapshot" do
    snapshot("Rome", 10, score: 50, science: 5)
    snapshot("Rome", 20, score: 80, science: 10)
    snapshot("Rome", 30, score: 120, science: 15)
    snapshot("Rome", 40, score: 200, science: 25)

    digest = DigestBuilder.new(@game).call

    assert_equal(
      {
        25 => { "score" => 80, "science" => 10 },
        40 => { "score" => 200, "science" => 25 }
      },
      digest[:metrics]["Rome"]
    )
  end

  test "checkpoint metrics include the demographics and tourism scalars" do
    snapshot("Rome", 25, score: 80, production: 62, food: 18, gross_gold: 45, plots: 87,
      tourism: 120, civs_influential_on: 1)

    digest = DigestBuilder.new(@game).call

    rome_checkpoint = digest[:metrics]["Rome"][25]
    assert_equal 62, rome_checkpoint["production"]
    assert_equal 18, rome_checkpoint["food"]
    assert_equal 45, rome_checkpoint["gross_gold"]
    assert_equal 87, rome_checkpoint["plots"]
    assert_equal 120, rome_checkpoint["tourism"]
    assert_equal 1, rome_checkpoint["civs_influential_on"]
  end

  test "adds tech/policy cost multipliers per checkpoint, derived from cities beyond the capital" do
    snapshot("Rome", 25, score: 80, cities: 4)
    snapshot("Greece", 25, score: 60, cities: 1)

    digest = DigestBuilder.new(@game).call

    rome_checkpoint = digest[:metrics]["Rome"][25]
    assert_equal 4, rome_checkpoint["cities"]
    assert_equal 1.15, rome_checkpoint["tech_cost_multiplier"]
    assert_equal 1.3, rome_checkpoint["policy_cost_multiplier"]

    greece_checkpoint = digest[:metrics]["Greece"][25]
    assert_equal 1.0, greece_checkpoint["tech_cost_multiplier"]
    assert_equal 1.0, greece_checkpoint["policy_cost_multiplier"]
  end

  test "never drops the cost multiplier below 1.0 when a civ has no cities" do
    snapshot("Rome", 25, score: 80, cities: 0)

    digest = DigestBuilder.new(@game).call

    rome_checkpoint = digest[:metrics]["Rome"][25]
    assert_equal 1.0, rome_checkpoint["tech_cost_multiplier"]
    assert_equal 1.0, rome_checkpoint["policy_cost_multiplier"]
  end

  test "adds army power and the power each unit averages per checkpoint" do
    snapshot("Rome", 25, score: 80, military_might: 1300, military_units: 10, gold: 900)

    checkpoint = DigestBuilder.new(@game).call[:metrics]["Rome"][25]
    assert_equal 1000, checkpoint["army_power"]
    assert_equal 100.0, checkpoint["power_per_unit"]
  end

  test "omits power per unit for a civilization fielding no military units" do
    snapshot("Rome", 25, score: 80, military_might: 0, military_units: 0, gold: 0)

    refute DigestBuilder.new(@game).call[:metrics]["Rome"][25].key?("power_per_unit")
  end

  test "omits army power when a checkpoint carries no treasury to divide out" do
    snapshot("Rome", 25, score: 80, military_might: 1000, military_units: 8)

    checkpoint = DigestBuilder.new(@game).call[:metrics]["Rome"][25]
    refute checkpoint.key?("army_power")
    refute checkpoint.key?("power_per_unit")
  end

  test "omits cost multipliers when a checkpoint has no city count" do
    snapshot("Rome", 25, score: 80)

    digest = DigestBuilder.new(@game).call

    refute digest[:metrics]["Rome"][25].key?("tech_cost_multiplier")
    refute digest[:metrics]["Rome"][25].key?("policy_cost_multiplier")
  end

  test "includes per-civ timelines from PlayerTimeline" do
    event("Rome", "city_founded", 1, city: "Roma", x: 1, y: 1)

    digest = DigestBuilder.new(@game).call

    assert_equal(
      [ { turn: 1, city: "Roma", action: :founded } ],
      digest[:timelines]["Rome"][:cities]
    )
    assert_equal [], digest[:timelines]["Greece"][:cities]
  end

  test "flags a map width it had to infer from the plots" do
    event("Rome", "city_founded", 1, city: "Roma", x: 45, y: 10)

    digest = DigestBuilder.new(@game).call

    assert_equal({ map_width: 46, map_width_estimated: true }, digest[:game].slice(:map_width, :map_width_estimated))
  end

  test "includes per-civ empire geometry from EmpireGeometry" do
    @game.update!(map_width: 46)
    event("Rome", "city_founded", 1, city: "Roma", x: 10, y: 10)
    event("Rome", "city_founded", 5, city: "Ostia", x: 14, y: 10)

    digest = DigestBuilder.new(@game).call

    assert_equal(
      { turn: 5, cities: 2, span: 4, mean_spacing: 4.0, elongation: 1.0 },
      digest[:timelines]["Rome"][:geometry].last
    )
  end

  test "includes per-civ city count mismatches from EmpireGeometry" do
    event("Rome", "city_founded", 1, city: "Roma", x: 10, y: 10)
    snapshot("Rome", 20, cities: 0)

    digest = DigestBuilder.new(@game).call

    assert_equal(
      [ { turn: 20, counted: 1, reported: 0 } ],
      digest[:timelines]["Rome"][:city_count_mismatches]
    )
  end

  test "includes the distance between every pair of capitals" do
    @game.update!(map_width: 46)
    event("Rome", "city_founded", 0, city: "Roma", x: 10, y: 10)
    event("Greece", "city_founded", 0, city: "Athens", x: 16, y: 10)

    proximity = DigestBuilder.new(@game).call[:capital_proximity]

    assert_equal "Roma", proximity[:capitals]["Rome"][:city]
    assert_equal [ { civs: %w[Rome Greece], distance: 6 } ], proximity[:distances]
  end

  test "includes who holds the ground between neighbouring capitals" do
    @game.update!(map_script: "Pangaea")
    event("Rome", "city_founded", 0, city: "Roma", x: 10, y: 20)
    event("Greece", "city_founded", 0, city: "Athenai", x: 27, y: 20)
    event("Rome", "city_founded", 30, city: "Ostia", x: 18, y: 20)

    buffer_cities = DigestBuilder.new(@game).call[:buffer_cities]

    assert_equal true, buffer_cities[:applicable]
    assert_equal "Ostia", buffer_cities[:pairs].sole[:buffers]["Rome"][:city]
  end

  test "says a map was never examined rather than leaving buffer cities out" do
    assert_equal(
      { applicable: false, reason: :map_not_pangaea },
      DigestBuilder.new(@game).call[:buffer_cities]
    )
  end

  test "includes key moments from KeyMomentDetector, keyed by heuristic" do
    event(nil, "war_declared", 10, attacker_team: 1, attacker_civs: %w[Rome], defender_team: 2, defender_civs: %w[Greece])

    digest = DigestBuilder.new(@game).call

    assert_equal 1, digest[:key_moments][:wars].size
    assert_equal 10, digest[:key_moments][:wars].first[:turn]
    assert_includes digest[:key_moments].keys, :buffer_city_losses
    assert_includes digest[:key_moments].keys, :leader_changes
    assert_includes digest[:key_moments].keys, :era_leads
    assert_includes digest[:key_moments].keys, :religion_foundings
    assert_includes digest[:key_moments].keys, :army_power_swings
    assert_includes digest[:key_moments].keys, :snowballs_score
    assert_includes digest[:key_moments].keys, :snowballs_population
    assert_includes digest[:key_moments].keys, :snowballs_science
    assert_includes digest[:key_moments].keys, :snowballs_culture
    assert_includes digest[:key_moments].keys, :snowballs_production
    assert_includes digest[:key_moments].keys, :snowballs_faith
    assert_includes digest[:key_moments].keys, :snowballs_gold_per_turn
    assert_includes digest[:key_moments].keys, :snowballs_food
    assert_includes digest[:key_moments].keys, :happiness_swings
    assert_includes digest[:key_moments].keys, :unhappiness_periods
    assert_includes digest[:key_moments].keys, :pantheon_foundings
    assert_includes digest[:key_moments].keys, :religion_enhancements
    assert_includes digest[:key_moments].keys, :reformations
    assert_includes digest[:key_moments].keys, :ideology_unlocks
    assert_includes digest[:key_moments].keys, :ideology_adoptions
    assert_includes digest[:key_moments].keys, :tenet_adoptions
    assert_includes digest[:key_moments].keys, :policy_branch_adoptions
    assert_includes digest[:key_moments].keys, :policy_branch_completions
    assert_includes digest[:key_moments].keys, :nuclear_detonations
    assert_includes digest[:key_moments].keys, :city_state_ally_takeovers
    assert_includes digest[:key_moments].keys, :influence_level_reached
    assert_includes digest[:key_moments].keys, :cultural_victory_imminent
    assert_includes digest[:key_moments].keys, :congress_host_changes
    assert_includes digest[:key_moments].keys, :united_nations_formed
    assert_includes digest[:key_moments].keys, :diplomatic_victory_imminent
    assert_includes digest[:key_moments].keys, :resolutions_passed
    assert_includes digest[:key_moments].keys, :capital_control_changes
    assert_includes digest[:key_moments].keys, :apollo_completions
    assert_includes digest[:key_moments].keys, :spaceship_part_assemblies
    assert_includes digest[:key_moments].keys, :science_victory_imminent
  end

  test "includes a cultural-standing matrix per civ from the latest known influence data" do
    snapshot("Rome", 10, influence: [ { "civ" => "Greece", "points" => 100, "level" => "INFLUENCE_LEVEL_FAMILIAR", "trend" => "INFLUENCE_TREND_RISING" } ])
    snapshot("Rome", 20, influence: [ { "civ" => "Greece", "points" => 320, "level" => "INFLUENCE_LEVEL_INFLUENTIAL", "trend" => "INFLUENCE_TREND_RISING" } ])

    digest = DigestBuilder.new(@game).call

    assert_equal(
      { "Greece" => { points: 320, level: "INFLUENCE_LEVEL_INFLUENTIAL", trend: "INFLUENCE_TREND_RISING" } },
      digest[:cultural]["Rome"]
    )
  end

  test "cultural matrix is empty for a civ with no influence data" do
    digest = DigestBuilder.new(@game).call

    assert_equal({}, digest[:cultural]["Rome"])
  end

  test "includes World Congress host history and the latest votes needed" do
    congress_snapshot(10, host: "Rome", delegates: [], votes_needed: 12)
    congress_snapshot(40, host: "Greece", delegates: [], votes_needed: 14)

    digest = DigestBuilder.new(@game).call

    assert_equal(
      [ { turn: 10, host: "Rome" }, { turn: 40, host: "Greece" } ],
      digest[:congress][:host_history]
    )
    assert_equal 14, digest[:congress][:votes_needed]
  end

  test "samples each civ's delegate votes at ~25-turn checkpoints" do
    congress_snapshot(10, host: "Rome", delegates: [ { "civ" => "Rome", "votes" => 3 } ], votes_needed: 12)
    congress_snapshot(30, host: "Rome", delegates: [ { "civ" => "Rome", "votes" => 5 } ], votes_needed: 12)

    digest = DigestBuilder.new(@game).call

    assert_equal({ 25 => 3, 30 => 5 }, digest[:congress][:delegates_by_civ]["Rome"])
  end

  test "includes raw resolution lifecycles, for the LLM to cross-reference against lekmod.resolutions" do
    event(nil, "resolution_proposed", 10, resolution: "RESOLUTION_WORLD_FAIR", proposer: "Rome", repeal: false)
    event(nil, "resolution_passed", 15, resolution: "RESOLUTION_WORLD_FAIR")

    digest = DigestBuilder.new(@game).call

    assert_equal(
      [ { resolution: "RESOLUTION_WORLD_FAIR", proposer: "Rome", repeal: false,
          proposed_turn: 10, outcome: :passed, outcome_turn: 15, repealed_turn: nil } ],
      digest[:congress][:resolutions]
    )
  end

  test "samples each civ's capitals held and spaceship state at ~25-turn checkpoints" do
    snapshot("Rome", 10, capitals: %w[Rome],
      spaceship: { "apollo" => 0, "booster" => 0, "cockpit" => 0, "stasis_chamber" => 0, "engine" => 0 })
    snapshot("Rome", 30, capitals: %w[Rome Greece],
      spaceship: { "apollo" => 1, "booster" => 1, "cockpit" => 0, "stasis_chamber" => 0, "engine" => 0 })

    digest = DigestBuilder.new(@game).call

    assert_equal({ 25 => 1, 30 => 2 }, digest[:victory_progress]["Rome"][:capitals_held])
    assert_equal(
      { "apollo" => 1, "booster" => 1, "cockpit" => 0, "stasis_chamber" => 0, "engine" => 0 },
      digest[:victory_progress]["Rome"][:spaceship][30]
    )
  end

  test "includes lekmod reference data resolved from the given version, for roster civs only" do
    @game.players.create!(civ: "Chile", leader_name: "Test Leader", human: true, handicap: "PRINCE")

    digest = DigestBuilder.new(@game, lekmod_version: "1.5", lekmod_root: LEKMOD_FIXTURES_ROOT).call

    assert_equal "1.5", digest[:lekmod][:version]
    assert_nil digest[:lekmod][:resolution_note]
    assert_equal [ "Chile" ], digest[:lekmod][:civilizations].keys
    assert_match(/v1\.5 text for Chile/, digest[:lekmod][:civilizations]["Chile"])
  end

  test "includes the LEKMOD entry for every policy adopted by any civ" do
    event("Rome", "policy_adopted", 5, policy: "POLICY_ARISTOCRACY")

    digest = DigestBuilder.new(@game, lekmod_version: "1.5", lekmod_root: LEKMOD_FIXTURES_ROOT).call

    assert_match(/\+15% Production towards Wonders/, digest[:lekmod][:policies]["POLICY_ARISTOCRACY"])
  end

  test "includes the LEKMOD entry for an adopted ideology tenet, matched by derived name" do
    event("Rome", "policy_adopted", 5, policy: "POLICY_ECONOMIC_UNION")

    digest = DigestBuilder.new(@game, lekmod_version: "1.5", lekmod_root: LEKMOD_FIXTURES_ROOT).call

    assert_match(/\+5% gold for each Trade Route/, digest[:lekmod][:policies]["POLICY_ECONOMIC_UNION"])
  end

  test "includes the LEKMOD entry for a belief founding a pantheon" do
    event("Rome", "pantheon_founded", 5, belief: "BELIEF_GOD_SEA", city: "Roma")

    digest = DigestBuilder.new(@game, lekmod_version: "1.5", lekmod_root: LEKMOD_FIXTURES_ROOT).call

    assert_match(/\+1 Faith and Culture from Fish/, digest[:lekmod][:beliefs]["BELIEF_GOD_SEA"])
  end

  test "includes the LEKMOD entries for beliefs chosen founding or enhancing a religion" do
    event("Rome", "religion_founded", 20, religion: "RELIGION_X", holy_city: "Roma", beliefs: [ "BELIEF_GOD_SEA" ])

    digest = DigestBuilder.new(@game, lekmod_version: "1.5", lekmod_root: LEKMOD_FIXTURES_ROOT).call

    assert_match(/\+1 Faith and Culture from Fish/, digest[:lekmod][:beliefs]["BELIEF_GOD_SEA"])
  end

  test "includes the LEKMOD display name for every resolution proposed in this game's Congress" do
    event(nil, "resolution_proposed", 20, resolution: "RESOLUTION_WORLDS_FAIR", proposer: "Rome", repeal: false)

    digest = DigestBuilder.new(@game, lekmod_version: "1.5", lekmod_root: LEKMOD_FIXTURES_ROOT).call

    assert_equal "World's Fair", digest[:lekmod][:resolutions]["RESOLUTION_WORLDS_FAIR"]
  end

  test "includes the full LEKMOD general rules text" do
    digest = DigestBuilder.new(@game, lekmod_version: "1.5", lekmod_root: LEKMOD_FIXTURES_ROOT).call

    assert_match(/## World Wonders/, digest[:lekmod][:general_rules])
  end

  test "falls back to an empty lekmod block, with a note, when the game has no lekmod_version" do
    digest = DigestBuilder.new(@game).call

    assert_nil digest[:lekmod][:version]
    assert digest[:lekmod][:resolution_note].present?
    assert_equal({}, digest[:lekmod][:civilizations])
    assert_equal({}, digest[:lekmod][:policies])
    assert_equal({}, digest[:lekmod][:beliefs])
    assert_nil digest[:lekmod][:general_rules]
  end

  private

  def snapshot(civ, turn, **metrics)
    @seq += 1
    payload = metrics.stringify_keys.merge("event" => "snapshot", "turn" => turn, "civ" => civ)
    @game.game_events.create!(
      seq: @seq, session_index: 0, turn: turn, event_type: "snapshot", civ: civ, payload: payload
    )
  end

  def congress_snapshot(turn, host:, delegates:, votes_needed:)
    @seq += 1
    payload = { "event" => "congress_snapshot", "turn" => turn, "host" => host,
                "delegates" => delegates, "votes_needed_for_diplo_victory" => votes_needed }
    @game.game_events.create!(seq: @seq, session_index: 0, turn: turn, event_type: "congress_snapshot", civ: nil, payload: payload)
  end

  def event(civ, event_type, turn, extra = {})
    @seq += 1
    payload = extra.stringify_keys.merge("event" => event_type, "turn" => turn)
    payload["civ"] = civ if civ
    @game.game_events.create!(
      seq: @seq, session_index: 0, turn: turn, event_type: event_type, civ: civ, payload: payload
    )
  end
end
