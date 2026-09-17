require "test_helper"

class GameDurationTest < ActiveSupport::TestCase
  setup do
    @game = Game.create!(name: "Game Duration Test Game")
    @seq = 0
  end

  test "turns played is the highest turn reached" do
    event(turn: 0, t_log: 100.0)
    event(turn: 12, t_log: 200.0)

    assert_equal 12, GameDuration.new(@game).turns_played
  end

  test "seconds played is the span between a session's first and last logged moment" do
    event(session_index: 0, t_log: 1000.0)
    event(session_index: 0, t_log: 1090.5)

    assert_equal 90.5, GameDuration.new(@game).seconds_played
  end

  test "sums the span of every session, since t_log resets when a session does" do
    event(session_index: 0, t_log: 1000.0)
    event(session_index: 0, t_log: 1100.0)
    event(session_index: 1, t_log: 50.0)
    event(session_index: 1, t_log: 80.0)

    assert_equal 130.0, GameDuration.new(@game).seconds_played
  end

  test "a session logged only once contributes no time" do
    event(session_index: 0, t_log: 500.0)

    assert_equal 0, GameDuration.new(@game).seconds_played
  end

  test "an event with no t_log does not break the total" do
    event(session_index: 0, t_log: 1000.0)
    @seq += 1
    @game.game_events.create!(
      seq: @seq, session_index: 0, turn: 1, event_type: "city_founded", payload: { "city" => "Roma" }
    )
    event(session_index: 0, t_log: 1050.0)

    assert_equal 50.0, GameDuration.new(@game).seconds_played
  end

  test "has no seconds played when nothing in the log carries a t_log" do
    @seq += 1
    @game.game_events.create!(
      seq: @seq, session_index: 0, turn: 1, event_type: "city_founded", payload: { "city" => "Roma" }
    )

    assert_nil GameDuration.new(@game).seconds_played
  end

  private

  def event(turn: 1, session_index: 0, t_log:)
    @seq += 1
    @game.game_events.create!(
      seq: @seq, session_index: session_index, turn: turn, event_type: "snapshot",
      payload: { "t_log" => t_log }
    )
  end
end
