require "test_helper"

class CityValueTest < ActiveSupport::TestCase
  setup do
    @game = Game.create!(name: "City Value Test Game")
    @seq = 0
  end

  test "at gives a city's share of its owner's empire across every yield" do
    city_snapshot("Iroquois", 150, "Onondaga", population: 18, buildings: 18,
                  yield_science: 54, yield_production: 54, yield_gold: 20, yield_culture: 10, yield_faith: 6)
    city_snapshot("Iroquois", 150, "Cattaraugus", population: 6, buildings: 6,
                  yield_science: 6, yield_production: 18, yield_gold: 10, yield_culture: 2, yield_faith: 2)

    value = CityValue.new(@game).at("Onondaga", 150)

    assert_in_delta 0.75, value[:population_share], 0.001
    assert_in_delta 0.75, value[:buildings_share], 0.001
    assert_in_delta 0.9, value[:science_share], 0.001
    assert_in_delta 0.75, value[:production_share], 0.001
    assert_in_delta 0.667, value[:gold_share], 0.001
    assert_in_delta 0.833, value[:culture_share], 0.001
    assert_in_delta 0.75, value[:faith_share], 0.001
  end

  test "at ranks the city among its owner's cities by each yield, largest first" do
    city_snapshot("Iroquois", 150, "Onondaga", population: 18, yield_science: 54, yield_production: 40)
    city_snapshot("Iroquois", 150, "Cattaraugus", population: 6, yield_science: 6, yield_production: 50)

    value = CityValue.new(@game).at("Onondaga", 150)

    assert_equal 1, value[:population_rank]
    assert_equal 1, value[:science_rank]
    assert_equal 2, value[:production_rank]
  end

  test "at reads the owner and the census turn from the city's own snapshot" do
    city_snapshot("Iroquois", 148, "Onondaga", population: 17)
    city_snapshot("Iroquois", 152, "Onondaga", population: 18)

    value = CityValue.new(@game).at("Onondaga", 150)

    assert_equal "Iroquois", value[:civ]
    assert_equal 148, value[:turn]
  end

  test "at takes shares over the owner's cities at the census turn only" do
    city_snapshot("Iroquois", 150, "Onondaga", population: 18)
    city_snapshot("Iroquois", 150, "Cattaraugus", population: 6)
    city_snapshot("Iroquois", 120, "Salamanca", population: 40) # a turn ago, not counted

    assert_in_delta 0.75, CityValue.new(@game).at("Onondaga", 150)[:population_share], 0.001
  end

  test "at deduplicates a city snapshotted twice in one turn, keeping the later payload" do
    city_snapshot("Iroquois", 29, "Onondaga", population: 17, yield_science: 10)
    city_snapshot("Iroquois", 29, "Onondaga", population: 18, yield_science: 20)
    city_snapshot("Iroquois", 29, "Cattaraugus", population: 6, yield_science: 20)

    value = CityValue.new(@game).at("Onondaga", 29)

    assert_in_delta 0.75, value[:population_share], 0.001
    assert_in_delta 0.5, value[:science_share], 0.001
  end

  test "at isolates one civ's empire from another's" do
    city_snapshot("Iroquois", 150, "Onondaga", population: 18)
    city_snapshot("India", 150, "Delhi", population: 30)

    assert_in_delta 1.0, CityValue.new(@game).at("Onondaga", 150)[:population_share], 0.001
  end

  test "at is nil for a city with no snapshot at or before the turn" do
    city_snapshot("Iroquois", 150, "Onondaga", population: 18)

    assert_nil CityValue.new(@game).at("Onondaga", 100)
    assert_nil CityValue.new(@game).at("Nowhere", 150)
  end

  test "a yield the whole empire earns nothing of has no share and no rank" do
    city_snapshot("Iroquois", 150, "Onondaga", population: 18, yield_faith: 0)
    city_snapshot("Iroquois", 150, "Cattaraugus", population: 6, yield_faith: 0)

    value = CityValue.new(@game).at("Onondaga", 150)

    assert_nil value[:faith_share]
    assert_nil value[:faith_rank]
  end

  test "series gives the city's value at every turn it was itself snapshotted" do
    city_snapshot("Iroquois", 100, "Onondaga", population: 10)
    city_snapshot("Iroquois", 100, "Cattaraugus", population: 10)
    city_snapshot("Iroquois", 150, "Onondaga", population: 18)
    city_snapshot("Iroquois", 150, "Cattaraugus", population: 6)

    series = CityValue.new(@game).series("Onondaga")

    assert_equal [ 100, 150 ], series.map { |entry| entry[:turn] }
    assert_in_delta 0.5, series.first[:population_share], 0.001
    assert_in_delta 0.75, series.last[:population_share], 0.001
  end

  test "series follows a city across a change of owner" do
    city_snapshot("Iroquois", 100, "Cahokia", population: 10)
    city_snapshot("England", 120, "Cahokia", population: 6)

    series = CityValue.new(@game).series("Cahokia")

    assert_equal [ "Iroquois", "England" ], series.map { |entry| entry[:civ] }
  end

  test "applicable? is false when the log carries no city snapshot" do
    @game.game_events.create!(
      seq: @seq += 1, session_index: 0, turn: 1, event_type: "snapshot", civ: "Iroquois",
      payload: { "event" => "snapshot", "turn" => 1, "civ" => "Iroquois" }
    )

    assert_not CityValue.new(@game).applicable?
  end

  test "applicable? is true once a city snapshot is present" do
    city_snapshot("Iroquois", 1, "Onondaga", population: 1)

    assert CityValue.new(@game).applicable?
  end

  private

  def city_snapshot(civ, turn, city, population:, buildings: 0, yield_science: 0, yield_production: 0,
                    yield_gold: 0, yield_culture: 0, yield_faith: 0)
    payload = { "event" => "city_snapshot", "turn" => turn, "civ" => civ, "city" => city,
                "population" => population, "buildings" => buildings, "yield_science" => yield_science,
                "yield_production" => yield_production, "yield_gold" => yield_gold,
                "yield_culture" => yield_culture, "yield_faith" => yield_faith }
    @game.game_events.create!(
      seq: @seq += 1, session_index: 0, turn: turn, event_type: "city_snapshot", civ: civ, payload: payload
    )
  end
end
