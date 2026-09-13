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

  # docs/ideal-opening.md "General, any opening": first researched tech
  # should be Mining, to reveal Iron early.
  test "first_tech reports the civ's earliest tech" do
    event(nil, "tech_researched", 1, civs: %w[Chile], tech: "TECH_MINING")

    assert_equal "TECH_MINING", strategy.first_tech("Chile")
  end

  test "first_tech is nil for a civ with no logged tech" do
    assert_nil strategy.first_tech("Chile")
  end

  test "first_tech keeps the earliest tech, not one researched later" do
    event(nil, "tech_researched", 1, civs: %w[Chile], tech: "TECH_MINING")
    event(nil, "tech_researched", 5, civs: %w[Chile], tech: "TECH_POTTERY")

    assert_equal "TECH_MINING", strategy.first_tech("Chile")
  end

  # Mining from a goody hut counts too - it satisfies "have Mining early"
  # just as well as researching it deliberately would.
  test "first_tech credits Mining that arrived via ruins ahead of any researched tech" do
    event("Chile", "tech_from_ruins", 3, tech: "TECH_MINING")
    event(nil, "tech_researched", 6, civs: %w[Chile], tech: "TECH_POTTERY")

    assert_equal "TECH_MINING", strategy.first_tech("Chile")
  end

  # Any other hut tech is a windfall, not a research choice - it doesn't
  # count as what the civ opened with.
  test "first_tech ignores a non-Mining tech that arrived via ruins ahead of any researched tech" do
    event("Chile", "tech_from_ruins", 3, tech: "TECH_POTTERY")
    event(nil, "tech_researched", 6, civs: %w[Chile], tech: "TECH_MINING")

    assert_equal "TECH_MINING", strategy.first_tech("Chile")
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

  # docs/ideal-opening.md "Worker theft — two independent paths", Path B:
  # no war needed, just a bullied city-state - the mod's fixed -50
  # influence penalty for bullying a unit, corroborated by a worker
  # actually appearing for the civ around that turn.
  test "bullied_workers reports a friendship drop matching the worker-bully penalty" do
    event("Chile", "city_state_friendship_changed", 55, city_state: "Zurich", old_friendship: 30, new_friendship: -20)
    event("Chile", "unit_created", 55, unit: "UNIT_WORKER", x: 1, y: 1)

    assert_equal(
      [ { turn: 55, city_state: "Zurich", delta: -50 } ],
      strategy.bullied_workers("Chile")
    )
  end

  test "bullied_workers matches a delta within tolerance of the fixed penalty" do
    event("Chile", "city_state_friendship_changed", 55, city_state: "Zurich", old_friendship: 30, new_friendship: -18)
    event("Chile", "unit_created", 56, unit: "UNIT_WORKER", x: 1, y: 1)

    assert_equal(-48, strategy.bullied_workers("Chile").first[:delta])
  end

  test "bullied_workers ignores a friendship drop that doesn't match the worker-bully penalty" do
    event("Chile", "city_state_friendship_changed", 55, city_state: "Zurich", old_friendship: 30, new_friendship: 15)
    event("Chile", "unit_created", 55, unit: "UNIT_WORKER", x: 1, y: 1)

    assert_equal [], strategy.bullied_workers("Chile")
  end

  test "bullied_workers ignores a matching delta with no corroborating worker" do
    event("Chile", "city_state_friendship_changed", 55, city_state: "Zurich", old_friendship: 30, new_friendship: -20)

    assert_equal [], strategy.bullied_workers("Chile")
  end

  test "bullied_workers ignores a worker that appeared too many turns away from the friendship drop" do
    event("Chile", "city_state_friendship_changed", 55, city_state: "Zurich", old_friendship: 30, new_friendship: -20)
    event("Chile", "unit_created", 60, unit: "UNIT_WORKER", x: 1, y: 1)

    assert_equal [], strategy.bullied_workers("Chile")
  end

  # docs/ideal-opening.md "National College timing": turn 100 on standard
  # speed, reusing GameSpeed rather than a hardcoded per-speed constant.
  test "national_college reports turns_early when built ahead of the standard-speed target" do
    event("Chile", "building_constructed", 90, building: "BUILDING_NATIONAL_COLLEGE", city: "Santiago")

    assert_equal(
      { built_turn: 90, target_turn: 100, turns_early: 10, turns_after_finisher: nil },
      strategy.national_college("Chile")
    )
  end

  test "national_college reports a negative turns_early when built past the target" do
    event("Chile", "building_constructed", 120, building: "BUILDING_NATIONAL_COLLEGE", city: "Santiago")

    assert_equal(-20, strategy.national_college("Chile")[:turns_early])
  end

  # turn 67 on quick speed is the same 2/3 factor GameSpeed already applies
  # elsewhere, not a separate hardcoded number.
  test "national_college scales the target turn to quick speed" do
    @game.update!(game_speed: "GAMESPEED_QUICK")
    event("Chile", "building_constructed", 60, building: "BUILDING_NATIONAL_COLLEGE", city: "Santiago")

    result = strategy.national_college("Chile")

    assert_equal 67, result[:target_turn]
    assert_equal 7, result[:turns_early]
  end

  test "national_college recognizes a civ-unique replacement building" do
    event("Israel", "building_constructed", 95, building: "BUILDING_ISRAEL_NATIONAL_COLLEGE", city: "Jerusalem")

    assert_equal 95, strategy.national_college("Israel")[:built_turn]
  end

  test "national_college leaves built_turn and turns_early nil when never built" do
    assert_equal(
      { built_turn: nil, target_turn: 100, turns_early: nil, turns_after_finisher: nil },
      strategy.national_college("Chile")
    )
  end

  # docs/ideal-opening.md: for a Liberty opening the checklist expects the
  # National College only after the tree closes, so the meaningful figure
  # is turns after the finisher, not turns from game start.
  test "national_college reports turns_after_finisher for a Liberty opening" do
    event("Chile", "policy_branch_adopted", 6, branch: "POLICY_BRANCH_LIBERTY")
    event("Chile", "policy_adopted", 90, policy: "POLICY_LIBERTY_FINISHER")
    event("Chile", "building_constructed", 95, building: "BUILDING_NATIONAL_COLLEGE", city: "Santiago")

    assert_equal(
      { built_turn: 95, target_turn: nil, turns_early: nil, turns_after_finisher: 5 },
      strategy.national_college("Chile")
    )
  end

  test "national_college reports a negative turns_after_finisher when built before the Liberty tree closes" do
    event("Chile", "policy_branch_adopted", 6, branch: "POLICY_BRANCH_LIBERTY")
    event("Chile", "policy_adopted", 90, policy: "POLICY_LIBERTY_FINISHER")
    event("Chile", "building_constructed", 80, building: "BUILDING_NATIONAL_COLLEGE", city: "Santiago")

    assert_equal(-10, strategy.national_college("Chile")[:turns_after_finisher])
  end

  test "national_college leaves turns_after_finisher nil for a Liberty tree not yet closed" do
    event("Chile", "policy_branch_adopted", 6, branch: "POLICY_BRANCH_LIBERTY")
    event("Chile", "building_constructed", 80, building: "BUILDING_NATIONAL_COLLEGE", city: "Santiago")

    assert_nil strategy.national_college("Chile")[:turns_after_finisher]
  end

  # docs/ideal-opening.md "General, any opening": open with 2 scouts. Looks
  # at the first four things the civ builds (unit_trained and
  # building_constructed merged by turn) and grades how many of them, and
  # which ones, were scouts.
  test "opening_scouts reports opened_with_two_scouts when the first two things built are scouts" do
    event("Chile", "unit_trained", 4, unit: "UNIT_SCOUT", city: "Santiago")
    event("Chile", "unit_trained", 7, unit: "UNIT_SCOUT", city: "Santiago")
    event("Chile", "unit_trained", 13, unit: "UNIT_WORKER", city: "Santiago")

    assert_equal(
      { category: :opened_with_two_scouts, scout_count: 2, interrupted_by: nil,
        items: [
          { turn: 4, kind: :unit, id: "UNIT_SCOUT" },
          { turn: 7, kind: :unit, id: "UNIT_SCOUT" },
          { turn: 13, kind: :unit, id: "UNIT_WORKER" }
        ] },
      strategy.opening_scouts("Chile")
    )
  end

  # A shrine between the two scouts still gets a second scout into the
  # window - a broken-up scout run rather than no scout run, and possibly
  # a deliberate pantheon rush rather than a mistake. interrupted_by names
  # exactly what came between the two scouts, so a report can say "shrine"
  # rather than making the reader work it out from the raw items list.
  test "opening_scouts reports two_scouts_interrupted when a scout run is broken up but a second scout still lands in the window" do
    event("Chile", "unit_trained", 4, unit: "UNIT_SCOUT", city: "Santiago")
    event("Chile", "building_constructed", 6, building: "BUILDING_SHRINE", city: "Santiago")
    event("Chile", "unit_trained", 10, unit: "UNIT_SCOUT", city: "Santiago")
    event("Chile", "unit_trained", 14, unit: "UNIT_WORKER", city: "Santiago")

    result = strategy.opening_scouts("Chile")

    assert_equal :two_scouts_interrupted, result[:category]
    assert_equal 2, result[:scout_count]
    assert_equal [ { turn: 6, kind: :building, id: "BUILDING_SHRINE" } ], result[:interrupted_by]
  end

  # Two items separate the scouts here, not one - interrupted_by carries
  # both, in order.
  test "opening_scouts reports every item between the two scouts in interrupted_by, not just the first" do
    event("Chile", "unit_trained", 4, unit: "UNIT_SCOUT", city: "Santiago")
    event("Chile", "building_constructed", 6, building: "BUILDING_SHRINE", city: "Santiago")
    event("Chile", "unit_trained", 8, unit: "UNIT_WARRIOR", city: "Santiago")
    event("Chile", "unit_trained", 10, unit: "UNIT_SCOUT", city: "Santiago")

    assert_equal(
      [ { turn: 6, kind: :building, id: "BUILDING_SHRINE" }, { turn: 8, kind: :unit, id: "UNIT_WARRIOR" } ],
      strategy.opening_scouts("Chile")[:interrupted_by]
    )
  end

  test "opening_scouts reports one_scout when only one scout appears in the first four things built" do
    event("Chile", "unit_trained", 4, unit: "UNIT_SCOUT", city: "Santiago")
    event("Chile", "unit_trained", 8, unit: "UNIT_WARRIOR", city: "Santiago")
    event("Chile", "unit_trained", 12, unit: "UNIT_WORKER", city: "Santiago")
    event("Chile", "building_constructed", 16, building: "BUILDING_MONUMENT", city: "Santiago")

    assert_equal :one_scout, strategy.opening_scouts("Chile")[:category]
    assert_nil strategy.opening_scouts("Chile")[:interrupted_by]
  end

  test "opening_scouts reports no_scouts when no scout appears in the first four things built" do
    event("Chile", "unit_trained", 6, unit: "UNIT_WORKER", city: "Santiago")
    event("Chile", "unit_trained", 12, unit: "UNIT_WARRIOR", city: "Santiago")
    event("Chile", "building_constructed", 16, building: "BUILDING_MONUMENT", city: "Santiago")
    event("Chile", "unit_trained", 20, unit: "UNIT_WORKER", city: "Santiago")

    assert_equal :no_scouts, strategy.opening_scouts("Chile")[:category]
    assert_equal 0, strategy.opening_scouts("Chile")[:scout_count]
    assert_nil strategy.opening_scouts("Chile")[:interrupted_by]
  end

  # A scout arriving after the first four things built is outside the
  # opening and doesn't count, even though it's the civ's only scout.
  test "opening_scouts only looks at the first four things built" do
    event("Chile", "unit_trained", 4, unit: "UNIT_WORKER", city: "Santiago")
    event("Chile", "unit_trained", 8, unit: "UNIT_WARRIOR", city: "Santiago")
    event("Chile", "unit_trained", 12, unit: "UNIT_WORKER", city: "Santiago")
    event("Chile", "building_constructed", 16, building: "BUILDING_MONUMENT", city: "Santiago")
    event("Chile", "unit_trained", 20, unit: "UNIT_SCOUT", city: "Santiago")

    assert_equal :no_scouts, strategy.opening_scouts("Chile")[:category]
  end

  test "opening_scouts works with fewer than four things built" do
    event("Chile", "unit_trained", 4, unit: "UNIT_SCOUT", city: "Santiago")
    event("Chile", "unit_trained", 7, unit: "UNIT_SCOUT", city: "Santiago")

    assert_equal :opened_with_two_scouts, strategy.opening_scouts("Chile")[:category]
  end

  # docs/ideal-opening.md's worker-theft SCOUT_UNITS list (Zabonah,
  # Nubian Bow, Pathfinder) is reused rather than duplicated - a
  # civ-unique replacement still opens with "2 scouts".
  test "opening_scouts recognizes civ-unique scout replacements" do
    event("Shoshone", "unit_trained", 4, unit: "UNIT_SHOSHONE_PATHFINDER", city: "Zuni")
    event("Shoshone", "unit_trained", 7, unit: "UNIT_SHOSHONE_PATHFINDER", city: "Zuni")

    assert_equal :opened_with_two_scouts, strategy.opening_scouts("Shoshone")[:category]
  end

  # docs/ideal-opening.md "Wide: close city spacing" - EmpireGeometry
  # already computes mean_spacing on every founding or capture; this
  # samples it as of the same early-game boundary EarlyGame uses to mark
  # the end of the opening.
  test "city_spacing reports mean_spacing as of the early-game boundary" do
    event(nil, "tech_researched", 15, civs: %w[Chile], tech: "TECH_EDUCATION")
    event("Chile", "building_constructed", 20, building: "BUILDING_WORKSHOP", city: "Santiago")
    event("Chile", "city_founded", 1, x: 10, y: 10)
    event("Chile", "city_founded", 5, x: 14, y: 10)

    assert_equal({ turn: 5, cities: 2, mean_spacing: 4.0 }, strategy.city_spacing("Chile"))
  end

  # A city founded after the opening already closed says nothing about how
  # the opening was played.
  test "city_spacing ignores a city founded after the early-game boundary" do
    event(nil, "tech_researched", 15, civs: %w[Chile], tech: "TECH_EDUCATION")
    event("Chile", "building_constructed", 20, building: "BUILDING_WORKSHOP", city: "Santiago")
    event("Chile", "city_founded", 1, x: 10, y: 10)
    event("Chile", "city_founded", 30, x: 14, y: 10)

    assert_equal({ turn: 1, cities: 1, mean_spacing: nil }, strategy.city_spacing("Chile"))
  end

  test "city_spacing is nil-shaped for a civ that never founded a city" do
    assert_equal({ turn: nil, cities: nil, mean_spacing: nil }, strategy.city_spacing("Chile"))
  end

  # docs/ideal-opening.md's tall/wide split. City count at the early-game
  # boundary is the primary signal - it's what the checklist's own bands
  # (tall 4-6, wide 6-10) actually measure. Opening branch only steps in
  # to break the shared boundary at 6 cities, and only for the two
  # branches with a settled style in this mod.
  test "playstyle classifies tall from city count alone" do
    boundary("Chile", 20)
    found_cities("Chile", 5)

    assert_equal :tall, strategy.playstyle("Chile")[:style]
  end

  test "playstyle classifies wide from city count alone" do
    boundary("Chile", 20)
    found_cities("Chile", 8)

    assert_equal :wide, strategy.playstyle("Chile")[:style]
  end

  test "playstyle breaks a tied city count of 6 toward tall for a Tradition opening" do
    boundary("Chile", 20)
    found_cities("Chile", 6)
    event("Chile", "policy_branch_adopted", 3, branch: "POLICY_BRANCH_TRADITION")

    assert_equal :tall, strategy.playstyle("Chile")[:style]
  end

  test "playstyle breaks a tied city count of 6 toward wide for a Liberty opening" do
    boundary("Chile", 20)
    found_cities("Chile", 6)
    event("Chile", "policy_branch_adopted", 3, branch: "POLICY_BRANCH_LIBERTY")

    assert_equal :wide, strategy.playstyle("Chile")[:style]
  end

  # Honor and Piety are played both tall and wide in this mod, so neither
  # settles a tied city count - the verdict stays nil rather than guessed.
  test "playstyle leaves a tied city count of 6 unresolved for a Honor opening" do
    boundary("Chile", 20)
    found_cities("Chile", 6)
    event("Chile", "policy_branch_adopted", 3, branch: "POLICY_BRANCH_HONOR")

    assert_nil strategy.playstyle("Chile")[:style]
  end

  test "playstyle leaves a tied city count of 6 unresolved for a Piety opening" do
    boundary("Chile", 20)
    found_cities("Chile", 6)
    event("Chile", "policy_branch_adopted", 3, branch: "POLICY_BRANCH_PIETY")

    assert_nil strategy.playstyle("Chile")[:style]
  end

  test "playstyle leaves a tied city count of 6 unresolved with no opening branch at all" do
    boundary("Chile", 20)
    found_cities("Chile", 6)

    assert_nil strategy.playstyle("Chile")[:style]
  end

  test "playstyle reports city_count, mean_spacing, and branch alongside the verdict" do
    boundary("Chile", 20)
    found_cities("Chile", 5)
    event("Chile", "policy_branch_adopted", 3, branch: "POLICY_BRANCH_PIETY")

    result = strategy.playstyle("Chile")

    assert_equal 5, result[:city_count]
    assert_equal "POLICY_BRANCH_PIETY", result[:branch]
    assert_not_nil result[:mean_spacing]
  end

  test "playstyle is unresolved for a civ that never founded a city" do
    result = strategy.playstyle("Chile")

    assert_nil result[:style]
    assert_nil result[:city_count]
  end

  # docs/ideal-opening.md "Good wonder targets": the checklist's wonder
  # list splits tall from wide, plus a universal bucket for wonders that
  # don't care about style at all. Which style bucket applies comes from
  # playstyle, not branch directly.
  test "good_wonders grades a tall civ against the universal and tall buckets" do
    boundary("Chile", 20)
    found_cities("Chile", 5)
    wonder("Chile", 10, "BUILDING_TEMPLE_ARTEMIS")
    wonder("Chile", 12, "BUILDING_GREAT_LIBRARY")

    result = strategy.good_wonders("Chile")

    assert_includes result[:targets], "BUILDING_TEMPLE_ARTEMIS"
    assert_includes result[:targets], "BUILDING_GREAT_LIBRARY"
    refute_includes result[:targets], "BUILDING_PYRAMID"
    assert_equal %w[BUILDING_TEMPLE_ARTEMIS BUILDING_GREAT_LIBRARY], result[:built]
  end

  test "good_wonders grades a wide civ against the universal and wide buckets" do
    boundary("Chile", 20)
    found_cities("Chile", 8)
    wonder("Chile", 10, "BUILDING_COLOSSUS")
    wonder("Chile", 12, "BUILDING_PYRAMID")

    result = strategy.good_wonders("Chile")

    assert_includes result[:targets], "BUILDING_COLOSSUS"
    assert_includes result[:targets], "BUILDING_PYRAMID"
    refute_includes result[:targets], "BUILDING_GREAT_LIBRARY"
    assert_equal %w[BUILDING_COLOSSUS BUILDING_PYRAMID], result[:built]
  end

  # Honor and Piety don't settle a tied city count, so neither the tall
  # nor the wide list applies - only the universal bucket does.
  test "good_wonders only grades against the universal bucket when style is unresolved" do
    boundary("Chile", 20)
    found_cities("Chile", 6)
    event("Chile", "policy_branch_adopted", 3, branch: "POLICY_BRANCH_HONOR")
    wonder("Chile", 10, "BUILDING_ORACLE")
    wonder("Chile", 12, "BUILDING_GREAT_LIBRARY")

    result = strategy.good_wonders("Chile")

    assert_includes result[:targets], "BUILDING_ORACLE"
    refute_includes result[:targets], "BUILDING_GREAT_LIBRARY"
    refute_includes result[:targets], "BUILDING_PYRAMID"
    assert_equal %w[BUILDING_ORACLE], result[:built]
  end

  # A wonder from the wrong style's list still isn't a target, even
  # though it was built.
  test "good_wonders excludes a wonder that was built but isn't on an applicable list" do
    boundary("Chile", 20)
    found_cities("Chile", 5)
    wonder("Chile", 10, "BUILDING_STONEHENGE")

    assert_equal [], strategy.good_wonders("Chile")[:built]
  end

  private

  def boundary(civ, turn)
    event(nil, "tech_researched", turn - 5, civs: [ civ ], tech: "TECH_EDUCATION")
    event(civ, "building_constructed", turn, building: "BUILDING_WORKSHOP", city: "Capital")
  end

  def found_cities(civ, count)
    count.times { |i| event(civ, "city_founded", i + 1, x: 10 + i, y: 10) }
  end

  def wonder(civ, turn, building)
    event(civ, "building_constructed", turn, building: building, wonder: "world", city: "Capital")
  end

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
