require "test_helper"

class KeyMomentDetectorTest < ActiveSupport::TestCase
  setup do
    @game = Game.create!(name: "Key Moment Test Game")
    @seq = 0
  end

  test "wars reports declaration, territory changes and unit-loss spikes" do
    event(nil, "war_declared", 10, attacker_team: 1, attacker_civs: %w[Rome], defender_team: 2, defender_civs: %w[Greece])
    event(nil, "city_captured", 12, city: "Athens", old_owner: "Greece", new_owner: "Rome")
    event("Greece", "unit_lost", 15)
    event("Greece", "unit_lost", 15)
    event("Greece", "unit_lost", 15)
    event("Rome", "unit_lost", 20)
    event(nil, "peace_made", 30, team_a: 1, team_a_civs: %w[Rome], team_b: 2, team_b_civs: %w[Greece])

    moments = detector.wars

    assert_equal 1, moments.size
    war = moments.first

    assert_equal :war, war[:type]
    assert_equal 10, war[:turn]
    assert_equal 30, war[:turn_peace]
    assert_equal %w[Rome], war[:attacker_civs]
    assert_equal %w[Greece], war[:defender_civs]
    assert_equal({ "Rome" => 1 }, war[:cities_captured])
    assert_equal [ { civ: "Greece", turn: 15, count: 3 } ], war[:unit_lost_spikes]
  end

  test "wars omits unit_lost_spikes when no side loses 3+ units in a single turn" do
    event(nil, "war_declared", 10, attacker_team: 1, attacker_civs: %w[Rome], defender_team: 2, defender_civs: %w[Greece])
    event("Greece", "unit_lost", 15)
    event("Greece", "unit_lost", 16)
    event(nil, "peace_made", 30, team_a: 1, team_a_civs: %w[Rome], team_b: 2, team_b_civs: %w[Greece])

    war = detector.wars.first

    assert_equal [], war[:unit_lost_spikes]
    assert_equal({}, war[:cities_captured])
  end

  test "wars ignores losses and captures outside the war window" do
    event(nil, "war_declared", 10, attacker_team: 1, attacker_civs: %w[Rome], defender_team: 2, defender_civs: %w[Greece])
    event(nil, "peace_made", 30, team_a: 1, team_a_civs: %w[Rome], team_b: 2, team_b_civs: %w[Greece])
    # Before the war
    event("Greece", "unit_lost", 5)
    event("Greece", "unit_lost", 5)
    event("Greece", "unit_lost", 5)
    # After peace
    event(nil, "city_captured", 40, city: "Sparta", old_owner: "Greece", new_owner: "Rome")

    war = detector.wars.first

    assert_equal [], war[:unit_lost_spikes]
    assert_equal({}, war[:cities_captured])
  end

  private

  def detector
    @detector ||= KeyMomentDetector.new(@game)
  end

  def event(civ, event_type, turn, extra = {})
    @seq += 1
    payload = extra.stringify_keys.merge("event" => event_type, "turn" => turn)
    payload["civ"] = civ if civ
    @game.game_events.create!(
      seq: @seq,
      session_index: 0,
      turn: turn,
      event_type: event_type,
      civ: civ,
      payload: payload
    )
  end
end
