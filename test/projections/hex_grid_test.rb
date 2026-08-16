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
end
