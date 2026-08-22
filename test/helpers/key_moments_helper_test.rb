require "test_helper"

class KeyMomentsHelperTest < ActionView::TestCase
  test "narrates a war that ended in peace" do
    moment = { type: :war, turn: 57, turn_peace: 70,
               attacker_civs: %w[Chile], defender_civs: %w[Vietnam] }

    assert_equal "Turn 57: Chile declared war on Vietnam (peace at turn 70)", key_moment_sentence(moment)
  end

  test "narrates a war still being fought" do
    moment = { type: :war, turn: 57, turn_peace: nil,
               attacker_civs: %w[Chile], defender_civs: %w[Vietnam] }

    assert_equal "Turn 57: Chile declared war on Vietnam (ongoing)", key_moment_sentence(moment)
  end

  test "narrates a lost buffer city by its captor and the rival it stood against" do
    moment = { type: :buffer_city_lost, turn: 152, civ: "Arabia", captured_by: "Babylon",
               against: "Philippines", city: "Medina" }

    assert_equal(
      "Turn 152: Arabia lost Medina to Babylon, the city between its capital and Philippines's",
      key_moment_sentence(moment)
    )
  end

  test "leaves the snowballed metric to the heading above the list" do
    moment = { type: :snowball, civ: "Chile", turn: 50, turn_end: 70, duration_turns: 20 }

    assert_equal "Turns 50–70: Chile pulled decisively ahead", key_moment_sentence(moment)
  end

  test "spans a range of turns only when the moment lasted more than one" do
    moment = { type: :unhappiness_period, civ: "Chile", turn: 40, turn_end: 40 }

    assert_equal "Turn 40: Chile happiness stayed below zero", key_moment_sentence(moment)
  end

  test "narrates a religion founding with its beliefs and order" do
    moment = { type: :religion_founded, turn: 30, civ: "Chile", religion: "Christianity",
               holy_city: "Santiago", beliefs: %w[BELIEF_A BELIEF_B], order: 2 }

    assert_equal(
      "Turn 30: Chile founded Christianity (#2) with BELIEF_A, BELIEF_B",
      key_moment_sentence(moment)
    )
  end

  test "marks a swing upwards so its direction is visible before reading" do
    moment = { type: :happiness_surge, civ: "Chile", turn: 73, turn_end: 74, from: 3, to: 13 }

    assert_match(/trend--up/, key_moment_trend(moment))
  end

  test "marks a swing downwards" do
    moment = { type: :army_power_collapse, civ: "Chile", turn: 80, turn_end: 85, from: 200, to: 100 }

    assert_match(/trend--down/, key_moment_trend(moment))
  end

  test "hides the arrow from screen readers, since the sentence already says it" do
    moment = { type: :happiness_surge, civ: "Chile", turn: 73, turn_end: 74, from: 3, to: 13 }

    assert_match(/aria-hidden/, key_moment_trend(moment))
  end

  test "leaves a moment that is not a swing unmarked" do
    moment = { type: :unhappiness_period, civ: "Chile", turn: 40, turn_end: 60 }

    assert_nil key_moment_trend(moment)
  end

  test "distinguishes a military collapse from a surge" do
    moment = { type: :army_power_collapse, civ: "Chile", turn: 80, turn_end: 85, from: 200, to: 100 }

    assert_equal "Turns 80–85: Chile army power dropped from 200 to 100", key_moment_sentence(moment)
  end

  test "narrates an influence level reached, humanizing the level" do
    moment = { type: :influence_level_reached, turn: 90, civ: "Chile", opponent: "Vietnam",
               level: "INFLUENCE_LEVEL_DOMINANT" }

    assert_equal "Turn 90: Chile became Dominant on Vietnam", key_moment_sentence(moment)
  end

  test "narrates cultural victory imminent" do
    moment = { type: :cultural_victory_imminent, turn: 120, civ: "Chile",
               civs_influential_on: 3, living_majors: 4 }

    assert_equal(
      "Turn 120: Chile is culturally influential on 3 of 4 living majors",
      key_moment_sentence(moment)
    )
  end

  test "narrates a Congress host change" do
    moment = { type: :congress_host_change, turn: 90, from: "Chile", to: "Vietnam" }

    assert_equal "Turn 90: World Congress host passed from Chile to Vietnam", key_moment_sentence(moment)
  end

  test "narrates the first Congress host, with no previous host" do
    moment = { type: :congress_host_change, turn: 90, from: nil, to: "Vietnam" }

    assert_equal "Turn 90: World Congress host passed from no host to Vietnam", key_moment_sentence(moment)
  end

  test "narrates the United Nations forming" do
    moment = { type: :united_nations_formed, turn: 220 }

    assert_equal "Turn 220: The United Nations formed", key_moment_sentence(moment)
  end

  test "narrates diplomatic victory imminent" do
    moment = { type: :diplomatic_victory_imminent, turn: 200, civ: "Chile", votes: 14, votes_needed: 12 }

    assert_equal(
      "Turn 200: Chile reached 14 delegate votes, meeting the 12 needed for a diplomatic victory",
      key_moment_sentence(moment)
    )
  end

  test "narrates a passed resolution with its proposer" do
    moment = { type: :resolution_passed, turn: 150, resolution: "RESOLUTION_WORLD_FAIR", proposer: "Chile" }

    assert_equal "Turn 150: RESOLUTION_WORLD_FAIR passed, proposed by Chile", key_moment_sentence(moment)
  end

  test "narrates a civilization gaining control of a capital" do
    moment = { type: :capital_gained, turn: 100, civ: "Chile", original_owner: "Vietnam" }

    assert_equal "Turn 100: Chile gained control of Vietnam's original capital", key_moment_sentence(moment)
  end

  test "narrates a civilization losing control of a capital, with a downward trend" do
    moment = { type: :capital_lost, turn: 100, civ: "Chile", original_owner: "Chile" }

    assert_equal "Turn 100: Chile lost control of Chile's original capital", key_moment_sentence(moment)
    assert_match(/trend--down/, key_moment_trend(moment))
  end

  test "narrates Apollo Program completion" do
    moment = { type: :apollo_completed, turn: 180, civ: "Chile" }

    assert_equal "Turn 180: Chile completed the Apollo Program", key_moment_sentence(moment)
  end

  test "narrates a spaceship part assembly" do
    moment = { type: :spaceship_part_assembled, turn: 190, civ: "Chile", part: "booster", count: 2 }

    assert_equal "Turn 190: Chile assembled a booster (2 total)", key_moment_sentence(moment)
  end

  test "narrates science victory imminent" do
    moment = { type: :science_victory_imminent, turn: 195, civ: "Chile", parts_assembled: 5 }

    assert_equal "Turn 195: Chile assembled 5 of 6 spaceship parts", key_moment_sentence(moment)
  end
end
