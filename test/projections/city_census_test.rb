require "test_helper"

class CityCensusTest < ActiveSupport::TestCase
  setup do
    @game = Game.create!(name: "City Census Test Game")
    @seq = 0
  end

  test "sizes lists a civ's city populations at the given turn, largest first" do
    city_snapshot("Tibet", 40, "Lhasa", population: 12)
    city_snapshot("Tibet", 40, "Shigatse", population: 4)
    city_snapshot("Tibet", 40, "Gyantse", population: 7)

    assert_equal [ 12, 7, 4 ], CityCensus.new(@game).sizes("Tibet", 40)
  end

  test "sizes carries the nearest snapshot at or before the turn forward" do
    city_snapshot("Tibet", 40, "Lhasa", population: 12)
    city_snapshot("Tibet", 50, "Lhasa", population: 15)

    assert_equal [ 12 ], CityCensus.new(@game).sizes("Tibet", 45)
    assert_equal [ 15 ], CityCensus.new(@game).sizes("Tibet", 500)
  end

  test "sizes deduplicates a city snapshotted twice in one turn, keeping the later payload" do
    city_snapshot("Tibet", 29, "Lhasa", population: 12)
    city_snapshot("Tibet", 29, "Lhasa", population: 13)

    assert_equal [ 13 ], CityCensus.new(@game).sizes("Tibet", 29)
  end

  test "sizes isolates one civ from another" do
    city_snapshot("Tibet", 40, "Lhasa", population: 12)
    city_snapshot("Iroquois", 40, "Onondaga", population: 18)

    assert_equal [ 12 ], CityCensus.new(@game).sizes("Tibet", 40)
  end

  test "sizes is empty for a civ with no snapshot at or before the turn" do
    city_snapshot("Tibet", 40, "Lhasa", population: 12)

    assert_equal [], CityCensus.new(@game).sizes("Tibet", 20)
    assert_equal [], CityCensus.new(@game).sizes("Iroquois", 40)
  end

  test "snapshot pairs each city with its population, largest first" do
    city_snapshot("Tibet", 40, "Lhasa", population: 12)
    city_snapshot("Tibet", 40, "Gyantse", population: 7)

    assert_equal [ { city: "Lhasa", population: 12 }, { city: "Gyantse", population: 7 } ],
                 CityCensus.new(@game).snapshot("Tibet", 40)
  end

  test "cities lists every city across every civ, largest first" do
    city_snapshot("Tibet", 40, "Lhasa", population: 12)
    city_snapshot("Iroquois", 40, "Onondaga", population: 18)

    assert_equal [ { city: "Onondaga", civ: "Iroquois", population: 18 },
                   { city: "Lhasa", civ: "Tibet", population: 12 } ],
                 CityCensus.new(@game).cities(40)
  end

  test "cities lists a captured city under its new owner, not the one that lost it" do
    city_snapshot("Tibet", 10, "Lhasa", population: 12)
    city_snapshot("Iroquois", 20, "Lhasa", population: 8)

    assert_equal [ { city: "Lhasa", civ: "Iroquois", population: 8 } ], CityCensus.new(@game).cities(40)
  end

  test "cities does not resurrect a captured city under its former owner" do
    city_snapshot("Tibet", 10, "Lhasa", population: 12)
    city_snapshot("Iroquois", 20, "Lhasa", population: 8)

    cities = CityCensus.new(@game).cities(40)

    assert_equal 1, cities.size
  end

  test "applicable? is false when the log carries no city snapshot" do
    @game.game_events.create!(
      seq: @seq += 1, session_index: 0, turn: 1, event_type: "snapshot", civ: "Tibet",
      payload: { "event" => "snapshot", "turn" => 1, "civ" => "Tibet" }
    )

    assert_not CityCensus.new(@game).applicable?
  end

  test "applicable? is true once a city snapshot is present" do
    city_snapshot("Tibet", 1, "Lhasa", population: 1)

    assert CityCensus.new(@game).applicable?
  end

  private

  def city_snapshot(civ, turn, city, population:)
    payload = { "event" => "city_snapshot", "turn" => turn, "civ" => civ, "city" => city,
                "population" => population }
    @game.game_events.create!(
      seq: @seq += 1, session_index: 0, turn: turn, event_type: "city_snapshot", civ: civ, payload: payload
    )
  end
end
