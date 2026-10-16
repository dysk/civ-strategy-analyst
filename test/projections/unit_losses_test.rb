require "test_helper"

class UnitLossesTest < ActiveSupport::TestCase
  setup do
    @game = Game.create!(name: "Unit Losses Test Game")
    @seq = 0
  end

  test "applicable when the log carries a reconciled cause" do
    lost("Babylon", "UNIT_WARRIOR", 10, cause: "killed", killer: "Barbarians", confidence: "inferred")

    assert_predicate losses, :applicable?
  end

  test "not applicable on a log the reconciler never touched" do
    lost("Babylon", "UNIT_WARRIOR", 10, killed_by: "Philippines")

    assert_not_predicate losses, :applicable?
  end

  test "reads the cause, the confidence and the killer off a death" do
    event = lost("Babylon", "UNIT_RIFLEMAN", 10, cause: "killed", killer: "Philippines", confidence: "confirmed")

    assert_equal :killed, losses.cause(event)
    assert_equal :confirmed, losses.confidence(event)
    assert_equal "Philippines", losses.killer(event)
  end

  test "names the captor of a civilian lost with the city it stood in" do
    event = lost("Arabia", "UNIT_CARAVAN", 144, cause: "city_captured",
                 captured_by: "Babylon", confidence: "confirmed")

    assert_equal :city_captured, losses.cause(event)
    assert_equal "Babylon", losses.killer(event)
  end

  test "a removal the reconciler called used up names nobody" do
    event = lost("Arabia", "UNIT_CARAVAN", 60, cause: "used_up", confidence: "confirmed")

    assert_equal :used_up, losses.cause(event)
    assert_nil losses.killer(event)
  end

  # The reconciler's great-person list omits the mod's unique great people,
  # so a Dalai Lama expended arrives as a barbarian kill by elimination.
  test "a great person outside the reconciler's own list is unclassified" do
    event = lost("Tibet", "UNIT_DALAILAMA", 80, cause: "killed", killer: "Barbarians", confidence: "inferred")

    assert_nil losses.cause(event)
    assert_nil losses.confidence(event)
    assert_nil losses.killer(event)
  end

  test "a great person the reconciler does know keeps its cause" do
    event = lost("Babylon", "UNIT_PROPHET", 80, cause: "expended", confidence: "confirmed")

    assert_equal :expended, losses.cause(event)
  end

  test "an ordinary unit on an unreconciled log is unclassified" do
    event = lost("Babylon", "UNIT_WARRIOR", 10, killed_by: "Philippines")

    assert_nil losses.cause(event)
    assert_nil losses.killer(event)
  end

  private

  def losses = @losses ||= UnitLosses.new(@game)

  def lost(civ, unit, turn, extra = {})
    @game.game_events.create!(
      seq: @seq += 1, session_index: 0, turn: turn, event_type: "unit_lost", civ: civ,
      payload: extra.stringify_keys.merge("event" => "unit_lost", "turn" => turn, "civ" => civ, "unit" => unit)
    )
  end
end
