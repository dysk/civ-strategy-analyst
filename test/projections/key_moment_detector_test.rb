require "test_helper"

class KeyMomentDetectorTest < ActiveSupport::TestCase
  setup do
    @game = Game.create!(name: "Key Moment Test Game")
    @seq = 0
  end

  test "wars reports declaration, territory changes and unit-loss spikes" do
    event(nil, "war_declared", 10, attacker_team: 1, attacker_civs: %w[Rome], defender_team: 2, defender_civs: %w[Greece])
    event(nil, "city_captured", 12, city: "Athens", old_owner: "Greece", new_owner: "Rome")
    event("Greece", "unit_lost", 15)
    event("Greece", "unit_lost", 15)
    event("Greece", "unit_lost", 15)
    event("Rome", "unit_lost", 20)
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
    assert_equal [ { civ: "Greece", turn: 15, count: 3 } ], war[:unit_lost_spikes]
  end

  test "wars omits unit_lost_spikes when no side loses 3+ units in a single turn" do
    event(nil, "war_declared", 10, attacker_team: 1, attacker_civs: %w[Rome], defender_team: 2, defender_civs: %w[Greece])
    event("Greece", "unit_lost", 15)
    event("Greece", "unit_lost", 16)
    event(nil, "peace_made", 30, team_a: 1, team_a_civs: %w[Rome], team_b: 2, team_b_civs: %w[Greece])

    war = detector.wars.first

    assert_equal [], war[:unit_lost_spikes]
    assert_equal({}, war[:cities_captured])
  end

  test "wars ignores losses and captures outside the war window" do
    event(nil, "war_declared", 10, attacker_team: 1, attacker_civs: %w[Rome], defender_team: 2, defender_civs: %w[Greece])
    event(nil, "peace_made", 30, team_a: 1, team_a_civs: %w[Rome], team_b: 2, team_b_civs: %w[Greece])
    # Before the war
    event("Greece", "unit_lost", 5)
    event("Greece", "unit_lost", 5)
    event("Greece", "unit_lost", 5)
    # After peace
    event(nil, "city_captured", 40, city: "Sparta", old_owner: "Greece", new_owner: "Rome")

    war = detector.wars.first

    assert_equal [], war[:unit_lost_spikes]
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

  test "military_might_swings flags single-turn drops and gains beyond 15%, ignores smaller moves" do
    snapshot("Rome", 101, military_might: 1000)
    snapshot("Rome", 102, military_might: 900)  # -10%, below threshold
    snapshot("Rome", 103, military_might: 700)  # -22.2%, collapse
    snapshot("Rome", 104, military_might: 850)  # +21.4%, surge (different direction, doesn't merge with the collapse)
    snapshot("Rome", 105, military_might: 900)  # +5.9%, below threshold

    snapshot("Greece", 101, military_might: 500)
    snapshot("Greece", 102, military_might: 500)

    moments = detector.military_might_swings

    assert_equal(
      [
        { type: :military_might_collapse, civ: "Rome", turn: 102, turn_end: 103, from: 900, to: 700, pct_change: -0.222 },
        { type: :military_might_surge, civ: "Rome", turn: 103, turn_end: 104, from: 700, to: 850, pct_change: 0.214 }
      ],
      moments
    )
  end

  test "military_might_swings merges consecutive same-direction swings into a single run" do
    snapshot("Rome", 101, military_might: 300)
    snapshot("Rome", 102, military_might: 360)  # +20%, surge
    snapshot("Rome", 103, military_might: 450)  # +25%, surge, chains onto the previous turn
    snapshot("Rome", 104, military_might: 460)  # +2.2%, below threshold, ends the run

    moments = detector.military_might_swings

    assert_equal(
      [ { type: :military_might_surge, civ: "Rome", turn: 101, turn_end: 103, from: 300, to: 450, pct_change: 0.5 } ],
      moments
    )
  end

  test "military_might_swings excludes swings within the first 100 turns for non-quick speeds" do
    @game.update!(game_speed: "GAMESPEED_STANDARD")
    snapshot("Rome", 1, military_might: 300)
    snapshot("Rome", 2, military_might: 200)   # -33%, within the grace period
    snapshot("Rome", 101, military_might: 210) # +5% vs turn 2, below threshold
    snapshot("Rome", 102, military_might: 126) # -40%, past the grace period

    moments = detector.military_might_swings

    assert_equal(
      [ { type: :military_might_collapse, civ: "Rome", turn: 101, turn_end: 102, from: 210, to: 126, pct_change: -0.4 } ],
      moments
    )
  end

  test "military_might_swings excludes swings within the first 67 turns for GAMESPEED_QUICK" do
    @game.update!(game_speed: "GAMESPEED_QUICK")
    snapshot("Rome", 1, military_might: 300)
    snapshot("Rome", 2, military_might: 200)  # -33%, within the grace period
    snapshot("Rome", 68, military_might: 210) # +5% vs turn 2, below threshold
    snapshot("Rome", 69, military_might: 126) # -40%, past the grace period

    moments = detector.military_might_swings

    assert_equal(
      [ { type: :military_might_collapse, civ: "Rome", turn: 68, turn_end: 69, from: 210, to: 126, pct_change: -0.4 } ],
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

  private

  def detector
    @detector ||= KeyMomentDetector.new(@game)
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
