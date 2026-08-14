require "test_helper"

class MetricSeriesTest < ActiveSupport::TestCase
  setup do
    @game = Game.create!(name: "Metrics Test Game")
    @seq = 0

    # Turn 1: Rome ahead
    snapshot("Rome", 1, score: 100, science: 10)
    snapshot("Greece", 1, score: 90, science: 12)

    # Turn 2: Greece takes the lead
    snapshot("Rome", 2, score: 120, science: 25)
    snapshot("Greece", 2, score: 130, science: 20)

    # Turn 3: Greece still ahead, no change
    snapshot("Rome", 3, score: 125, science: 40)
    snapshot("Greece", 3, score: 128, science: 33)

    # Turn 4: Rome takes the lead back
    snapshot("Rome", 4, score: 200, science: 60)
    snapshot("Greece", 4, score: 140, science: 50)

    @series = MetricSeries.new(@game)
  end

  test "values returns turn/value pairs for a civ in turn order" do
    assert_equal [ [ 1, 100 ], [ 2, 120 ], [ 3, 125 ], [ 4, 200 ] ], @series.values("score", "Rome")
  end

  test "values works for a different metric" do
    assert_equal [ [ 1, 12 ], [ 2, 20 ], [ 3, 33 ], [ 4, 50 ] ], @series.values("science", "Greece")
  end

  test "deltas returns the change from the previous snapshot, skipping the first turn" do
    assert_equal [ [ 2, 20 ], [ 3, 5 ], [ 4, 75 ] ], @series.deltas("score", "Rome")
  end

  test "ranking orders civs by metric value descending for each turn" do
    ranking = @series.ranking("score")

    assert_equal %w[Rome Greece], ranking[1]
    assert_equal %w[Greece Rome], ranking[2]
    assert_equal %w[Greece Rome], ranking[3]
    assert_equal %w[Rome Greece], ranking[4]
  end

  test "leader_changes reports only the turns where the top civ changes" do
    assert_equal(
      [
        { turn: 2, from: "Rome", to: "Greece" },
        { turn: 4, from: "Greece", to: "Rome" }
      ],
      @series.leader_changes("score")
    )
  end

  test "final_ranking returns the ranking at the last known turn" do
    assert_equal %w[Rome Greece], @series.final_ranking("score")
  end

  test "final_ranking is empty when there is no data" do
    game = Game.create!(name: "Empty Game")
    assert_equal [], MetricSeries.new(game).final_ranking("score")
  end

  test "leader_changes is empty when the same civ leads throughout" do
    game = Game.create!(name: "No Change Game")
    seq = 0
    create_snapshot(game, "Rome", 1, { score: 100 }, seq += 1)
    create_snapshot(game, "Greece", 1, { score: 50 }, seq += 1)
    create_snapshot(game, "Rome", 2, { score: 150 }, seq += 1)
    create_snapshot(game, "Greece", 2, { score: 60 }, seq += 1)

    assert_equal [], MetricSeries.new(game).leader_changes("score")
  end

  private

  def snapshot(civ, turn, **metrics)
    @seq += 1
    create_snapshot(@game, civ, turn, metrics, @seq)
  end

  def create_snapshot(game, civ, turn, metrics, seq)
    game.game_events.create!(
      seq: seq,
      session_index: 0,
      turn: turn,
      event_type: "snapshot",
      civ: civ,
      payload: metrics.stringify_keys.merge("event" => "snapshot", "turn" => turn, "civ" => civ)
    )
  end
end
