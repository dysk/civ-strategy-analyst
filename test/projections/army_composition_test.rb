require "test_helper"

class ArmyCompositionTest < ActiveSupport::TestCase
  setup do
    @game = Game.create!(name: "Army Test Game")
    @seq = 0
  end

  test "reports the army a civilization held at its last snapshot" do
    snapshot("Rome", 10, military_might: 300, military_units: 6)
    snapshot("Rome", 20, military_might: 1000, military_units: 8)

    assert_equal(
      { turn: 20, units: 8, might: 1000, might_per_unit: 125.0 },
      ArmyComposition.new(@game).latest("Rome")
    )
  end

  test "keeps one entry per turn when a turn was snapshotted twice" do
    snapshot("Rome", 10, military_might: 300, military_units: 6)
    snapshot("Rome", 10, military_might: 400, military_units: 7)

    assert_equal [ { turn: 10, units: 7, might: 400, might_per_unit: 57.1 } ],
                 ArmyComposition.new(@game).series("Rome")
  end

  test "has nothing to report for a civilization with no snapshots" do
    snapshot("Rome", 10, military_might: 300, military_units: 6)

    assert_nil ArmyComposition.new(@game).latest("Greece")
  end

  test "leaves might per unit out for a civilization fielding no units" do
    snapshot("Rome", 10, military_might: 0, military_units: 0)

    assert_nil ArmyComposition.new(@game).latest("Rome")[:might_per_unit]
  end

  private

  def snapshot(civ, turn, metrics)
    @game.game_events.create!(
      seq: @seq += 1, session_index: 0, turn: turn, event_type: "snapshot", civ: civ,
      payload: metrics.stringify_keys.merge("event" => "snapshot", "turn" => turn, "civ" => civ)
    )
  end
end
