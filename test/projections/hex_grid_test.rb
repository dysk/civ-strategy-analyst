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
end
