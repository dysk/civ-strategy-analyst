require "test_helper"

class GameEventTest < ActiveSupport::TestCase
  test "valid with seq, turn, event_type and a game" do
    event = GameEvent.new(game: games(:one), seq: 2, session_index: 0, turn: 5, event_type: "tech_researched")
    assert event.valid?
  end

  test "invalid without a seq" do
    event = GameEvent.new(game: games(:one), seq: nil, session_index: 0, turn: 5, event_type: "tech_researched")
    assert_not event.valid?
    assert_includes event.errors[:seq], "can't be blank"
  end

  test "invalid without a turn" do
    event = GameEvent.new(game: games(:one), seq: 2, session_index: 0, turn: nil, event_type: "tech_researched")
    assert_not event.valid?
    assert_includes event.errors[:turn], "can't be blank"
  end

  test "invalid without an event_type" do
    event = GameEvent.new(game: games(:one), seq: 2, session_index: 0, turn: 5, event_type: nil)
    assert_not event.valid?
    assert_includes event.errors[:event_type], "can't be blank"
  end

  test "invalid with duplicate seq in the same game" do
    duplicate = GameEvent.new(game: games(:one), seq: game_events(:one).seq, session_index: 0, turn: 5, event_type: "tech_researched")
    assert_not duplicate.valid?
    assert_includes duplicate.errors[:seq], "has already been taken"
  end

  test "valid with the same seq in a different game" do
    event = GameEvent.new(game: games(:two), seq: game_events(:one).seq, session_index: 0, turn: 5, event_type: "tech_researched")
    assert event.valid?
  end

  test "defaults payload to an empty hash" do
    event = GameEvent.create!(game: games(:one), seq: 99, session_index: 0, turn: 5, event_type: "tech_researched")
    assert_equal({}, event.payload)
  end

  test "belongs to a game" do
    assert_equal games(:one), game_events(:one).game
  end
end
