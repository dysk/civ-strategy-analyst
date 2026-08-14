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
    snapshot("Rome", 1, score: 100, science: 20)
    snapshot("Greece", 1, score: 90, science: 10)

    # Score flips to Greece; science leader (Rome) unchanged.
    snapshot("Rome", 2, score: 100, science: 20)
    snapshot("Greece", 2, score: 110, science: 15)

    # Score leader unchanged (Greece still ahead); science flips to Greece.
    snapshot("Rome", 3, score: 100, science: 12)
    snapshot("Greece", 3, score: 110, science: 25)

    moments = detector.leader_changes

    assert_equal(
      [
        { type: :leader_change, metric: "score", turn: 2, from: "Rome", to: "Greece" },
        { type: :leader_change, metric: "science", turn: 3, from: "Rome", to: "Greece" }
      ],
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

  test "religion_foundings reports each founding in order, tagged with how early it was" do
    event("Greece", "religion_founded", 50, holy_city: "Athens", religion: "RELIGION_POLYTHEISM", beliefs: %w[BELIEF_X])
    event("Rome", "religion_founded", 35, holy_city: "Roma", religion: "RELIGION_JUDAISM", beliefs: %w[BELIEF_Y])

    moments = detector.religion_foundings

    assert_equal(
      [
        { type: :religion_founded, turn: 35, civ: "Rome", religion: "RELIGION_JUDAISM", holy_city: "Roma", order: 1 },
        { type: :religion_founded, turn: 50, civ: "Greece", religion: "RELIGION_POLYTHEISM", holy_city: "Athens", order: 2 }
      ],
      moments
    )
  end

  test "military_might_collapses flags single-turn drops beyond 15%, ignores smaller dips" do
    snapshot("Rome", 1, military_might: 1000)
    snapshot("Rome", 2, military_might: 900)  # -10%, below threshold
    snapshot("Rome", 3, military_might: 700)  # -22.2%, collapse
    snapshot("Rome", 4, military_might: 750)  # gain, never a collapse

    snapshot("Greece", 1, military_might: 500)
    snapshot("Greece", 2, military_might: 500)

    moments = detector.military_might_collapses

    assert_equal 1, moments.size
    collapse = moments.first
    assert_equal :military_might_collapse, collapse[:type]
    assert_equal "Rome", collapse[:civ]
    assert_equal 3, collapse[:turn]
    assert_equal 900, collapse[:from]
    assert_equal 700, collapse[:to]
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
