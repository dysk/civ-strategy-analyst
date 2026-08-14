require "test_helper"

class OutcomeResolverTest < ActiveSupport::TestCase
  setup do
    @game = Game.create!(name: "Outcome Test Game", max_turns: 100)
    @seq = 0
  end

  test "uses the declared winner and victory_type when given, regardless of game state" do
    snapshot("Rome", 50, score: 100)
    snapshot("Greece", 50, score: 200)

    outcome = OutcomeResolver.new(@game, winner_civ: "Rome", victory_type: "domination").call

    assert_equal(
      { winner_civ: "Rome", victory_type: "domination", in_progress: false, source: :declared },
      outcome
    )
  end

  test "infers the score leader and marks the game in progress when turns remain" do
    snapshot("Rome", 50, score: 300)
    snapshot("Greece", 50, score: 200)

    outcome = OutcomeResolver.new(@game).call

    assert_equal(
      { winner_civ: "Rome", victory_type: nil, in_progress: true, source: :inferred },
      outcome
    )
  end

  test "infers the score leader and marks the game not in progress once max_turns is reached" do
    snapshot("Rome", 100, score: 300)
    snapshot("Greece", 100, score: 200)

    outcome = OutcomeResolver.new(@game).call

    assert_equal(
      { winner_civ: "Rome", victory_type: nil, in_progress: false, source: :inferred },
      outcome
    )
  end

  test "reports in progress with no leader when there are no snapshots yet" do
    outcome = OutcomeResolver.new(@game).call

    assert_equal(
      { winner_civ: nil, victory_type: nil, in_progress: true, source: :inferred },
      outcome
    )
  end

  private

  def snapshot(civ, turn, **metrics)
    @seq += 1
    payload = metrics.stringify_keys.merge("event" => "snapshot", "turn" => turn, "civ" => civ)
    @game.game_events.create!(
      seq: @seq, session_index: 0, turn: turn, event_type: "snapshot", civ: civ, payload: payload
    )
  end
end
