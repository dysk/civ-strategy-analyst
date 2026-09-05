require "test_helper"

class CapitalProximityTest < ActiveSupport::TestCase
  setup do
    @game = Game.create!(name: "Capital Proximity Test Game", map_width: 46, map_height: 20)
    @seq = 0
  end

  test "treats the first city a civ founded as its capital" do
    founded("Rome", "Roma", 0, 10, 10)
    founded("Rome", "Ostia", 30, 14, 10)

    assert_equal(
      { civ: "Rome", city: "Roma", turn: 0, x: 10, y: 10, latitude: "equatorial", longitude: nil },
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
        { civs: %w[Rome Greece], distance: 6, bearing: "E" },
        { civs: %w[Rome Carthage], distance: 6, bearing: "N" },
        { civs: %w[Greece Carthage], distance: 9, bearing: "NW" }
      ],
      proximity.distances
    )
  end

  test "measures across the map seam the short way round" do
    founded("Rome", "Roma", 0, 44, 10)
    founded("Greece", "Athens", 0, 2, 10)

    assert_equal [ { civs: %w[Rome Greece], distance: 4, bearing: "E" } ], proximity.distances
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

  test "names the latitude band each capital sits in, counting y up from the south" do
    founded("Egypt", "Thebes", 0, 10, 1)
    founded("Rome", "Roma", 0, 10, 6)
    founded("Greece", "Athens", 0, 10, 15)
    founded("Norway", "Nidaros", 0, 10, 19)

    assert_equal [ "far south", "southern", "northern", "far north" ],
      proximity.capitals.values.map { |capital| capital[:latitude] }
  end

  test "leaves latitude unsaid when the log never reported the map height" do
    @game.update!(map_height: nil)
    founded("Rome", "Roma", 0, 10, 10)

    assert_nil proximity.capitals["Rome"][:latitude]
  end

  test "a wrapping map has no fixed east or west, so a capital gets no longitude" do
    founded("Rome", "Roma", 0, 2, 10)

    assert_nil proximity.capitals["Rome"][:longitude]
  end

  test "on Pangaea the seam is ocean, so the world has edges to place a capital between" do
    pangaea
    founded("Rome", "Roma", 0, 2, 10)
    founded("Greece", "Athens", 0, 23, 10)
    founded("Carthage", "Carthago", 0, 44, 10)

    assert_equal [ "far west", "central", "far east" ],
      CapitalProximity.for(@game).capitals.values.map { |capital| capital[:longitude] }
  end

  test "on Pangaea nothing marches across the seam, so distance and bearing go the long way" do
    pangaea
    founded("Rome", "Roma", 0, 44, 10)
    founded("Greece", "Athens", 0, 2, 10)

    assert_equal [ { civs: %w[Rome Greece], distance: 42, bearing: "W" } ],
      CapitalProximity.for(@game).distances
  end

  test "builds its own bounds from the game's map" do
    founded("Rome", "Roma", 0, 10, 6)

    assert_equal "southern", CapitalProximity.for(@game).capitals["Rome"][:latitude]
  end

  private

  def proximity
    CapitalProximity.new(@game, grid: HexGrid.new(width: 46), bounds: MapBounds.new(@game))
  end

  def pangaea
    @game.update!(map_script: 'Assets\\Maps\\Lekmap v5.2\\LekmapPangaeaFractalv5.2.lua')
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
