require "test_helper"

class DemographicsTest < ActiveSupport::TestCase
  test "a single citizen in a single city is a thousand souls" do
    assert_equal 1_000, Demographics.new(population: 1, cities: 1).souls
  end

  # Population points are not people: the series curve turns a city of twelve
  # into a million souls, which is the figure a chronicle would quote.
  test "counts souls city by city along the growth curve" do
    assert_equal 1_051_000, Demographics.new(population: 12, cities: 1).souls
    assert_equal 4_856_000, Demographics.new(population: 42, cities: 3).souls
  end

  test "an empire that holds no cities has no souls to count" do
    assert_equal 0, Demographics.new(population: 0, cities: 0).souls
  end
end
