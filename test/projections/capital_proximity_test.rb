require "test_helper"

class CapitalProximityTest < ActiveSupport::TestCase
  setup do
    @game = Game.create!(name: "Capital Proximity Test Game", map_width: 46)
    @seq = 0
  end

  test "treats the first city a civ founded as its capital" do
    founded("Rome", "Roma", 0, 10, 10)
    founded("Rome", "Ostia", 30, 14, 10)

    assert_equal(
      { civ: "Rome", city: "Roma", turn: 0, x: 10, y: 10 },
      proximity.capitals["Rome"]
    )
  end

  test "a captured capital does not replace the captor's own" do
    founded("Rome", "Roma", 0, 10, 10)
    founded("Greece", "Athens", 0, 20, 10)
    event(nil, "city_captured", 40, city: "Athens", old_owner: "Greece", new_owner: "Rome", x: 20, y: 10)

    assert_equal "Roma", proximity.capitals["Rome"][:city]
  end

  test "measures every pair of capitals" do
    founded("Rome", "Roma", 0, 10, 10)
    founded("Greece", "Athens", 0, 16, 10)
    founded("Carthage", "Carthago", 0, 10, 16)

    assert_equal(
      [
        { civs: %w[Rome Greece], distance: 6 },
        { civs: %w[Rome Carthage], distance: 6 },
        { civs: %w[Greece Carthage], distance: 9 }
      ],
      proximity.distances
    )
  end

  test "measures across the map seam the short way round" do
    founded("Rome", "Roma", 0, 44, 10)
    founded("Greece", "Athens", 0, 2, 10)

    assert_equal [ { civs: %w[Rome Greece], distance: 4 } ], proximity.distances
  end

  test "ignores cities founded without coordinates" do
    event("Rome", "city_founded", 0, city: "Roma")

    assert_empty proximity.capitals
    assert_empty proximity.distances
  end

  test "a lone civilization has a capital but no distances" do
    founded("Rome", "Roma", 0, 10, 10)

    assert_equal %w[Rome], proximity.capitals.keys
    assert_empty proximity.distances
  end

  test "builds its own grid from the game's map width" do
    founded("Rome", "Roma", 0, 44, 10)
    founded("Greece", "Athens", 0, 2, 10)

    assert_equal 4, CapitalProximity.for(@game).distances.first[:distance]
  end

  private

  def proximity
    CapitalProximity.new(@game, grid: HexGrid.new(width: 46))
  end

  def founded(civ, city, turn, x, y)
    event(civ, "city_founded", turn, city: city, x: x, y: y)
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
