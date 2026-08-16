require "test_helper"

class CapitalsTimelineTest < ActiveSupport::TestCase
  setup do
    @game = Game.create!(name: "Capitals Test Game")
    @seq = 0
  end

  test "series returns turn, the capitals list and the held count for a civ" do
    snapshot("Rome", 100, capitals: %w[Rome Athens])

    assert_equal(
      [ { turn: 100, capitals: %w[Rome Athens], capitals_held: 2 } ],
      CapitalsTimeline.new(@game).series("Rome")
    )
  end

  test "capitals_held returns turn/value pairs like a MetricSeries value series" do
    snapshot("Rome", 50, capitals: %w[Rome])
    snapshot("Rome", 100, capitals: %w[Rome Athens Sparta])

    assert_equal [ [ 50, 1 ], [ 100, 3 ] ], CapitalsTimeline.new(@game).capitals_held("Rome")
  end

  test "keeps one entry per turn when a turn was snapshotted twice" do
    snapshot("Rome", 100, capitals: %w[Rome])
    snapshot("Rome", 100, capitals: %w[Rome Athens])

    assert_equal [ [ 100, 2 ] ], CapitalsTimeline.new(@game).capitals_held("Rome")
  end

  test "leaves a snapshot with no capitals field out of the series" do
    snapshot("Rome", 100, score: 300)

    assert_equal [], CapitalsTimeline.new(@game).series("Rome")
  end

  test "has nothing to report for a civ with no snapshots" do
    snapshot("Rome", 100, capitals: %w[Rome])

    assert_nil CapitalsTimeline.new(@game).latest("Greece")
  end

  private

  def snapshot(civ, turn, metrics)
    @game.game_events.create!(
      seq: @seq += 1, session_index: 0, turn: turn, event_type: "snapshot", civ: civ,
      payload: metrics.stringify_keys.merge("event" => "snapshot", "turn" => turn, "civ" => civ)
    )
  end
end
