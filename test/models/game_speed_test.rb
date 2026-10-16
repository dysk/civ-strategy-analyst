require "test_helper"

class GameSpeedTest < ActiveSupport::TestCase
  test "turns scales standard turns by two thirds on quick speed" do
    assert_equal 67, GameSpeed.new("GAMESPEED_QUICK").turns(100)
    assert_equal 100, GameSpeed.new("GAMESPEED_QUICK").turns(150)
  end

  test "turns leaves standard turns untouched on standard speed" do
    assert_equal 100, GameSpeed.new("GAMESPEED_STANDARD").turns(100)
  end

  test "turns falls back to standard speed for an unknown speed" do
    assert_equal 150, GameSpeed.new("GAMESPEED_MARATHON").turns(150)
  end

  test "turns falls back to standard speed when the speed is missing" do
    assert_equal 150, GameSpeed.new(nil).turns(150)
  end

  test "turns recognises a quick speed written without the prefix" do
    assert_equal 67, GameSpeed.new("Quick").turns(100)
  end

  test "for reads the speed off the game" do
    assert_equal 67, GameSpeed.for(games(:two)).turns(100)
    assert_equal 100, GameSpeed.for(games(:one)).turns(100)
  end

  # A golden age runs at 80% on quick speed where turns run at 67%, so the
  # general factor would answer 5 for an artist's eight turns.
  test "golden_age_turns scales a golden age by its own factor, not the turn factor" do
    assert_equal 8, GameSpeed.new("GAMESPEED_STANDARD").golden_age_turns(8)
    assert_equal 16, GameSpeed.new("GAMESPEED_MARATHON").golden_age_turns(8)
    assert_equal 10, GameSpeed.new("GAMESPEED_EPIC").golden_age_turns(8)
    assert_equal 6, GameSpeed.new("GAMESPEED_QUICK").golden_age_turns(8)
    assert_equal 4, GameSpeed.new("GAMESPEED_ONLINE").golden_age_turns(8)
  end

  test "golden_age_turns scales a longer base age the same way" do
    assert_equal 10, GameSpeed.new("GAMESPEED_QUICK").golden_age_turns(12)
  end

  test "golden_age_turns falls back to standard speed when the speed is missing" do
    assert_equal 8, GameSpeed.new(nil).golden_age_turns(8)
  end
end
