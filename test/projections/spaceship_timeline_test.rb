require "test_helper"

class SpaceshipTimelineTest < ActiveSupport::TestCase
  setup do
    @game = Game.create!(name: "Spaceship Test Game")
    @seq = 0
  end

  test "series returns turn, the raw spaceship state and parts assembled for a civ" do
    snapshot("Rome", 100,
      spaceship: { "apollo" => 1, "booster" => 2, "cockpit" => 1, "stasis_chamber" => 0, "engine" => 1 })

    assert_equal(
      [ { turn: 100, spaceship: { "apollo" => 1, "booster" => 2, "cockpit" => 1, "stasis_chamber" => 0, "engine" => 1 },
          parts_assembled: 4 } ],
      SpaceshipTimeline.new(@game).series("Rome")
    )
  end

  test "parts_assembled excludes apollo, since it's a prerequisite unlock, not a ship part" do
    snapshot("Rome", 100,
      spaceship: { "apollo" => 1, "booster" => 3, "cockpit" => 1, "stasis_chamber" => 1, "engine" => 1 })

    assert_equal 6, SpaceshipTimeline.new(@game).latest("Rome")[:parts_assembled]
  end

  test "keeps one entry per turn when a turn was snapshotted twice" do
    snapshot("Rome", 100, spaceship: { "apollo" => 1, "booster" => 1, "cockpit" => 0, "stasis_chamber" => 0, "engine" => 0 })
    snapshot("Rome", 100, spaceship: { "apollo" => 1, "booster" => 2, "cockpit" => 0, "stasis_chamber" => 0, "engine" => 0 })

    assert_equal [ 2 ], SpaceshipTimeline.new(@game).series("Rome").map { |entry| entry[:parts_assembled] }
  end

  test "leaves a snapshot with no spaceship field out of the series" do
    snapshot("Rome", 100, score: 300)

    assert_equal [], SpaceshipTimeline.new(@game).series("Rome")
  end

  test "has nothing to report for a civ with no snapshots" do
    snapshot("Rome", 100, spaceship: { "apollo" => 1, "booster" => 0, "cockpit" => 0, "stasis_chamber" => 0, "engine" => 0 })

    assert_nil SpaceshipTimeline.new(@game).latest("Greece")
  end

  test "complete? is true once every part meets its required count" do
    assert SpaceshipTimeline.complete?(
      { "apollo" => 1, "booster" => 3, "cockpit" => 1, "stasis_chamber" => 1, "engine" => 1 }
    )
  end

  test "complete? is false when any single part is short" do
    refute SpaceshipTimeline.complete?(
      { "apollo" => 1, "booster" => 2, "cockpit" => 1, "stasis_chamber" => 1, "engine" => 1 }
    )
  end

  test "complete? is false for a nil spaceship" do
    refute SpaceshipTimeline.complete?(nil)
  end

  private

  def snapshot(civ, turn, metrics)
    @game.game_events.create!(
      seq: @seq += 1, session_index: 0, turn: turn, event_type: "snapshot", civ: civ,
      payload: metrics.deep_stringify_keys.merge("event" => "snapshot", "turn" => turn, "civ" => civ)
    )
  end
end
