require "test_helper"

class WorldSizeTest < ActiveSupport::TestCase
  test "research_turns leaves turns untouched up to a small map" do
    assert_equal 100, WorldSize.new("WORLDSIZE_SMALL").research_turns(100)
  end

  test "research_turns stretches turns by the map's research percent" do
    assert_equal 110, WorldSize.new("WORLDSIZE_STANDARD").research_turns(100)
    assert_equal 120, WorldSize.new("WORLDSIZE_LARGE").research_turns(100)
    assert_equal 130, WorldSize.new("WORLDSIZE_HUGE").research_turns(100)
  end

  test "research_turns falls back to a small map for an unknown or missing size" do
    assert_equal 100, WorldSize.new("WORLDSIZE_UNKNOWN").research_turns(100)
    assert_equal 100, WorldSize.new(nil).research_turns(100)
  end

  test "research_turns recognises a size written without the prefix" do
    assert_equal 110, WorldSize.new("Standard").research_turns(100)
  end

  test "tech_cost_per_city shrinks on the two largest maps" do
    assert_equal 0.05, WorldSize.new("WORLDSIZE_STANDARD").tech_cost_per_city
    assert_equal 0.0375, WorldSize.new("WORLDSIZE_LARGE").tech_cost_per_city
    assert_equal 0.025, WorldSize.new("WORLDSIZE_HUGE").tech_cost_per_city
  end

  test "policy_cost_per_city shrinks on the two largest maps" do
    assert_equal 0.10, WorldSize.new("WORLDSIZE_STANDARD").policy_cost_per_city
    assert_equal 0.075, WorldSize.new("WORLDSIZE_LARGE").policy_cost_per_city
    assert_equal 0.05, WorldSize.new("WORLDSIZE_HUGE").policy_cost_per_city
  end

  test "for reads the size off the game" do
    assert_equal 110, WorldSize.for(games(:one)).research_turns(100)
    assert_equal 100, WorldSize.for(games(:two)).research_turns(100)
  end
end
