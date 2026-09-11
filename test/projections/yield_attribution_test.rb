require "test_helper"

class YieldAttributionTest < ActiveSupport::TestCase
  setup do
    @game = Game.create!(name: "Yield Attribution Test Game")
    @seq = 0
  end

  test "series returns turn/total/sources/shortfall for a yield" do
    snapshot("India", 10, science: 40, yield_sources: { science: { cities: 40 } })

    assert_equal(
      [ { turn: 10, total: 40, sources: { cities: 40 }, shortfall: 0 } ],
      YieldAttribution.new(@game).series("India", "science")
    )
  end

  test "shortfall is the gap between the reported total and the summed sources" do
    # A golden age's flat culture bonus isn't attributed to any source.
    snapshot("Netherlands", 25, culture: 7, yield_sources: { culture: { cities: 6 } })

    point = YieldAttribution.new(@game).series("Netherlands", "culture").first

    assert_equal 1, point[:shortfall]
  end

  test "shortfall is zero when a named deficit already accounts for the gap" do
    snapshot("Iroquois", 96, science: 36.97, yield_sources: { science: { cities: 37.5, deficit: -0.53 } })

    point = YieldAttribution.new(@game).series("Iroquois", "science").first

    assert_equal 0, point[:shortfall]
  end

  test "keeps one entry per turn when a turn was snapshotted twice" do
    snapshot("Rome", 10, science: 10, yield_sources: { science: { cities: 10 } })
    snapshot("Rome", 10, science: 15, yield_sources: { science: { cities: 15 } })

    assert_equal [ 15 ], YieldAttribution.new(@game).series("Rome", "science").map { |point| point[:total] }
  end

  test "has nothing to report for a yield with no source data" do
    snapshot("Rome", 10, science: 10, yield_sources: { science: { cities: 10 } })

    assert_equal [], YieldAttribution.new(@game).series("Rome", "culture")
    assert_equal [], YieldAttribution.new(@game).series("Greece", "science")
  end

  test "yields lists the yield names that carry source data for a civ" do
    snapshot("India", 10, yield_sources: { science: { cities: 4 }, faith: {}, tourism: {} })

    assert_equal %w[science], YieldAttribution.new(@game).yields("India")
  end

  test "yields reflects every source-bearing yield seen across turns, not just the last" do
    snapshot("India", 10, yield_sources: { science: { cities: 4 } })
    snapshot("India", 20, yield_sources: { culture: { cities: 8 } })

    assert_equal %w[science culture], YieldAttribution.new(@game).yields("India")
  end

  test "applicable? is false when snapshots carry no yield_sources at all" do
    @game.game_events.create!(
      seq: @seq += 1, session_index: 0, turn: 1, event_type: "snapshot", civ: "Tibet",
      payload: { "event" => "snapshot", "turn" => 1, "civ" => "Tibet" }
    )

    assert_not YieldAttribution.new(@game).applicable?
  end

  test "applicable? is false when yield_sources is always empty" do
    snapshot("Tibet", 1, yield_sources: { science: {}, culture: {} })

    assert_not YieldAttribution.new(@game).applicable?
  end

  test "applicable? is true once a snapshot carries real source data" do
    snapshot("Tibet", 1, yield_sources: { science: { cities: 4 } })

    assert YieldAttribution.new(@game).applicable?
  end

  private

  def snapshot(civ, turn, metrics)
    @game.game_events.create!(
      seq: @seq += 1, session_index: 0, turn: turn, event_type: "snapshot", civ: civ,
      payload: metrics.deep_stringify_keys.merge("event" => "snapshot", "turn" => turn, "civ" => civ)
    )
  end
end
