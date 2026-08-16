require "test_helper"

class EmpireGeometryTest < ActiveSupport::TestCase
  setup do
    @game = Game.create!(name: "Empire Geometry Test Game")
    @seq = 0
  end

  test "a civilization that never held a city has no geometry" do
    founded("Rome", 1, 10, 10)

    assert_equal [], geometry.series("Greece")
  end

  test "a single city has no extent and no spacing" do
    founded("Rome", 1, 10, 10)

    assert_equal(
      [ { turn: 1, cities: 1, span: 0, mean_spacing: nil, elongation: nil } ],
      geometry.series("Rome")
    )
  end

  test "two cities are spaced as far apart as they stand" do
    founded("Rome", 1, 10, 10)
    founded("Rome", 5, 14, 10)

    assert_equal(
      { turn: 5, cities: 2, span: 4, mean_spacing: 4.0, elongation: 1.0 },
      geometry.series("Rome").last
    )
  end

  test "measures the shape of an empire from all of its cities" do
    founded("Chile", 1, 14, 28)
    founded("Chile", 10, 9, 22)
    founded("Chile", 20, 14, 34)

    assert_equal(
      { turn: 20, cities: 3, span: 12, mean_spacing: 6.7, elongation: 1.38 },
      geometry.series("Chile").last
    )
  end

  test "a captured city counts towards its new owner" do
    founded("Rome", 1, 10, 10)
    founded("Greece", 2, 14, 10)
    captured(5, 14, 10, from: "Greece", to: "Rome")

    assert_equal(
      { turn: 5, cities: 2, span: 4, mean_spacing: 4.0, elongation: 1.0 },
      geometry.series("Rome").last
    )
  end

  test "a captured city stops counting towards its old owner" do
    founded("Rome", 1, 10, 10)
    founded("Greece", 2, 14, 10)
    captured(5, 14, 10, from: "Greece", to: "Rome")

    assert_equal(
      { turn: 5, cities: 0, span: nil, mean_spacing: nil, elongation: nil },
      geometry.series("Greece").last
    )
  end

  test "ignores a founding the log recorded without coordinates" do
    @seq += 1
    @game.game_events.create!(
      seq: @seq, session_index: 0, turn: 1, event_type: "city_founded",
      civ: "Rome", payload: { "city" => "Roma" }
    )

    assert_equal [], geometry.series("Rome")
  end

  private

  def geometry
    EmpireGeometry.new(@game, grid: HexGrid.new(width: 46))
  end

  def founded(civ, turn, x, y)
    event(turn, "city_founded", civ: civ, payload: { "x" => x, "y" => y })
  end

  def captured(turn, x, y, from:, to:)
    event(turn, "city_captured", payload: { "x" => x, "y" => y, "old_owner" => from, "new_owner" => to })
  end

  def event(turn, event_type, payload:, civ: nil)
    @seq += 1
    @game.game_events.create!(
      seq: @seq, session_index: 0, turn: turn, event_type: event_type, civ: civ, payload: payload
    )
  end
end
