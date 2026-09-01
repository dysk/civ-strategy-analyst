require "test_helper"

class TurnCalendarTest < ActiveSupport::TestCase
  test "reads the year of a turn from the column of the game's speed" do
    assert_equal "3940 BC", calendar_for("GAMESPEED_QUICK").year_for(1)
    assert_equal "3960 BC", calendar_for("GAMESPEED_STANDARD").year_for(1)
    assert_equal "3975 BC", calendar_for("GAMESPEED_EPIC").year_for(1)
  end

  test "reads years past the era boundary" do
    assert_equal "1960 AD", calendar_for("GAMESPEED_QUICK").year_for(250)
  end

  # The table only covers quick, standard and epic; a marathon game still
  # deserves a chronicle, dated on the closest speed the table knows.
  test "falls back to the standard column for a speed the table does not cover" do
    assert_equal "3960 BC", calendar_for("GAMESPEED_MARATHON").year_for(1)
  end

  test "clamps a turn beyond the end of the table to its last year" do
    assert_equal "2220 AD", calendar_for("GAMESPEED_QUICK").year_for(900)
  end

  test "series maps every turn up to the given one" do
    series = calendar_for("GAMESPEED_QUICK").series(3)

    assert_equal({ 0 => "4000 BC", 1 => "3940 BC", 2 => "3880 BC", 3 => "3820 BC" }, series)
  end

  private

  def calendar_for(speed)
    TurnCalendar.for(Game.create!(name: "Calendar Game", game_speed: speed))
  end
end
