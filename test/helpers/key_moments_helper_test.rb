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

  test "narrates a rush technology with the lead it bought" do
    moment = { type: :rush_tech_lead, turn: 120, tech: "TECH_METALLURGY",
               civs: %w[Chile], next_turn: 148, next_civs: %w[Vietnam] }

    assert_equal(
      "Turn 120: Chile reached TECH_METALLURGY first, 28 turns ahead of Vietnam",
      key_moment_sentence(moment)
    )
  end

  test "narrates a rush technology nobody else reached" do
    moment = { type: :rush_tech_lead, turn: 200, tech: "TECH_COMBUSTION", civs: %w[Chile] }

    assert_equal(
      "Turn 200: Chile reached TECH_COMBUSTION first, and nobody else got there",
      key_moment_sentence(moment)
    )
  end

  test "counts a one-turn rush lead in the singular" do
    moment = { type: :rush_tech_lead, turn: 120, tech: "TECH_FLIGHT",
               civs: %w[Chile], next_turn: 121, next_civs: %w[Vietnam] }

    assert_equal(
      "Turn 120: Chile reached TECH_FLIGHT first, 1 turn ahead of Vietnam",
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
end
