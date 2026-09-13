require "test_helper"

class OpeningStrategyTest < ActiveSupport::TestCase
  setup do
    @game = Game.create!(name: "Opening Strategy Test Game")
    @seq = 0
  end

  test "branch reports the civ's first policy branch adopted" do
    event("Chile", "policy_branch_adopted", 11, branch: "POLICY_BRANCH_TRADITION")

    assert_equal "POLICY_BRANCH_TRADITION", strategy.branch("Chile")
  end

  test "branch is nil for a civ that never adopted a policy branch" do
    assert_nil strategy.branch("Chile")
  end

  # A civ that survives to a full game closes several trees. Only the
  # first one it opened into is its opening strategy.
  test "branch keeps the opening branch, not one adopted later" do
    event("Chile", "policy_branch_adopted", 11, branch: "POLICY_BRANCH_TRADITION")
    event("Chile", "policy_branch_adopted", 120, branch: "POLICY_BRANCH_RATIONALISM")

    assert_equal "POLICY_BRANCH_TRADITION", strategy.branch("Chile")
  end

  test "closed_opening is nil for a civ that never opened a branch" do
    assert_nil strategy.closed_opening("Chile")
  end

  test "closed_opening reports turns_to_close once the branch's finisher is adopted" do
    event("Chile", "policy_branch_adopted", 11, branch: "POLICY_BRANCH_TRADITION")
    event("Chile", "policy_adopted", 87, policy: "POLICY_TRADITION_FINISHER")

    assert_equal(
      { branch: "POLICY_BRANCH_TRADITION", opened_turn: 11, finisher_policy: "POLICY_TRADITION_FINISHER",
        finished_turn: 87, turns_to_close: 76 },
      strategy.closed_opening("Chile")
    )
  end

  test "closed_opening leaves finished_turn and turns_to_close nil while the tree is still open" do
    event("Chile", "policy_branch_adopted", 11, branch: "POLICY_BRANCH_TRADITION")

    result = strategy.closed_opening("Chile")

    assert_equal "POLICY_TRADITION_FINISHER", result[:finisher_policy]
    assert_nil result[:finished_turn]
    assert_nil result[:turns_to_close]
  end

  # A policy from the same branch is not the branch closing - only its
  # own finisher is.
  test "closed_opening ignores an ordinary policy from the same branch" do
    event("Chile", "policy_branch_adopted", 11, branch: "POLICY_BRANCH_TRADITION")
    event("Chile", "policy_adopted", 20, policy: "POLICY_ARISTOCRACY")

    assert_nil strategy.closed_opening("Chile")[:finished_turn]
  end

  # The finisher id is derived from the branch name rather than looked up
  # in a per-branch table, so a branch whose finisher is missing from a
  # given mod version's ids.yml (Liberty, in db/lekmod/34.15) still
  # resolves correctly - ids.yml carries display names, not whether an
  # event was logged.
  test "closed_opening derives the finisher policy id for Liberty" do
    event("Bolivia", "policy_branch_adopted", 6, branch: "POLICY_BRANCH_LIBERTY")
    event("Bolivia", "policy_adopted", 90, policy: "POLICY_LIBERTY_FINISHER")

    assert_equal 84, strategy.closed_opening("Bolivia")[:turns_to_close]
  end

  test "closed_opening derives the finisher policy id for Honor and Piety" do
    event("Rome", "policy_branch_adopted", 30, branch: "POLICY_BRANCH_HONOR")
    event("Rome", "policy_adopted", 95, policy: "POLICY_HONOR_FINISHER")
    event("Egypt", "policy_branch_adopted", 40, branch: "POLICY_BRANCH_PIETY")
    event("Egypt", "policy_adopted", 140, policy: "POLICY_PIETY_FINISHER")

    assert_equal 65, strategy.closed_opening("Rome")[:turns_to_close]
    assert_equal 100, strategy.closed_opening("Egypt")[:turns_to_close]
  end

  private

  def strategy
    @strategy ||= OpeningStrategy.new(@game)
  end

  def event(civ, event_type, turn, extra = {})
    @seq += 1
    payload = extra.stringify_keys.merge("event" => event_type, "turn" => turn)
    payload["civ"] = civ if civ
    @game.game_events.create!(
      seq: @seq,
      session_index: 0,
      turn: turn,
      event_type: event_type,
      civ: civ,
      payload: payload
    )
  end
end
