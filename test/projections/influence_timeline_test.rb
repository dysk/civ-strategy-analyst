require "test_helper"

class InfluenceTimelineTest < ActiveSupport::TestCase
  setup do
    @game = Game.create!(name: "Influence Test Game")
    @seq = 0
  end

  test "series returns turn/points/level/trend for a civ-opponent pair over time" do
    snapshot("Rome", 10, influence: [
      { civ: "Greece", points: 100, level: "INFLUENCE_LEVEL_FAMILIAR", trend: "INFLUENCE_TREND_RISING" }
    ])
    snapshot("Rome", 20, influence: [
      { civ: "Greece", points: 320, level: "INFLUENCE_LEVEL_INFLUENTIAL", trend: "INFLUENCE_TREND_RISING" }
    ])

    assert_equal(
      [
        { turn: 10, points: 100, level: "INFLUENCE_LEVEL_FAMILIAR", trend: "INFLUENCE_TREND_RISING" },
        { turn: 20, points: 320, level: "INFLUENCE_LEVEL_INFLUENTIAL", trend: "INFLUENCE_TREND_RISING" }
      ],
      InfluenceTimeline.new(@game).series("Rome", "Greece")
    )
  end

  test "keeps one entry per turn when a turn was snapshotted twice" do
    snapshot("Rome", 10, influence: [ { civ: "Greece", points: 100, level: "INFLUENCE_LEVEL_FAMILIAR", trend: "INFLUENCE_TREND_RISING" } ])
    snapshot("Rome", 10, influence: [ { civ: "Greece", points: 110, level: "INFLUENCE_LEVEL_FAMILIAR", trend: "INFLUENCE_TREND_RISING" } ])

    assert_equal [ 110 ], InfluenceTimeline.new(@game).series("Rome", "Greece").map { |point| point[:points] }
  end

  test "opponents lists the civs a given civ has influence data on" do
    snapshot("Rome", 10, influence: [
      { civ: "Greece", points: 100, level: "INFLUENCE_LEVEL_FAMILIAR", trend: "INFLUENCE_TREND_STATIC" },
      { civ: "Egypt", points: 40, level: "INFLUENCE_LEVEL_EXOTIC", trend: "INFLUENCE_TREND_STATIC" }
    ])

    assert_equal %w[Greece Egypt], InfluenceTimeline.new(@game).opponents("Rome")
  end

  test "level_changes reports only the turns where the level flips" do
    snapshot("Rome", 10, influence: [ { civ: "Greece", points: 100, level: "INFLUENCE_LEVEL_FAMILIAR", trend: "INFLUENCE_TREND_RISING" } ])
    snapshot("Rome", 20, influence: [ { civ: "Greece", points: 150, level: "INFLUENCE_LEVEL_FAMILIAR", trend: "INFLUENCE_TREND_RISING" } ])
    snapshot("Rome", 30, influence: [ { civ: "Greece", points: 320, level: "INFLUENCE_LEVEL_INFLUENTIAL", trend: "INFLUENCE_TREND_RISING" } ])

    assert_equal(
      [ { turn: 30, from: "INFLUENCE_LEVEL_FAMILIAR", to: "INFLUENCE_LEVEL_INFLUENTIAL" } ],
      InfluenceTimeline.new(@game).level_changes("Rome", "Greece")
    )
  end

  test "latest_points_delta is the change between the last two known points" do
    snapshot("Rome", 10, influence: [ { civ: "Greece", points: 100, level: "INFLUENCE_LEVEL_FAMILIAR", trend: "INFLUENCE_TREND_RISING" } ])
    snapshot("Rome", 20, influence: [ { civ: "Greece", points: 150, level: "INFLUENCE_LEVEL_FAMILIAR", trend: "INFLUENCE_TREND_RISING" } ])

    assert_equal 50, InfluenceTimeline.new(@game).latest_points_delta("Rome", "Greece")
  end

  test "has nothing to report for a pair with no influence data" do
    snapshot("Rome", 10, influence: [ { civ: "Greece", points: 100, level: "INFLUENCE_LEVEL_FAMILIAR", trend: "INFLUENCE_TREND_RISING" } ])

    assert_equal [], InfluenceTimeline.new(@game).series("Rome", "Egypt")
    assert_nil InfluenceTimeline.new(@game).latest_points_delta("Rome", "Egypt")
  end

  private

  def snapshot(civ, turn, metrics)
    @game.game_events.create!(
      seq: @seq += 1, session_index: 0, turn: turn, event_type: "snapshot", civ: civ,
      payload: metrics.deep_stringify_keys.merge("event" => "snapshot", "turn" => turn, "civ" => civ)
    )
  end
end
