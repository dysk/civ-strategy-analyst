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

  # docs/ideal-opening.md "Worker theft — two independent paths", Path A:
  # a war declared on a city-state whose first casualty is its worker,
  # taken alive rather than killed.
  test "worker_raids reports a war that opened by capturing a city-state worker" do
    session_started(city_states: %w[Zurich])
    event(nil, "war_declared", 40, attacker_team: 1, attacker_civs: %w[Chile], defender_team: 2, defender_civs: %w[Zurich])
    event("Zurich", "unit_lost", 42, unit: "UNIT_WORKER", killed_by: "Chile")
    event(nil, "peace_made", 44, team_a: 1, team_a_civs: %w[Chile], team_b: 2, team_b_civs: %w[Zurich])

    assert_equal(
      [ { city_state: "Zurich", declared_turn: 40, captured_turn: 42, peace_turn: 44 } ],
      strategy.worker_raids("Chile")
    )
  end

  test "worker_raids leaves peace_turn nil for a raid that never made peace" do
    session_started(city_states: %w[Zurich])
    event(nil, "war_declared", 40, attacker_team: 1, attacker_civs: %w[Chile], defender_team: 2, defender_civs: %w[Zurich])
    event("Zurich", "unit_lost", 42, unit: "UNIT_WORKER", killed_by: "Chile")

    assert_nil strategy.worker_raids("Chile").first[:peace_turn]
  end

  # The war precondition matters: a war against a full civilization that
  # happens to cost it a worker is not a city-state raid.
  test "worker_raids ignores a war against a civilization that is not a city-state" do
    event(nil, "war_declared", 40, attacker_team: 1, attacker_civs: %w[Chile], defender_team: 2, defender_civs: %w[Greece])
    event("Greece", "unit_lost", 42, unit: "UNIT_WORKER", killed_by: "Chile")

    assert_equal [], strategy.worker_raids("Chile")
  end

  test "worker_raids ignores a war the civ fought as defender" do
    session_started(city_states: %w[Zurich])
    event(nil, "war_declared", 40, attacker_team: 1, attacker_civs: %w[Zurich], defender_team: 2, defender_civs: %w[Chile])
    event("Zurich", "unit_lost", 42, unit: "UNIT_WORKER", killed_by: "Chile")

    assert_equal [], strategy.worker_raids("Chile")
  end

  test "worker_raids ignores a war against a city-state where nothing changed hands" do
    session_started(city_states: %w[Zurich])
    event(nil, "war_declared", 40, attacker_team: 1, attacker_civs: %w[Chile], defender_team: 2, defender_civs: %w[Zurich])
    event(nil, "peace_made", 44, team_a: 1, team_a_civs: %w[Chile], team_b: 2, team_b_civs: %w[Zurich])

    assert_equal [], strategy.worker_raids("Chile")
  end

  # A soldier traded first makes this a real war against the city-state,
  # not a declare-war-grab-worker-make-peace raid, even though a worker
  # was taken later in the same war.
  test "worker_raids ignores a war whose first casualty was a soldier, not the worker" do
    session_started(city_states: %w[Zurich])
    event(nil, "war_declared", 40, attacker_team: 1, attacker_civs: %w[Chile], defender_team: 2, defender_civs: %w[Zurich])
    event(nil, "unit_killed", 41, killer: "Zurich", victim: "Chile", unit: "UNIT_WARRIOR")
    event("Zurich", "unit_lost", 42, unit: "UNIT_WORKER", killed_by: "Chile")

    assert_equal [], strategy.worker_raids("Chile")
  end

  private

  def strategy
    @strategy ||= OpeningStrategy.new(@game)
  end

  def session_started(city_states:)
    @seq += 1
    payload = { "event" => "session_started", "turn" => 0, "city_states" => city_states.map { |civ| { "civ" => civ } } }
    @game.game_events.create!(seq: @seq, session_index: 0, turn: 0, event_type: "session_started", payload: payload)
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
