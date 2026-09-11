require "test_helper"

class KeyMomentDetectorTest < ActiveSupport::TestCase
  setup do
    @game = Game.create!(name: "Key Moment Test Game")
    @seq = 0
  end

  test "wars reports declaration, territory changes and what each side lost" do
    event(nil, "war_declared", 10, attacker_team: 1, attacker_civs: %w[Rome], defender_team: 2, defender_civs: %w[Greece])
    event(nil, "city_captured", 12, city: "Athens", old_owner: "Greece", new_owner: "Rome")
    killed("Rome", "Greece", "UNIT_ARCHER", 15)
    killed("Greece", "Rome", "UNIT_WARRIOR", 20)
    event(nil, "peace_made", 30, team_a: 1, team_a_civs: %w[Rome], team_b: 2, team_b_civs: %w[Greece])

    moments = detector.wars

    assert_equal 1, moments.size
    war = moments.first

    assert_equal :war, war[:type]
    assert_equal 10, war[:turn]
    assert_equal 30, war[:turn_peace]
    assert_equal %w[Rome], war[:attacker_civs]
    assert_equal %w[Greece], war[:defender_civs]
    assert_equal({ "Rome" => 1 }, war[:cities_captured])
    assert_equal({ "UNIT_ARCHER" => 1 }, war[:toll]["Greece"][:loss_types])
  end

  # What a war opened with is as close as the log comes to saying what it
  # was about, and it is the whole story of a war fought over one worker.
  test "wars names what the war opened with" do
    event(nil, "war_declared", 10, attacker_team: 1, attacker_civs: %w[Rome], defender_team: 2, defender_civs: %w[Greece])
    event("Greece", "unit_lost", 12, unit: "UNIT_WORKER", killed_by: "Rome")

    assert_equal({ turn: 12, civ: "Greece", unit: "UNIT_WORKER", by: "Rome",
                   fate: :captured, kind: :civilian },
                 detector.wars.first[:first_blood])
  end

  test "wars leaves the toll empty when no side lost anything" do
    event(nil, "war_declared", 10, attacker_team: 1, attacker_civs: %w[Rome], defender_team: 2, defender_civs: %w[Greece])
    event("Greece", "unit_lost", 15, unit: "UNIT_CARAVAN")
    event(nil, "peace_made", 30, team_a: 1, team_a_civs: %w[Rome], team_b: 2, team_b_civs: %w[Greece])

    war = detector.wars.first

    assert_equal 0, war[:toll]["Greece"][:losses]
    assert_nil war[:first_blood]
  end

  test "wars sizes a war by what it cost" do
    event(nil, "war_declared", 10, attacker_team: 1, attacker_civs: %w[Rome], defender_team: 2, defender_civs: %w[Greece])
    event("Greece", "unit_lost", 12, unit: "UNIT_WORKER", killed_by: "Rome")

    assert_equal :raid, detector.wars.first[:scale]
  end

  # A toll says what a war cost and nothing about what it was fought
  # with. The armies say the rest: crossbows against gatling guns is a
  # different war from an even one, whatever the count of the dead.
  test "wars reports the armies each side brought to it" do
    event("Rome", "unit_created", 5, unit: "UNIT_ARCHER")
    event("Greece", "unit_created", 5, unit: "UNIT_SPEARMAN")
    event(nil, "war_declared", 10, attacker_team: 1, attacker_civs: %w[Rome], defender_team: 2, defender_civs: %w[Greece])
    killed("Rome", "Greece", "UNIT_SPEARMAN", 15)

    assert_equal({ "UNIT_ARCHER" => 1 }, detector.wars.first[:forces]["Rome"][:opening])
  end

  # A war in which nobody exchanged a blow has no order of battle worth
  # reading: who stood where is not its story, the absence of it is.
  test "wars leaves the order of battle off a war nobody fought" do
    event("Rome", "unit_created", 5, unit: "UNIT_ARCHER")
    event(nil, "war_declared", 10, attacker_team: 1, attacker_civs: %w[Rome], defender_team: 2, defender_civs: %w[Greece])
    event(nil, "peace_made", 30, team_a: 1, team_a_civs: %w[Rome], team_b: 2, team_b_civs: %w[Greece])

    assert_nil detector.wars.first[:forces]
  end

  # A city-state's units barely reach the log, so its side of a war reads
  # as an army of nothing. That is a fact about the record and not about
  # its strength, and a reader handed it draws the wrong one.
  test "wars leaves out a side the log records no army for" do
    event("Rome", "unit_created", 5, unit: "UNIT_ARCHER")
    event(nil, "war_declared", 10, attacker_team: 1, attacker_civs: %w[Rome], defender_team: 2, defender_civs: %w[Ragusa])
    killed("Rome", "Ragusa", "UNIT_SPEARMAN", 15)

    assert_equal %w[Rome], detector.wars.first[:forces].keys
  end

  test "wars leaves the order of battle off a war the log records no armies for" do
    event(nil, "war_declared", 10, attacker_team: 1, attacker_civs: %w[Ragusa], defender_team: 2, defender_civs: %w[Zurich])
    killed("Ragusa", "Zurich", "UNIT_SPEARMAN", 15)

    assert_nil detector.wars.first[:forces]
  end

  test "wars ignores losses and captures outside the war window" do
    event(nil, "war_declared", 10, attacker_team: 1, attacker_civs: %w[Rome], defender_team: 2, defender_civs: %w[Greece])
    event(nil, "peace_made", 30, team_a: 1, team_a_civs: %w[Rome], team_b: 2, team_b_civs: %w[Greece])
    killed("Rome", "Greece", "UNIT_ARCHER", 5)
    event(nil, "city_captured", 40, city: "Sparta", old_owner: "Greece", new_owner: "Rome")

    war = detector.wars.first

    assert_equal 0, war[:toll]["Greece"][:losses]
    assert_equal({}, war[:cities_captured])
  end

  test "leader_changes reports score and science leadership crossovers together, sorted by turn" do
    snapshot("Rome", 101, score: 100, science: 20)
    snapshot("Greece", 101, score: 90, science: 10)

    # Score flips to Greece; science leader (Rome) unchanged.
    snapshot("Rome", 102, score: 100, science: 20)
    snapshot("Greece", 102, score: 110, science: 15)

    # Score leader unchanged (Greece still ahead); science flips to Greece.
    snapshot("Rome", 103, score: 100, science: 12)
    snapshot("Greece", 103, score: 110, science: 25)

    moments = detector.leader_changes

    assert_equal(
      [
        { type: :leader_change, metric: "score", turn: 102, from: "Rome", to: "Greece" },
        { type: :leader_change, metric: "science", turn: 103, from: "Rome", to: "Greece" }
      ],
      moments
    )
  end

  test "leader_changes excludes crossovers within the first 100 turns for non-quick speeds" do
    @game.update!(game_speed: "GAMESPEED_STANDARD")
    snapshot("Rome", 1, score: 100)
    snapshot("Greece", 1, score: 90)
    snapshot("Rome", 100, score: 100)
    snapshot("Greece", 100, score: 110)
    snapshot("Rome", 101, score: 120)
    snapshot("Greece", 101, score: 110)

    moments = detector.leader_changes

    assert_equal(
      [ { type: :leader_change, metric: "score", turn: 101, from: "Greece", to: "Rome" } ],
      moments
    )
  end

  test "leader_changes excludes crossovers within the first 67 turns for GAMESPEED_QUICK" do
    @game.update!(game_speed: "GAMESPEED_QUICK")
    snapshot("Rome", 1, score: 100)
    snapshot("Greece", 1, score: 90)
    snapshot("Rome", 67, score: 100)
    snapshot("Greece", 67, score: 110)
    snapshot("Rome", 68, score: 120)
    snapshot("Greece", 68, score: 110)

    moments = detector.leader_changes

    assert_equal(
      [ { type: :leader_change, metric: "score", turn: 68, from: "Greece", to: "Rome" } ],
      moments
    )
  end

  test "leader_changes also reports production leadership crossovers" do
    snapshot("Rome", 101, score: 100, science: 20, production: 30)
    snapshot("Greece", 101, score: 90, science: 10, production: 20)

    snapshot("Rome", 102, score: 100, science: 20, production: 30)
    snapshot("Greece", 102, score: 90, science: 10, production: 40)

    moments = detector.leader_changes

    assert_includes moments, { type: :leader_change, metric: "production", turn: 102, from: "Rome", to: "Greece" }
  end

  test "era_leads reports which civs reached each era first, sorted by turn" do
    event(nil, "era_entered", 40, team: 1, civs: %w[Rome], era: "ERA_CLASSICAL")
    event(nil, "era_entered", 45, team: 2, civs: %w[Greece], era: "ERA_CLASSICAL")

    # Both teams reach the medieval era on the same turn: a tie.
    event(nil, "era_entered", 90, team: 1, civs: %w[Rome], era: "ERA_MEDIEVAL")
    event(nil, "era_entered", 90, team: 3, civs: %w[Egypt], era: "ERA_MEDIEVAL")
    event(nil, "era_entered", 95, team: 2, civs: %w[Greece], era: "ERA_MEDIEVAL")

    moments = detector.era_leads

    assert_equal(
      [
        { type: :era_lead, turn: 40, era: "ERA_CLASSICAL", civs: %w[Rome] },
        { type: :era_lead, turn: 90, era: "ERA_MEDIEVAL", civs: %w[Rome Egypt] }
      ],
      moments
    )
  end

  test "religion_foundings reports each founding in order, tagged with how early it was and which beliefs were chosen" do
    event("Greece", "religion_founded", 50, holy_city: "Athens", religion: "RELIGION_POLYTHEISM", beliefs: %w[BELIEF_X])
    event("Rome", "religion_founded", 35, holy_city: "Roma", religion: "RELIGION_JUDAISM", beliefs: %w[BELIEF_Y BELIEF_Z])

    moments = detector.religion_foundings

    assert_equal(
      [
        { type: :religion_founded, turn: 35, civ: "Rome", religion: "RELIGION_JUDAISM", holy_city: "Roma",
          beliefs: %w[BELIEF_Y BELIEF_Z], order: 1 },
        { type: :religion_founded, turn: 50, civ: "Greece", religion: "RELIGION_POLYTHEISM", holy_city: "Athens",
          beliefs: %w[BELIEF_X], order: 2 }
      ],
      moments
    )
  end

  test "pantheon_foundings reports each pantheon with the belief chosen" do
    event("Greece", "pantheon_founded", 8, city: "Athens", belief: "BELIEF_GODDESS_OF_HARVEST")
    event("Rome", "pantheon_founded", 5, city: "Roma", belief: "BELIEF_GOD_OF_THE_SEA")

    moments = detector.pantheon_foundings

    assert_equal(
      [
        { type: :pantheon_founded, turn: 5, civ: "Rome", city: "Roma", belief: "BELIEF_GOD_OF_THE_SEA" },
        { type: :pantheon_founded, turn: 8, civ: "Greece", city: "Athens", belief: "BELIEF_GODDESS_OF_HARVEST" }
      ],
      moments
    )
  end

  test "religion_enhancements reports the beliefs chosen when a religion is enhanced" do
    event("Rome", "religion_enhanced", 90, religion: "RELIGION_JUDAISM", beliefs: %w[BELIEF_Y])
    event("Greece", "religion_enhanced", 85, religion: "RELIGION_POLYTHEISM", beliefs: %w[BELIEF_X BELIEF_W])

    moments = detector.religion_enhancements

    assert_equal(
      [
        { type: :religion_enhanced, turn: 85, civ: "Greece", religion: "RELIGION_POLYTHEISM", beliefs: %w[BELIEF_X BELIEF_W] },
        { type: :religion_enhanced, turn: 90, civ: "Rome", religion: "RELIGION_JUDAISM", beliefs: %w[BELIEF_Y] }
      ],
      moments
    )
  end

  test "reformations reports the belief chosen for a reformation" do
    event("Rome", "reformation_added", 130, religion: "RELIGION_JUDAISM", belief: "BELIEF_APOSTOLIC_PALACE")
    event("Greece", "reformation_added", 120, religion: "RELIGION_POLYTHEISM", belief: "BELIEF_JESUIT_EDUCATION")

    moments = detector.reformations

    assert_equal(
      [
        { type: :reformation_added, turn: 120, civ: "Greece", religion: "RELIGION_POLYTHEISM", belief: "BELIEF_JESUIT_EDUCATION" },
        { type: :reformation_added, turn: 130, civ: "Rome", religion: "RELIGION_JUDAISM", belief: "BELIEF_APOSTOLIC_PALACE" }
      ],
      moments
    )
  end

  test "ideology_unlocks reports when a civ unlocks an ideology branch, ignoring non-ideology branches" do
    event("Chile", "policy_branch_unlocked", 141, branch: "POLICY_BRANCH_FREEDOM")
    event("Egypt", "policy_branch_unlocked", 111, branch: "POLICY_BRANCH_EXPLORATION")

    moments = detector.ideology_unlocks

    assert_equal(
      [ { type: :ideology_unlocked, turn: 141, civ: "Chile", ideology: "POLICY_BRANCH_FREEDOM" } ],
      moments
    )
  end

  test "ideology_adoptions reports which ideology each civ adopted, ignoring non-ideology branches" do
    event("Rome", "policy_branch_adopted", 200, branch: "POLICY_BRANCH_FREEDOM")
    event("Greece", "policy_branch_adopted", 210, branch: "POLICY_BRANCH_ORDER")
    event("Egypt", "policy_branch_adopted", 190, branch: "POLICY_BRANCH_TRADITION")

    moments = detector.ideology_adoptions

    assert_equal(
      [
        { type: :ideology_adopted, turn: 200, civ: "Rome", ideology: "POLICY_BRANCH_FREEDOM" },
        { type: :ideology_adopted, turn: 210, civ: "Greece", ideology: "POLICY_BRANCH_ORDER" }
      ],
      moments
    )
  end

  test "tenet_adoptions reports policies picked after a civ adopts an ideology, tagged with which ideology" do
    event("Rome", "policy_adopted", 180, policy: "POLICY_LEGALISM")          # before the ideology, not a tenet
    event("Rome", "policy_branch_adopted", 200, branch: "POLICY_BRANCH_FREEDOM")
    event("Rome", "policy_adopted", 205, policy: "POLICY_CIVIL_SOCIETY")     # tenet
    event("Rome", "policy_adopted", 220, policy: "POLICY_UNIVERSAL_SUFFRAGE") # tenet
    event("Greece", "policy_adopted", 50, policy: "POLICY_REPUBLIC")         # never adopts an ideology

    moments = detector.tenet_adoptions

    assert_equal(
      [
        { type: :tenet_adopted, turn: 205, civ: "Rome", ideology: "POLICY_BRANCH_FREEDOM", tenet: "POLICY_CIVIL_SOCIETY" },
        { type: :tenet_adopted, turn: 220, civ: "Rome", ideology: "POLICY_BRANCH_FREEDOM", tenet: "POLICY_UNIVERSAL_SUFFRAGE" }
      ],
      moments
    )
  end

  test "policy_branch_adoptions reports which branch each civ adopted, excluding ideology branches" do
    event("Rome", "policy_branch_adopted", 11, branch: "POLICY_BRANCH_TRADITION")
    event("Greece", "policy_branch_adopted", 6, branch: "POLICY_BRANCH_LIBERTY")
    event("Egypt", "policy_branch_adopted", 200, branch: "POLICY_BRANCH_FREEDOM")

    moments = detector.policy_branch_adoptions

    assert_equal(
      [
        { type: :policy_branch_adopted, turn: 6, civ: "Greece", branch: "POLICY_BRANCH_LIBERTY" },
        { type: :policy_branch_adopted, turn: 11, civ: "Rome", branch: "POLICY_BRANCH_TRADITION" }
      ],
      moments
    )
  end

  test "policy_branch_completions reports when a civ has adopted every policy in a known branch" do
    event("Rome", "policy_adopted", 14, policy: "POLICY_LEGALISM")
    event("Rome", "policy_adopted", 21, policy: "POLICY_LANDED_ELITE")
    event("Rome", "policy_adopted", 33, policy: "POLICY_MONARCHY")
    event("Rome", "policy_adopted", 46, policy: "POLICY_OLIGARCHY")
    event("Rome", "policy_adopted", 57, policy: "POLICY_ARISTOCRACY")

    event("Greece", "policy_adopted", 10, policy: "POLICY_REPUBLIC")
    event("Greece", "policy_adopted", 14, policy: "POLICY_COLLECTIVE_RULE")
    event("Greece", "policy_adopted", 24, policy: "POLICY_CITIZENSHIP")

    moments = detector.policy_branch_completions

    assert_equal(
      [ { type: :policy_branch_completed, turn: 57, civ: "Rome", branch: "POLICY_BRANCH_TRADITION" } ],
      moments
    )
  end

  test "policy_branch_completions detects completion even when picks from multiple branches are interleaved" do
    event("Rome", "policy_adopted", 10, policy: "POLICY_REPUBLIC")           # Liberty
    event("Rome", "policy_adopted", 20, policy: "POLICY_ORGANIZED_RELIGION") # Piety
    event("Rome", "policy_adopted", 30, policy: "POLICY_COLLECTIVE_RULE")    # Liberty
    event("Rome", "policy_adopted", 40, policy: "POLICY_CITIZENSHIP")        # Liberty
    event("Rome", "policy_adopted", 50, policy: "POLICY_REPRESENTATION")     # Liberty
    event("Rome", "policy_adopted", 60, policy: "POLICY_MERITOCRACY")        # Liberty, completes the branch

    moments = detector.policy_branch_completions

    assert_equal(
      [ { type: :policy_branch_completed, turn: 60, civ: "Rome", branch: "POLICY_BRANCH_LIBERTY" } ],
      moments
    )
  end

  test "army_power_swings flags single-turn drops and gains beyond 15%, ignores smaller moves" do
    snapshot("Rome", 101, military_might: 1000, gold: 0)
    snapshot("Rome", 102, military_might: 900, gold: 0)  # -10%, below threshold
    snapshot("Rome", 103, military_might: 700, gold: 0)  # -22.2%, collapse
    snapshot("Rome", 104, military_might: 850, gold: 0)  # +21.4%, surge (different direction, doesn't merge with the collapse)
    snapshot("Rome", 105, military_might: 900, gold: 0)  # +5.9%, below threshold

    snapshot("Greece", 101, military_might: 500, gold: 0)
    snapshot("Greece", 102, military_might: 500, gold: 0)

    moments = detector.army_power_swings

    assert_equal(
      [
        { type: :army_power_collapse, civ: "Rome", turn: 102, turn_end: 103, from: 900, to: 700, pct_change: -0.222 },
        { type: :army_power_surge, civ: "Rome", turn: 103, turn_end: 104, from: 700, to: 850, pct_change: 0.214 }
      ],
      moments
    )
  end

  test "army_power_swings ignores a jump the treasury made on its own" do
    snapshot("Rome", 101, military_might: 1000, gold: 0)
    snapshot("Rome", 102, military_might: 1300, gold: 900)  # same army, 900 gold inflates might by 30%

    assert_empty detector.army_power_swings
  end

  test "army_power_swings sees a collapse a filling treasury hides" do
    snapshot("Rome", 101, military_might: 1000, gold: 0)
    snapshot("Rome", 102, military_might: 1040, gold: 900)  # might rose, power fell from 1000 to 800

    assert_equal(
      [ { type: :army_power_collapse, civ: "Rome", turn: 101, turn_end: 102,
          from: 1000, to: 800, pct_change: -0.2 } ],
      detector.army_power_swings
    )
  end

  test "army_power_swings skips a civilization whose snapshots carry no treasury" do
    snapshot("Rome", 101, military_might: 1000)
    snapshot("Rome", 102, military_might: 500)

    assert_empty detector.army_power_swings
  end

  test "army_power_swings merges consecutive same-direction swings into a single run" do
    snapshot("Rome", 101, military_might: 300, gold: 0)
    snapshot("Rome", 102, military_might: 360, gold: 0)  # +20%, surge
    snapshot("Rome", 103, military_might: 450, gold: 0)  # +25%, surge, chains onto the previous turn
    snapshot("Rome", 104, military_might: 460, gold: 0)  # +2.2%, below threshold, ends the run

    moments = detector.army_power_swings

    assert_equal(
      [ { type: :army_power_surge, civ: "Rome", turn: 101, turn_end: 103, from: 300, to: 450, pct_change: 0.5 } ],
      moments
    )
  end

  test "army_power_swings excludes swings within the first 100 turns for non-quick speeds" do
    @game.update!(game_speed: "GAMESPEED_STANDARD")
    snapshot("Rome", 1, military_might: 300, gold: 0)
    snapshot("Rome", 2, military_might: 200, gold: 0)   # -33%, within the grace period
    snapshot("Rome", 101, military_might: 210, gold: 0) # +5% vs turn 2, below threshold
    snapshot("Rome", 102, military_might: 126, gold: 0) # -40%, past the grace period

    moments = detector.army_power_swings

    assert_equal(
      [ { type: :army_power_collapse, civ: "Rome", turn: 101, turn_end: 102, from: 210, to: 126, pct_change: -0.4 } ],
      moments
    )
  end

  test "army_power_swings excludes swings within the first 67 turns for GAMESPEED_QUICK" do
    @game.update!(game_speed: "GAMESPEED_QUICK")
    snapshot("Rome", 1, military_might: 300, gold: 0)
    snapshot("Rome", 2, military_might: 200, gold: 0)  # -33%, within the grace period
    snapshot("Rome", 68, military_might: 210, gold: 0) # +5% vs turn 2, below threshold
    snapshot("Rome", 69, military_might: 126, gold: 0) # -40%, past the grace period

    moments = detector.army_power_swings

    assert_equal(
      [ { type: :army_power_collapse, civ: "Rome", turn: 68, turn_end: 69, from: 210, to: 126, pct_change: -0.4 } ],
      moments
    )
  end

  test "happiness_swings flags single-turn changes of at least 10 points, ignores smaller moves" do
    snapshot("Rome", 101, happiness: 5)
    snapshot("Rome", 102, happiness: -8)  # -13, collapse
    snapshot("Rome", 103, happiness: -1)  # +7, below threshold
    snapshot("Rome", 104, happiness: 12)  # +13, surge

    moments = detector.happiness_swings

    assert_equal(
      [
        { type: :happiness_collapse, civ: "Rome", turn: 101, turn_end: 102, from: 5, to: -8, delta: -13 },
        { type: :happiness_surge, civ: "Rome", turn: 103, turn_end: 104, from: -1, to: 12, delta: 13 }
      ],
      moments
    )
  end

  test "happiness_swings merges consecutive same-direction swings into a single run" do
    snapshot("Rome", 101, happiness: 0)
    snapshot("Rome", 102, happiness: 15)  # +15, surge
    snapshot("Rome", 103, happiness: 30)  # +15, surge, chains onto the previous turn
    snapshot("Rome", 104, happiness: 32)  # +2, below threshold, ends the run

    moments = detector.happiness_swings

    assert_equal(
      [ { type: :happiness_surge, civ: "Rome", turn: 101, turn_end: 103, from: 0, to: 30, delta: 30 } ],
      moments
    )
  end

  test "happiness_swings excludes swings within the early-game grace period" do
    @game.update!(game_speed: "GAMESPEED_STANDARD")
    snapshot("Rome", 1, happiness: 20)
    snapshot("Rome", 2, happiness: 5)    # -15, within the grace period
    snapshot("Rome", 101, happiness: 5)
    snapshot("Rome", 102, happiness: -10) # -15, past the grace period

    moments = detector.happiness_swings

    assert_equal(
      [ { type: :happiness_collapse, civ: "Rome", turn: 101, turn_end: 102, from: 5, to: -10, delta: -15 } ],
      moments
    )
  end

  test "unhappiness_periods reports contiguous stretches where happiness stays below zero" do
    snapshot("Rome", 1, happiness: 5)
    snapshot("Rome", 2, happiness: -3)
    snapshot("Rome", 3, happiness: -1)
    snapshot("Rome", 4, happiness: 2)
    snapshot("Rome", 5, happiness: -6)
    snapshot("Rome", 6, happiness: 8)

    moments = detector.unhappiness_periods

    assert_equal(
      [
        { type: :unhappiness_period, civ: "Rome", turn: 2, turn_end: 3 },
        { type: :unhappiness_period, civ: "Rome", turn: 5, turn_end: 5 }
      ],
      moments
    )
  end

  test "unhappiness_periods reports an open-ended stretch that never recovers by the last snapshot" do
    snapshot("Rome", 1, happiness: 5)
    snapshot("Rome", 2, happiness: -3)
    snapshot("Rome", 3, happiness: -7)

    moments = detector.unhappiness_periods

    assert_equal(
      [ { type: :unhappiness_period, civ: "Rome", turn: 2, turn_end: 3 } ],
      moments
    )
  end

  test "snowballs flags a civ whose growth pace stays well ahead for 15+ turns" do
    # A grows 10/turn, B grows 2/turn, every turn from 1 to 30: A's 10-turn
    # rolling pace is consistently ahead once the window fills at turn 11,
    # and stays ahead through the last turn (a 19-turn stretch).
    (1..30).each do |t|
      snapshot("A", t, score: t * 10)
      snapshot("B", t, score: t * 2)
    end

    moments = detector.snowballs("score")

    assert_equal(
      [ { type: :snowball, civ: "A", turn: 11, turn_end: 30, duration_turns: 19 } ],
      moments
    )
  end

  test "snowballs finds nothing in a metric the snapshots never recorded" do
    (1..30).each do |t|
      snapshot("A", t, score: t * 10)
      snapshot("B", t, score: t * 2)
    end

    assert_equal [], detector.snowballs("population")
  end

  test "snowballs is generic over the metric name (e.g. population)" do
    (1..30).each do |t|
      snapshot("A", t, population: t * 10)
      snapshot("B", t, population: t * 2)
    end

    moments = detector.snowballs("population")

    assert_equal(
      [ { type: :snowball, civ: "A", turn: 11, turn_end: 30, duration_turns: 19 } ],
      moments
    )
  end

  test "snowballs ignores pace-leadership stretches shorter than 15 turns" do
    # Leadership alternates every few turns, never holding for 15+ turns.
    (1..30).each do |t|
      leader_is_a = (t / 5).even?
      snapshot("A", t, score: leader_is_a ? t * 10 : t * 3)
      snapshot("B", t, score: leader_is_a ? t * 3 : t * 10)
    end

    assert_equal [], detector.snowballs("score")
  end

  test "nuclear_detonations lists each detonation sorted by turn" do
    event("Rome", "nuclear_detonation", 200, city: "Athens", war: true, bystander_war: false)
    event("Greece", "nuclear_detonation", 190, city: "Roma", war: true, bystander_war: false)

    moments = detector.nuclear_detonations

    assert_equal(
      [
        { type: :nuclear_detonation, turn: 190, civ: "Greece", city: "Roma", bystander_war: false },
        { type: :nuclear_detonation, turn: 200, civ: "Rome", city: "Athens", bystander_war: false }
      ],
      moments
    )
  end

  test "city_state_ally_takeovers reports only ally changes that steal from an existing ally" do
    # First alliance ever (no previous ally) is not a takeover.
    event(nil, "city_state_ally_changed", 10, city_state: "Cahokia", old_ally: nil, new_ally: "Rome")
    # Rome loses Cahokia's alliance to Greece: a takeover.
    event(nil, "city_state_ally_changed", 40, city_state: "Cahokia", old_ally: "Rome", new_ally: "Greece")
    # Losing an ally with no replacement is not a takeover either.
    event(nil, "city_state_ally_changed", 60, city_state: "Cahokia", old_ally: "Greece", new_ally: nil)

    moments = detector.city_state_ally_takeovers

    assert_equal(
      [ { type: :city_state_ally_takeover, turn: 40, city_state: "Cahokia", from: "Rome", to: "Greece" } ],
      moments
    )
  end

  test "influence_level_reached reports only transitions into Influential or Dominant" do
    snapshot("Rome", 10, influence: [ { "civ" => "Greece", "points" => 50, "level" => "INFLUENCE_LEVEL_EXOTIC", "trend" => "INFLUENCE_TREND_RISING" } ])
    snapshot("Rome", 20, influence: [ { "civ" => "Greece", "points" => 150, "level" => "INFLUENCE_LEVEL_POPULAR", "trend" => "INFLUENCE_TREND_RISING" } ])
    snapshot("Rome", 30, influence: [ { "civ" => "Greece", "points" => 320, "level" => "INFLUENCE_LEVEL_INFLUENTIAL", "trend" => "INFLUENCE_TREND_RISING" } ])
    snapshot("Rome", 40, influence: [ { "civ" => "Greece", "points" => 500, "level" => "INFLUENCE_LEVEL_DOMINANT", "trend" => "INFLUENCE_TREND_RISING" } ])

    moments = detector.influence_level_reached

    assert_equal(
      [
        { type: :influence_level_reached, turn: 30, civ: "Rome", opponent: "Greece", level: "INFLUENCE_LEVEL_INFLUENTIAL" },
        { type: :influence_level_reached, turn: 40, civ: "Rome", opponent: "Greece", level: "INFLUENCE_LEVEL_DOMINANT" }
      ],
      moments
    )
  end

  test "influence_level_reached covers every civ-opponent pair, sorted by turn" do
    snapshot("Rome", 10, influence: [ { "civ" => "Greece", "points" => 50, "level" => "INFLUENCE_LEVEL_EXOTIC", "trend" => "INFLUENCE_TREND_RISING" } ])
    snapshot("Rome", 40, influence: [ { "civ" => "Greece", "points" => 500, "level" => "INFLUENCE_LEVEL_DOMINANT", "trend" => "INFLUENCE_TREND_RISING" } ])
    snapshot("Greece", 10, influence: [ { "civ" => "Rome", "points" => 60, "level" => "INFLUENCE_LEVEL_EXOTIC", "trend" => "INFLUENCE_TREND_STATIC" } ])
    snapshot("Greece", 20, influence: [ { "civ" => "Rome", "points" => 310, "level" => "INFLUENCE_LEVEL_INFLUENTIAL", "trend" => "INFLUENCE_TREND_RISING" } ])

    moments = detector.influence_level_reached

    assert_equal(
      [
        { type: :influence_level_reached, turn: 20, civ: "Greece", opponent: "Rome", level: "INFLUENCE_LEVEL_INFLUENTIAL" },
        { type: :influence_level_reached, turn: 40, civ: "Rome", opponent: "Greece", level: "INFLUENCE_LEVEL_DOMINANT" }
      ],
      moments
    )
  end

  test "cultural_victory_imminent reports the first turn a civ is influential on all but one living major" do
    snapshot("Rome", 10, civs_influential_on: 1)
    snapshot("Greece", 10, civs_influential_on: 0)
    snapshot("Egypt", 10, civs_influential_on: 0)

    snapshot("Rome", 20, civs_influential_on: 2)
    snapshot("Greece", 20, civs_influential_on: 0)
    snapshot("Egypt", 20, civs_influential_on: 0)

    # Stays imminent on turn 30 too, but only the first crossing is reported.
    snapshot("Rome", 30, civs_influential_on: 2)
    snapshot("Greece", 30, civs_influential_on: 0)
    snapshot("Egypt", 30, civs_influential_on: 0)

    moments = detector.cultural_victory_imminent

    assert_equal(
      [ { type: :cultural_victory_imminent, turn: 20, civ: "Rome", civs_influential_on: 2, living_majors: 3 } ],
      moments
    )
  end

  test "cultural_victory_imminent needs at least two living majors to mean anything" do
    snapshot("Rome", 10, civs_influential_on: 0)

    assert_equal [], detector.cultural_victory_imminent
  end

  test "congress_host_changes reports each host transition, sorted by turn" do
    event(nil, "congress_host_changed", 90, old_host: nil, new_host: "Rome")
    event(nil, "congress_host_changed", 150, old_host: "Rome", new_host: "Greece")

    assert_equal(
      [
        { type: :congress_host_change, turn: 90, from: nil, to: "Rome" },
        { type: :congress_host_change, turn: 150, from: "Rome", to: "Greece" }
      ],
      detector.congress_host_changes
    )
  end

  test "united_nations_formed reports the turn the UN was formed" do
    event(nil, "united_nations_formed", 220)

    assert_equal [ { type: :united_nations_formed, turn: 220 } ], detector.united_nations_formed
  end

  # A passed irrelevance vote removes a player from victory contention and
  # from the session - it reshapes every standing that follows.
  test "players_declared_irrelevant reports each passed irrelevance vote with its subject, proposer and tally" do
    event(nil, "mp_proposal_result", 120, type: "irrelevance", status: "passed",
      owner: "India", subject: "Rome", yes_votes: 4, no_votes: 1)
    event(nil, "mp_proposal_result", 90, type: "irrelevance", status: "passed",
      owner: "Greece", subject: "Egypt", yes_votes: 3, no_votes: 0)

    assert_equal(
      [
        { type: :player_declared_irrelevant, turn: 90, civ: "Egypt", proposer: "Greece", yes_votes: 3, no_votes: 0 },
        { type: :player_declared_irrelevant, turn: 120, civ: "Rome", proposer: "India", yes_votes: 4, no_votes: 1 }
      ],
      detector.players_declared_irrelevant
    )
  end

  test "players_declared_irrelevant ignores a failed vote and votes that are not about irrelevance" do
    event(nil, "mp_proposal_result", 100, type: "irrelevance", status: "failed",
      owner: "India", subject: "Rome", yes_votes: 2, no_votes: 3)
    event(nil, "mp_proposal_result", 110, type: "concede", status: "passed",
      owner: "Rome", subject: "India", yes_votes: 5, no_votes: 0)

    assert_equal [], detector.players_declared_irrelevant
  end

  test "diplomatic_victory_imminent reports the first turn a civ's delegate votes meet the threshold" do
    congress_snapshot(50, host: "Rome",
      delegates: [ { "civ" => "Rome", "votes" => 5 }, { "civ" => "Greece", "votes" => 10 } ], votes_needed: 12)
    congress_snapshot(74, host: "Rome",
      delegates: [ { "civ" => "Rome", "votes" => 5 }, { "civ" => "Greece", "votes" => 12 } ], votes_needed: 12)
    # Stays past the threshold, but only the first crossing is reported.
    congress_snapshot(98, host: "Rome",
      delegates: [ { "civ" => "Rome", "votes" => 5 }, { "civ" => "Greece", "votes" => 13 } ], votes_needed: 12)

    assert_equal(
      [ { type: :diplomatic_victory_imminent, turn: 74, civ: "Greece", votes: 12, votes_needed: 12 } ],
      detector.diplomatic_victory_imminent
    )
  end

  test "resolutions_passed lists each passed resolution with its proposer, sorted by turn" do
    event(nil, "resolution_proposed", 10, resolution: "RESOLUTION_WORLD_FAIR", proposer: "Rome", repeal: false)
    event(nil, "resolution_passed", 15, resolution: "RESOLUTION_WORLD_FAIR")
    event(nil, "resolution_proposed", 20, resolution: "RESOLUTION_PLAYER_EMBARGO", proposer: "Greece", repeal: false)
    event(nil, "resolution_failed", 25, resolution: "RESOLUTION_PLAYER_EMBARGO")

    assert_equal(
      [ { type: :resolution_passed, turn: 15, resolution: "RESOLUTION_WORLD_FAIR", proposer: "Rome",
          repeal: false } ],
      detector.resolutions_passed
    )
  end

  test "resolutions_passed marks a passed repeal proposal as a repeal" do
    event(nil, "resolution_proposed", 10, resolution: "RESOLUTION_CULTURAL_HERITAGE_SITES", proposer: "Rome", repeal: false)
    event(nil, "resolution_passed", 15, resolution: "RESOLUTION_CULTURAL_HERITAGE_SITES")
    event(nil, "resolution_proposed", 20, resolution: "RESOLUTION_CULTURAL_HERITAGE_SITES", proposer: "Greece", repeal: true)
    event(nil, "resolution_passed", 25, resolution: "RESOLUTION_CULTURAL_HERITAGE_SITES")
    event(nil, "resolution_repealed", 25, resolution: "RESOLUTION_CULTURAL_HERITAGE_SITES")

    assert_equal(
      [ false, true ],
      detector.resolutions_passed.map { |moment| moment[:repeal] }
    )
  end

  test "capital_control_changes reports capitals gained and lost, sorted by turn" do
    snapshot("Rome", 50, capitals: %w[Rome])
    snapshot("Rome", 100, capitals: %w[Rome Athens])
    snapshot("Rome", 150, capitals: %w[Athens])

    assert_equal(
      [
        { type: :capital_gained, civ: "Rome", original_owner: "Athens", turn: 100 },
        { type: :capital_lost, civ: "Rome", original_owner: "Rome", turn: 150 }
      ],
      detector.capital_control_changes
    )
  end

  test "capital_control_changes dates a capture from the capture itself, not the snapshot that catches up to it" do
    snapshot("Rome", 99, capitals: %w[Rome])
    event(nil, "city_captured", 100, city: "Athens", old_owner: "Greece", new_owner: "Rome", capital: true)
    snapshot("Rome", 101, capitals: %w[Rome Athens])

    gained = detector.capital_control_changes.find { |moment| moment[:type] == :capital_gained }

    assert_equal 100, gained[:turn]
  end

  test "capital_control_changes still finds the capture when it shares a turn with the stale snapshot" do
    snapshot("Rome", 100, capitals: %w[Rome])
    event(nil, "city_captured", 100, city: "Athens", old_owner: "Greece", new_owner: "Rome", capital: true)
    snapshot("Rome", 101, capitals: %w[Rome Athens])

    gained = detector.capital_control_changes.find { |moment| moment[:type] == :capital_gained }

    assert_equal 100, gained[:turn]
  end

  test "apollo_completions reports the first turn a civ's Apollo Program count goes positive" do
    snapshot("Rome", 100, spaceship: { apollo: 0, booster: 0, cockpit: 0, stasis_chamber: 0, engine: 0 })
    snapshot("Rome", 120, spaceship: { apollo: 1, booster: 0, cockpit: 0, stasis_chamber: 0, engine: 0 })

    assert_equal [ { type: :apollo_completed, civ: "Rome", turn: 120 } ], detector.apollo_completions
  end

  test "spaceship_part_assemblies reports each increase in a part's count" do
    snapshot("Rome", 100, spaceship: { apollo: 1, booster: 0, cockpit: 0, stasis_chamber: 0, engine: 0 })
    snapshot("Rome", 120, spaceship: { apollo: 1, booster: 1, cockpit: 0, stasis_chamber: 0, engine: 0 })
    snapshot("Rome", 140, spaceship: { apollo: 1, booster: 2, cockpit: 1, stasis_chamber: 0, engine: 0 })

    assert_equal(
      [
        { type: :spaceship_part_assembled, civ: "Rome", turn: 120, part: "booster", count: 1 },
        { type: :spaceship_part_assembled, civ: "Rome", turn: 140, part: "booster", count: 2 },
        { type: :spaceship_part_assembled, civ: "Rome", turn: 140, part: "cockpit", count: 1 }
      ],
      detector.spaceship_part_assemblies
    )
  end

  test "science_victory_imminent reports the first turn assembly reaches 5 of the 6 required parts" do
    snapshot("Rome", 100, spaceship: { apollo: 1, booster: 2, cockpit: 1, stasis_chamber: 0, engine: 1 })
    snapshot("Rome", 120, spaceship: { apollo: 1, booster: 3, cockpit: 1, stasis_chamber: 0, engine: 1 })

    assert_equal(
      [ { type: :science_victory_imminent, civ: "Rome", turn: 120, parts_assembled: 5 } ],
      detector.science_victory_imminent
    )
  end

  test "buffer_city_losses names the captor and the rival the city stood against" do
    pangaea_with_a_roman_buffer
    event(nil, "city_captured", 80, city: "Ostia", old_owner: "Rome", new_owner: "Greece", x: 18, y: 20)

    assert_equal(
      [ { type: :buffer_city_lost, turn: 80, civ: "Rome", captured_by: "Greece", against: "Greece", city: "Ostia" } ],
      detector.buffer_city_losses
    )
  end

  test "buffer_city_losses keeps naming the pair rival when a third civ takes the city" do
    pangaea_with_a_roman_buffer
    event(nil, "city_captured", 80, city: "Ostia", old_owner: "Rome", new_owner: "Egypt", x: 18, y: 20)

    loss = detector.buffer_city_losses.sole

    assert_equal "Egypt", loss[:captured_by]
    assert_equal "Greece", loss[:against]
  end

  test "buffer_city_losses ignores a capture on a plot that buffered nobody" do
    pangaea_with_a_roman_buffer
    event("Rome", "city_founded", 40, city: "Neapolis", x: 10, y: 30)
    event(nil, "city_captured", 80, city: "Neapolis", old_owner: "Rome", new_owner: "Greece", x: 10, y: 30)

    assert_empty detector.buffer_city_losses
  end

  test "buffer_city_losses reports nothing on a map that is not Pangaea" do
    pangaea_with_a_roman_buffer
    @game.update!(map_script: "Continents")
    event(nil, "city_captured", 80, city: "Ostia", old_owner: "Rome", new_owner: "Greece", x: 18, y: 20)

    assert_empty detector.buffer_city_losses
  end

  test "wonder_races_lost reports each civ that lost a race it had invested in" do
    lost_race("BUILDING_LOUVRE", winner: %w[Netherlands Amsterdam], completed: 158, winner_from: 150,
              loser: %w[England London], first: 148, last: 157, invested: 425, turns_left: 2)

    moment = detector.wonder_races_lost.sole

    assert_equal :wonder_race_lost, moment[:type]
    assert_equal 158, moment[:turn]
    assert_equal "England", moment[:civ]
    assert_equal "London", moment[:city]
    assert_equal "BUILDING_LOUVRE", moment[:wonder]
    assert_equal 425, moment[:production_invested]
    assert_equal 2, moment[:turns_left]
    assert_equal "Netherlands", moment[:winner]
  end

  test "a race lost carries what the loser could see of the winner's city" do
    lost_race("BUILDING_LOUVRE", winner: %w[Netherlands Amsterdam], completed: 158, winner_from: 150,
              loser: %w[England London], first: 148, last: 157, invested: 425, turns_left: 2)
    watching("England", "Amsterdam", "Netherlands", from: 152)

    moment = detector.wonder_races_lost.sole

    assert_equal [ 152, 6, %w[England] ],
                 moment.values_at(:observed_from_turn, :observed_turns, :observed_by)
  end

  # On an AI the label would manufacture a decision out of an engine default:
  # no AI code reads surveillance and none reconsiders a wonder in its queue.
  test "a race lost by an AI is not labelled with a response" do
    @game.players.create!(civ: "England", human: false)
    lost_race("BUILDING_LOUVRE", winner: %w[Netherlands Amsterdam], completed: 158, winner_from: 150,
              loser: %w[England London], first: 148, last: 157, invested: 425, turns_left: 2)
    watching("England", "Amsterdam", "Netherlands", from: 152)

    assert_equal [ false, nil ], detector.wonder_races_lost.sole.values_at(:contender_human, :response)
  end

  test "a race lost by a human watching the winner's city is the moment this feature adds" do
    @game.players.create!(civ: "England", human: true)
    lost_race("BUILDING_LOUVRE", winner: %w[Netherlands Amsterdam], completed: 158, winner_from: 150,
              loser: %w[England London], first: 148, last: 157, invested: 425, turns_left: 2)
    watching("England", "Amsterdam", "Netherlands", from: 152)

    assert_equal [ true, :pressed_on ], detector.wonder_races_lost.sole.values_at(:contender_human, :response)
  end

  test "a race lost carries what the winner poured in to take it" do
    lost_race("BUILDING_LOUVRE", winner: %w[Netherlands Amsterdam], completed: 158, winner_from: 150,
              loser: %w[England London], first: 148, last: 157, invested: 425, turns_left: 2,
              winner_lump_on: 154)

    assert_equal [ 154 ],
      detector.wonder_races_lost.sole[:winner_accelerated_on_turns].map { |a| a[:turn] }
  end

  # Losing a race and walking away from one are different facts; only the
  # loss is a moment.
  test "wonder_races_lost ignores a race a civ abandoned before it was decided" do
    lost_race("BUILDING_MACHU_PICHU", winner: %w[Zimbabwe Harare], completed: 115, winner_from: 108,
              loser: %w[India Vijayanagara], first: 100, last: 109, invested: 90, turns_left: 4)

    assert_empty detector.wonder_races_lost
  end

  test "wonder_races_lost ignores a race lost with nothing sunk into it" do
    lost_race("BUILDING_GREAT_LIBRARY", winner: %w[England London], completed: 36, winner_from: 33,
              loser: %w[Zimbabwe Harare], first: 35, last: 35, invested: 0, turns_left: 10)

    assert_empty detector.wonder_races_lost
  end

  test "wonder_races marks the turn a wonder became a contest, lightly" do
    lost_race("BUILDING_LOUVRE", winner: %w[Netherlands Amsterdam], completed: 158, winner_from: 140,
              loser: %w[England London], first: 148, last: 157, invested: 425, turns_left: 2)

    moment = detector.wonder_races.sole

    assert_equal :wonder_race, moment[:type]
    assert_equal 148, moment[:turn]
    assert_equal "BUILDING_LOUVRE", moment[:wonder]
  end

  # A loss the game still rated many turns off is a different fact from one
  # decided on the last turn; the scale carries the difference to the spine.
  test "wonder_races_lost scales a near-miss apart from a distant loss" do
    lost_race("BUILDING_LOUVRE", winner: %w[Netherlands Amsterdam], completed: 158, winner_from: 150,
              loser: %w[England London], first: 148, last: 157, invested: 425, turns_left: 2)
    lost_race("BUILDING_GREAT_WALL", winner: %w[England London], completed: 60, winner_from: 52,
              loser: %w[Zimbabwe Harare], first: 40, last: 59, invested: 30, turns_left: 12)

    by_wonder = detector.wonder_races_lost.index_by { |m| m[:wonder] }

    assert_equal :close, by_wonder["BUILDING_LOUVRE"][:scale]
    assert_equal :distant, by_wonder["BUILDING_GREAT_WALL"][:scale]
  end

  test "wonder_races_lost counts a heavy investment as close even from further back" do
    lost_race("BUILDING_RED_FORT", winner: %w[India Vijayanagara], completed: 163, winner_from: 156,
              loser: %w[Iroquois GrandRiver], first: 150, last: 162, invested: 268, turns_left: 6)

    assert_equal :close, detector.wonder_races_lost.sole[:scale]
  end

  private

  def lost_race(wonder, winner:, completed:, winner_from:, loser:, first:, last:, invested:, turns_left:,
                winner_lump_on: nil)
    winner_civ, winner_city = winner
    loser_civ, loser_city = loser

    (winner_from..completed - 1).each do |turn|
      steps = turn - winner_from + 1
      steps += 3 if winner_lump_on && turn >= winner_lump_on
      event(winner_civ, "city_snapshot", turn, city: winner_city, producing: wonder,
            producing_kind: "wonder", production_stored: 50 * steps, production_turns_left: 1)
    end

    (first..last).each do |turn|
      event(loser_civ, "city_snapshot", turn, city: loser_city, producing: wonder, producing_kind: "wonder",
            production_stored: turn == last ? invested : 0, production_turns_left: turn == last ? turns_left : 20)
    end

    event(winner_civ, "building_constructed", completed, building: wonder, city: winner_city, wonder: "world")
  end

  def watching(civ, city, city_civ, from:)
    event(civ, "spy_moved", from - 4, spy: "#{civ}_SPY", city: city, city_civ: city_civ, state: "travelling")
    event(civ, "spy_surveillance_established", from, spy: "#{civ}_SPY", city: city, city_civ: city_civ)
  end

  # Rome and Greece 17 hexes apart with Ostia standing in the corridor.
  def pangaea_with_a_roman_buffer
    @game.update!(map_script: "Pangaea")
    event("Rome", "city_founded", 0, city: "Roma", x: 10, y: 20)
    event("Greece", "city_founded", 0, city: "Athenai", x: 27, y: 20)
    event("Rome", "city_founded", 30, city: "Ostia", x: 18, y: 20)
  end

  def congress_snapshot(turn, host:, delegates:, votes_needed:)
    @seq += 1
    payload = { "event" => "congress_snapshot", "turn" => turn, "host" => host,
                "delegates" => delegates, "votes_needed_for_diplo_victory" => votes_needed }
    @game.game_events.create!(seq: @seq, session_index: 0, turn: turn, event_type: "congress_snapshot", civ: nil, payload: payload)
  end

  def detector
    @detector ||= KeyMomentDetector.new(@game)
  end

  def killed(killer, victim, unit, turn)
    event(nil, "unit_killed", turn, killer: killer, victim: victim, unit: unit)
    event(victim, "unit_lost", turn, unit: unit)
  end

  def snapshot(civ, turn, **metrics)
    @seq += 1
    payload = metrics.stringify_keys.merge("event" => "snapshot", "turn" => turn, "civ" => civ)
    @game.game_events.create!(
      seq: @seq, session_index: 0, turn: turn, event_type: "snapshot", civ: civ, payload: payload
    )
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
