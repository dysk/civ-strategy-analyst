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

  # The per-city path applies the curve to each real city size instead of to an
  # empire-wide average. Where every city is the same size the two paths agree.
  test "counts souls from real per-city sizes" do
    assert_equal 1_000, Demographics.new(city_sizes: [ 1 ]).souls
    assert_equal 4_856_000, Demographics.new(city_sizes: [ 14, 14, 14 ]).souls
  end

  # x**2.8 is convex, so spreading a population evenly understates it: the same
  # 42 citizens over 3 cities hold more people the more lopsided the empire is.
  test "an uneven empire holds more souls than the averaged figure admits" do
    averaged = Demographics.new(population: 42, cities: 3).souls

    assert_operator Demographics.new(city_sizes: [ 40, 1, 1 ]).souls, :>, averaged
  end

  test "names which branch produced the figure" do
    assert_equal :cities, Demographics.new(city_sizes: [ 14, 14, 14 ]).source
    assert_equal :average, Demographics.new(population: 42, cities: 3).source
  end

  test "an empire with no per-city sizes has no souls to count" do
    assert_equal 0, Demographics.new(city_sizes: []).souls
  end
end
