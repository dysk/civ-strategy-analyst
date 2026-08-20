require "test_helper"

class EarlyGameHelperTest < ActionView::TestCase
  test "names the milestone that ended the early game, without internal prefixes" do
    row = { reason: :milestone, milestone_turn: 77,
            milestone: { tech: "TECH_METAL_CASTING", building: "BUILDING_UNIVERSITY" } }

    assert_equal "METAL_CASTING + UNIVERSITY", early_game_milestone(row)
  end

  test "carries the turn of a milestone reached after the deadline" do
    row = { reason: :deadline, milestone_turn: 111,
            milestone: { tech: "TECH_EDUCATION", building: "BUILDING_WORKSHOP" } }

    assert_equal "EDUCATION + WORKSHOP (t. 111)", early_game_milestone(row)
  end

  test "has nothing to name for a civ that reached neither milestone" do
    assert_nil early_game_milestone({ reason: :deadline, milestone_turn: nil, milestone: nil })
  end
end
