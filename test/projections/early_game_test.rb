require "test_helper"

class EarlyGameTest < ActiveSupport::TestCase
  setup do
    @game = Game.create!(name: "Early Game Test Game", game_speed: "GAMESPEED_STANDARD")
    @seq = 0
  end

  test "deadline_turn is 150 standard turns, scaled by game speed" do
    assert_equal 150, EarlyGame.new(@game).deadline_turn

    @game.update!(game_speed: "GAMESPEED_QUICK")

    assert_equal 100, EarlyGame.new(@game).deadline_turn
  end

  test "for_civ ends the early game when Education meets a Workshop" do
    tech("Rome", 60, "TECH_EDUCATION")
    building("Rome", 80, "BUILDING_WORKSHOP")

    assert_equal(
      {
        civ: "Rome",
        end_turn: 80,
        reason: :milestone,
        milestone_turn: 80,
        milestone: { tech: "TECH_EDUCATION", building: "BUILDING_WORKSHOP" },
        tech_turn: 60,
        building_turn: 80,
        deadline_turn: 150
      },
      early_game.for_civ("Rome")
    )
  end

  test "for_civ ends the early game when Metal Casting meets a University" do
    tech("Rome", 50, "TECH_METAL_CASTING")
    building("Rome", 90, "BUILDING_UNIVERSITY")

    assert_equal(
      {
        civ: "Rome",
        end_turn: 90,
        reason: :milestone,
        milestone_turn: 90,
        milestone: { tech: "TECH_METAL_CASTING", building: "BUILDING_UNIVERSITY" },
        tech_turn: 50,
        building_turn: 90,
        deadline_turn: 150
      },
      early_game.for_civ("Rome")
    )
  end

  test "for_civ takes the earlier of the two milestones" do
    tech("Rome", 60, "TECH_EDUCATION")
    building("Rome", 100, "BUILDING_WORKSHOP")
    tech("Rome", 50, "TECH_METAL_CASTING")
    building("Rome", 80, "BUILDING_UNIVERSITY")

    assert_equal 80, early_game.for_civ("Rome")[:end_turn]
    assert_equal({ tech: "TECH_METAL_CASTING", building: "BUILDING_UNIVERSITY" }, early_game.for_civ("Rome")[:milestone])
  end

  test "for_civ reports the Education milestone when both land on the same turn" do
    tech("Rome", 40, "TECH_EDUCATION")
    building("Rome", 90, "BUILDING_WORKSHOP")
    tech("Rome", 30, "TECH_METAL_CASTING")
    building("Rome", 90, "BUILDING_UNIVERSITY")

    assert_equal({ tech: "TECH_EDUCATION", building: "BUILDING_WORKSHOP" }, early_game.for_civ("Rome")[:milestone])
  end

  test "for_civ does not end the early game on a technology without its building" do
    tech("Rome", 60, "TECH_EDUCATION")
    tech("Rome", 65, "TECH_METAL_CASTING")
    snapshot("Rome", 160)

    assert_equal(
      { civ: "Rome", end_turn: 150, reason: :deadline, milestone_turn: nil, milestone: nil,
        tech_turn: nil, building_turn: nil, deadline_turn: 150 },
      early_game.for_civ("Rome")
    )
  end

  test "for_civ does not end the early game on a building without its technology" do
    building("Rome", 60, "BUILDING_WORKSHOP")
    building("Rome", 70, "BUILDING_UNIVERSITY")
    snapshot("Rome", 160)

    assert_equal :deadline, early_game.for_civ("Rome")[:reason]
    assert_nil early_game.for_civ("Rome")[:milestone_turn]
  end

  test "for_civ falls back to the deadline when neither milestone is reached" do
    snapshot("Rome", 160)

    assert_equal 150, early_game.for_civ("Rome")[:end_turn]
    assert_equal :deadline, early_game.for_civ("Rome")[:reason]
  end

  test "for_civ keeps a milestone reached past the deadline, but ends on the deadline" do
    tech("Rome", 140, "TECH_EDUCATION")
    building("Rome", 160, "BUILDING_WORKSHOP")
    snapshot("Rome", 170)

    assert_equal(
      {
        civ: "Rome",
        end_turn: 150,
        reason: :deadline,
        milestone_turn: 160,
        milestone: { tech: "TECH_EDUCATION", building: "BUILDING_WORKSHOP" },
        tech_turn: 140,
        building_turn: 160,
        deadline_turn: 150
      },
      early_game.for_civ("Rome")
    )
  end

  test "for_civ ends on the game's last turn when the log stops before the deadline" do
    tech("Rome", 15, "TECH_EDUCATION")
    snapshot("Rome", 20)

    assert_equal(
      { civ: "Rome", end_turn: 20, reason: :game_end, milestone_turn: nil, milestone: nil,
        tech_turn: nil, building_turn: nil, deadline_turn: 150 },
      early_game.for_civ("Rome")
    )
  end

  test "for_civ counts a technology picked up from ruins" do
    event("Rome", "tech_from_ruins", 30, tech: "TECH_EDUCATION")
    building("Rome", 40, "BUILDING_WORKSHOP")

    assert_equal 40, early_game.for_civ("Rome")[:end_turn]
    assert_equal 30, early_game.for_civ("Rome")[:tech_turn]
  end

  test "for_civ credits a team-researched technology to every member of the team" do
    event(nil, "tech_researched", 50, team: 1, civs: %w[Rome Egypt], tech: "TECH_METAL_CASTING")
    building("Rome", 70, "BUILDING_UNIVERSITY")
    building("Egypt", 80, "BUILDING_UNIVERSITY")

    assert_equal 70, early_game.for_civ("Rome")[:end_turn]
    assert_equal 80, early_game.for_civ("Egypt")[:end_turn]
  end

  test "for_civ scales the deadline with game speed" do
    @game.update!(game_speed: "GAMESPEED_QUICK")
    snapshot("Rome", 110)

    assert_equal 100, early_game.for_civ("Rome")[:end_turn]
    assert_equal :deadline, early_game.for_civ("Rome")[:reason]
  end

  test "series returns one row per player, keyed by civ" do
    @game.players.create!(civ: "Rome")
    @game.players.create!(civ: "Egypt")
    tech("Rome", 50, "TECH_METAL_CASTING")
    building("Rome", 70, "BUILDING_UNIVERSITY")
    snapshot("Egypt", 160)

    series = early_game.series

    assert_equal %w[Rome Egypt], series.keys
    assert_equal 70, series["Rome"][:end_turn]
    assert_equal :deadline, series["Egypt"][:reason]
  end

  private

  def early_game
    @early_game ||= EarlyGame.new(@game)
  end

  def tech(civ, turn, tech)
    event(nil, "tech_researched", turn, team: 1, civs: [ civ ], tech: tech)
  end

  def building(civ, turn, building)
    event(civ, "building_constructed", turn, building: building, city: "#{civ} City")
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
