require "test_helper"

class DigestBuilderTest < ActiveSupport::TestCase
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
        game_speed: "QUICK", max_turns: 40, start_era: "ERA_ANCIENT" },
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

  test "includes key moments from KeyMomentDetector, keyed by heuristic" do
    event(nil, "war_declared", 10, attacker_team: 1, attacker_civs: %w[Rome], defender_team: 2, defender_civs: %w[Greece])

    digest = DigestBuilder.new(@game).call

    assert_equal 1, digest[:key_moments][:wars].size
    assert_equal 10, digest[:key_moments][:wars].first[:turn]
    assert_includes digest[:key_moments].keys, :leader_changes
    assert_includes digest[:key_moments].keys, :era_leads
    assert_includes digest[:key_moments].keys, :religion_foundings
    assert_includes digest[:key_moments].keys, :military_might_swings
    assert_includes digest[:key_moments].keys, :snowballs_score
    assert_includes digest[:key_moments].keys, :snowballs_population
    assert_includes digest[:key_moments].keys, :snowballs_science
    assert_includes digest[:key_moments].keys, :snowballs_culture
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
  end

  private

  def snapshot(civ, turn, **metrics)
    @seq += 1
    payload = metrics.stringify_keys.merge("event" => "snapshot", "turn" => turn, "civ" => civ)
    @game.game_events.create!(
      seq: @seq, session_index: 0, turn: turn, event_type: "snapshot", civ: civ, payload: payload
    )
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
