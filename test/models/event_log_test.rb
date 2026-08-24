require "test_helper"

class EventLogTest < ActiveSupport::TestCase
  setup do
    @game = Game.create!(name: "Event Log Test Game")
    @seq = 0
  end

  test "for loads the game's events in seq order" do
    event("Rome", "snapshot", 2)
    event("Greece", "unit_lost", 1)

    assert_equal [ 1, 2 ], EventLog.for(@game).all.map(&:seq)
  end

  test "of_type keeps only the events of that type" do
    rome = event("Rome", "snapshot", 1)
    event("Greece", "unit_lost", 1)
    egypt = event("Egypt", "snapshot", 2)

    assert_equal [ rome.id, egypt.id ], EventLog.for(@game).of_type("snapshot").map(&:id)
  end

  test "of_type is empty for a type the game never logged" do
    event("Rome", "snapshot", 1)

    assert_empty EventLog.for(@game).of_type("nuclear_detonation")
  end

  test "by groups a type's events under each value of the attribute" do
    rome_first = event("Rome", "snapshot", 1)
    event("Greece", "snapshot", 1)
    rome_second = event("Rome", "snapshot", 2)

    index = EventLog.for(@game).by("snapshot", :civ)

    assert_equal [ rome_first.id, rome_second.id ], index["Rome"].map(&:id)
  end

  test "by ignores events of other types" do
    event("Rome", "snapshot", 1)
    event("Rome", "unit_lost", 1)

    assert_equal 1, EventLog.for(@game).by("snapshot", :civ)["Rome"].size
  end

  # The rescans this replaces were the quadratic ones: every (civ, opponent)
  # pair walked the whole snapshot list. The index has to survive the walk.
  test "by builds each index once and hands back the same one" do
    event("Rome", "snapshot", 1)
    log = EventLog.for(@game)

    assert_same log.by("snapshot", :civ), log.by("snapshot", :civ)
  end

  test "by indexes each type separately" do
    event("Rome", "snapshot", 1)
    event("Rome", "unit_lost", 1)
    log = EventLog.for(@game)

    assert_not_same log.by("snapshot", :civ), log.by("unit_lost", :civ)
  end

  private

  def event(civ, event_type, turn)
    @seq += 1
    @game.game_events.create!(
      seq: @seq, session_index: 0, turn: turn, event_type: event_type, civ: civ,
      payload: { "event" => event_type, "turn" => turn, "civ" => civ }
    )
  end
end
