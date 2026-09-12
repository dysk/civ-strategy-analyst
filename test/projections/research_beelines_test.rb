require "test_helper"

class ResearchBeelinesTest < ActiveSupport::TestCase
  setup do
    @game = Game.create!(name: "Research Beelines Test Game")
    @seq = 0
  end

  test "reports the marker tech's turn and tech count for a civ that researched it" do
    fill_techs("India", upto: 17)
    researched("TECH_EDUCATION", 74, civs: %w[India])

    entry = ResearchBeelines.new(@game).markers_reached("India").find { |m| m[:marker] == "universities" }

    assert_equal "TECH_EDUCATION", entry[:tech]
    assert_equal 74, entry[:turn]
    assert_equal 18, entry[:tech_count]
  end

  # The real trigger for this: TECH_MINING at turn 9 in india-diplo fires
  # both tech_researched and tech_from_ruins for England, crediting the
  # same tech twice if tech_from_ruins is treated as a second acquisition.
  test "does not double-count a tech that also arrived via ruins" do
    researched("TECH_MINING", 9, civs: %w[England])
    from_ruins("England", "TECH_MINING", 9)
    researched("TECH_MACHINERY", 20, civs: %w[England])

    entry = ResearchBeelines.new(@game).markers_reached("England").find { |m| m[:marker] == "crossbows" }

    assert_equal 2, entry[:tech_count]
  end

  test "tech_count only counts techs researched at or before the marker's turn" do
    fill_techs("India", upto: 17)
    researched("TECH_EDUCATION", 74, civs: %w[India])
    researched("TECH_CURRENCY", 80, civs: %w[India])

    entry = ResearchBeelines.new(@game).markers_reached("India").find { |m| m[:marker] == "universities" }

    assert_equal 18, entry[:tech_count]
  end

  test "ignores another civ's tech pace when counting" do
    fill_techs("England", upto: 30)
    researched("TECH_EDUCATION", 74, civs: %w[India])

    entry = ResearchBeelines.new(@game).markers_reached("India").find { |m| m[:marker] == "universities" }

    assert_equal 1, entry[:tech_count]
  end

  test "rush is true when the tech count lands inside the marker's band" do
    fill_techs("India", upto: 17)
    researched("TECH_EDUCATION", 74, civs: %w[India])

    entry = ResearchBeelines.new(@game).markers_reached("India").find { |m| m[:marker] == "universities" }

    assert_equal true, entry[:rush]
    assert_equal 0, entry[:distance_to_band]
  end

  test "rush is false and distance_to_band is negative below the band" do
    fill_techs("India", upto: 9)
    researched("TECH_EDUCATION", 74, civs: %w[India])

    entry = ResearchBeelines.new(@game).markers_reached("India").find { |m| m[:marker] == "universities" }

    assert_equal false, entry[:rush]
    assert_equal(-6, entry[:distance_to_band])
  end

  test "rush is false and distance_to_band is positive above the band" do
    fill_techs("India", upto: 19)
    researched("TECH_EDUCATION", 74, civs: %w[India])

    entry = ResearchBeelines.new(@game).markers_reached("India").find { |m| m[:marker] == "universities" }

    assert_equal false, entry[:rush]
    assert_equal 1, entry[:distance_to_band]
  end

  test "carries the band and the snapshot's own tech count alongside the event-based count" do
    fill_techs("India", upto: 17)
    researched("TECH_EDUCATION", 74, civs: %w[India])
    snapshot("India", 74, techs: 19)

    entry = ResearchBeelines.new(@game).markers_reached("India").find { |m| m[:marker] == "universities" }

    assert_equal({ min: 16, max: 19 }, entry[:band])
    assert_equal 19, entry[:snapshot_tech_count]
  end

  test "snapshot_tech_count is nil when the log carries no snapshot for that turn" do
    fill_techs("India", upto: 17)
    researched("TECH_EDUCATION", 74, civs: %w[India])

    entry = ResearchBeelines.new(@game).markers_reached("India").find { |m| m[:marker] == "universities" }

    assert_nil entry[:snapshot_tech_count]
  end

  test "reports every marker a civ reached, not just the first" do
    fill_techs("India", upto: 17)
    researched("TECH_EDUCATION", 74, civs: %w[India])
    fill_techs("India", upto: 24, starting_at: 75)
    researched("TECH_MACHINERY", 100, civs: %w[India])

    markers = ResearchBeelines.new(@game).markers_reached("India").map { |m| m[:marker] }

    assert_includes markers, "universities"
    assert_includes markers, "crossbows"
  end

  test "omits a marker a civ never researched" do
    fill_techs("India", upto: 5)

    assert_empty ResearchBeelines.new(@game).markers_reached("India")
  end

  private

  # Fills in `upto` distinct, throwaway researched techs for civ, so a
  # marker tech researched afterwards lands at a known tech_count.
  def fill_techs(civ, upto:, starting_at: 1)
    (starting_at...(starting_at + upto)).each { |i| researched("TECH_FILLER_#{i}", i, civs: [ civ ]) }
  end

  def researched(tech, turn, civs:)
    event(nil, "tech_researched", turn, tech: tech, civs: civs, change: 1)
  end

  def from_ruins(civ, tech, turn)
    event(civ, "tech_from_ruins", turn, tech: tech)
  end

  def snapshot(civ, turn, techs:)
    event(civ, "snapshot", turn, techs: techs)
  end

  def event(civ, event_type, turn, extra = {})
    @seq += 1
    payload = extra.stringify_keys.merge("event" => event_type, "turn" => turn)
    payload["civ"] = civ if civ
    @game.game_events.create!(
      seq: @seq, session_index: 0, turn: turn, event_type: event_type, civ: civ, payload: payload
    )
  end
end
