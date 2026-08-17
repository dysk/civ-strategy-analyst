require "test_helper"

class MapBoundsTest < ActiveSupport::TestCase
  setup do
    @game = Game.create!(name: "Map Bounds Test Game")
    @seq = 0
  end

  test "uses the width the log recorded" do
    @game.update!(map_width: 48)
    plot_at(45)

    assert_equal 48, MapBounds.new(@game).width
  end

  test "a recorded width is not an estimate" do
    @game.update!(map_width: 48)

    refute_predicate MapBounds.new(@game), :estimated?
  end

  test "estimates the width from the easternmost plot when the log recorded none" do
    plot_at(45)
    plot_at(12)

    assert_equal 46, MapBounds.new(@game).width
  end

  test "an inferred width is an estimate" do
    plot_at(45)

    assert_predicate MapBounds.new(@game), :estimated?
  end

  test "an unknown width is not an estimate either" do
    refute_predicate MapBounds.new(@game), :estimated?
  end

  test "has no width when nothing in the log carries coordinates" do
    @game.game_events.create!(
      seq: 1, session_index: 0, turn: 1, event_type: "city_founded", payload: { "city" => "Roma" }
    )

    assert_nil MapBounds.new(@game).width
  end

  test "uses the height the log recorded" do
    @game.update!(map_height: 24)
    plot_at(45, y: 20)

    assert_equal 24, MapBounds.new(@game).height
  end

  test "estimates the height from the northernmost plot when the log recorded none" do
    plot_at(1, y: 22)
    plot_at(2, y: 9)

    assert_equal 23, MapBounds.new(@game).height
  end

  test "has no height when nothing in the log carries coordinates" do
    @game.game_events.create!(
      seq: 1, session_index: 0, turn: 1, event_type: "city_founded", payload: { "city" => "Roma" }
    )

    assert_nil MapBounds.new(@game).height
  end

  private

  def plot_at(x, y: 10)
    @seq += 1
    @game.game_events.create!(
      seq: @seq, session_index: 0, turn: 1, event_type: "plot_acquired", payload: { "x" => x, "y" => y }
    )
  end
end
