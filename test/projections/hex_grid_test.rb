require "test_helper"

class HexGridTest < ActiveSupport::TestCase
  setup { @grid = HexGrid.new(width: 46) }

  test "a plot is no distance from itself" do
    assert_equal 0, @grid.distance([ 10, 10 ], [ 10, 10 ])
  end

  test "measures distance along a row in whole hexes" do
    assert_equal 4, @grid.distance([ 10, 10 ], [ 14, 10 ])
  end

  test "adds the axes apart when the offsets share a sign" do
    assert_equal 3, @grid.distance([ 10, 10 ], [ 12, 12 ])
  end

  test "takes the longer axis when the offsets have opposite signs" do
    assert_equal 3, @grid.distance([ 10, 10 ], [ 8, 12 ])
  end

  test "measures across the map seam the short way round" do
    assert_equal 10, @grid.distance([ 39, 16 ], [ 1, 20 ])
  end

  test "measures the same distance in either direction" do
    assert_equal @grid.distance([ 1, 20 ], [ 39, 16 ]), @grid.distance([ 39, 16 ], [ 1, 20 ])
  end

  test "goes the long way round on a map too wide to wrap between the plots" do
    assert_equal 40, HexGrid.new(width: 200).distance([ 39, 16 ], [ 1, 20 ])
  end

  test "does not wrap at all when the map width is unknown" do
    assert_equal 40, HexGrid.new(width: nil).distance([ 39, 16 ], [ 1, 20 ])
  end

  test "the compass reads a growing y as north, the way the game lays out its plots" do
    assert_equal "N", @grid.bearing([ 10, 10 ], [ 10, 14 ])
  end

  test "a falling y is south" do
    assert_equal "S", @grid.bearing([ 10, 14 ], [ 10, 10 ])
  end

  test "a growing x is east" do
    assert_equal "E", @grid.bearing([ 10, 10 ], [ 14, 10 ])
  end

  test "a falling x is west" do
    assert_equal "W", @grid.bearing([ 14, 10 ], [ 10, 10 ])
  end

  test "names both axes when neither dominates" do
    assert_equal "NE", @grid.bearing([ 10, 10 ], [ 14, 14 ])
    assert_equal "SW", @grid.bearing([ 14, 14 ], [ 10, 10 ])
  end

  test "drops the shorter axis when the longer one dominates" do
    assert_equal "E", @grid.bearing([ 10, 10 ], [ 20, 11 ])
  end

  test "bearings across the map seam point the short way round" do
    assert_equal "E", @grid.bearing([ 44, 10 ], [ 2, 10 ])
  end

  test "without a known width the seam is not a shortcut" do
    assert_equal "W", HexGrid.new(width: nil).bearing([ 44, 10 ], [ 2, 10 ])
  end

  test "a plot lies in no direction from itself" do
    assert_nil @grid.bearing([ 10, 10 ], [ 10, 10 ])
  end

  test "a plot on the line between two others sits no distance off it" do
    assert_in_delta 0, @grid.offset_from_line([ 10, 20 ], [ 27, 20 ], [ 18, 20 ]), 0.001
  end

  test "measures how far a plot sits off the line between two others" do
    assert_in_delta 3, @grid.offset_from_line([ 10, 20 ], [ 27, 20 ], [ 18, 23 ]), 0.001
  end

  test "reads the offset in the game's metric, so a diagonal pair's flank is nearer than a ruler says" do
    assert_in_delta 5.15, @grid.offset_from_line([ 30, 16 ], [ 29, 29 ], [ 24, 20 ]), 0.01
    assert_in_delta 1.49, @grid.offset_from_line([ 30, 16 ], [ 29, 29 ], [ 28, 24 ]), 0.01
  end

  test "a line of no length leaves the offset at zero" do
    assert_equal 0.0, @grid.offset_from_line([ 10, 20 ], [ 10, 20 ], [ 15, 25 ])
  end
end
