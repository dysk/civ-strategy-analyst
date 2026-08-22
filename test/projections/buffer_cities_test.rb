require "test_helper"

# Coordinates are read off the corridor diagram in docs/buffer-city.md:
# Rome's capital at (10, 20) and Greece's at (27, 20) are 17 hexes apart,
# so every plot between them has a detour equal to its rows off that line.
class BufferCitiesTest < ActiveSupport::TestCase
  ROME_CAPITAL = [ 10, 20 ].freeze
  GREECE_CAPITAL = [ 27, 20 ].freeze

  setup do
    @game = Game.create!(
      name: "Buffer Cities Test Game",
      map_script: 'Assets\Maps\Lekmap v5.2\LekmapPangaeaFractalv5.2.lua',
      game_speed: "GAMESPEED_QUICK"
    )
    @seq = 0
    logged_through(200)
  end

  test "call reports a map that is not Pangaea as not applicable" do
    @game.update!(map_script: "Continents")
    capitals

    assert_equal({ applicable: false, reason: :map_not_pangaea }, buffer_cities.call)
  end

  test "call states the thresholds and the window it applied" do
    capitals
    digest = buffer_cities.call

    assert_equal true, digest[:applicable]
    assert_equal 17, digest[:neighbour_distance]
    assert_equal 6, digest[:detour_tolerance]
    assert_equal 100, digest[:window_turn]
  end

  test "call does not pair capitals further apart than the neighbour distance" do
    founded("Rome", "Roma", 0, *ROME_CAPITAL)
    founded("Greece", "Athenai", 0, 28, 20)

    assert_empty buffer_cities.call[:pairs]
  end

  test "call counts a city on the line between two capitals as a buffer" do
    capitals
    founded("Rome", "Ostia", 30, 18, 20)

    assert_equal(
      { city: "Ostia", turn: 30, x: 18, y: 20, detour: 0,
        from_own_capital: 8, from_rival_capital: 9,
        order: 2, capital_population: nil, reach_before: 0 },
      pair[:buffers]["Rome"]
    )
  end

  test "call counts a city at the edge of the detour tolerance as a buffer" do
    capitals
    founded("Rome", "Ostia", 30, 18, 26)

    assert_equal 6, pair[:buffers]["Rome"][:detour]
  end

  test "call rejects a city beyond the detour tolerance" do
    capitals
    founded("Rome", "Ostia", 30, 18, 27)

    assert_nil pair[:buffers]["Rome"]
  end

  test "call rejects a city behind its own capital though its detour is within tolerance" do
    capitals
    founded("Rome", "Ostia", 30, 7, 20)

    assert_nil pair[:buffers]["Rome"]
  end

  test "call rejects a city past the rival capital" do
    capitals
    founded("Rome", "Ostia", 30, 30, 20)

    assert_nil pair[:buffers]["Rome"]
  end

  test "call picks the corridor city closest to the rival capital as the buffer" do
    capitals
    founded("Rome", "Ostia", 30, 14, 20)
    founded("Rome", "Neapolis", 40, 22, 20)

    assert_equal "Neapolis", pair[:buffers]["Rome"][:city]
    assert_equal 5, pair[:buffers]["Rome"][:from_rival_capital]
  end

  test "call lists a civ with no corridor city in without_buffer" do
    capitals
    founded("Rome", "Ostia", 30, 18, 20)

    assert_nil pair[:buffers]["Greece"]
    assert_equal %w[Greece], pair[:without_buffer]
  end

  test "call measures capital distance without wrapping across the map edge" do
    @game.update!(map_width: 46)
    founded("Rome", "Roma", 0, 44, 10)
    founded("Greece", "Athenai", 0, 2, 10)

    assert_empty buffer_cities.call[:pairs]
  end

  test "call lets one city be the buffer against two rivals" do
    capitals
    founded("Egypt", "Thebes", 0, 15, 13)
    founded("Rome", "Ostia", 30, 18, 20)

    assert_equal(
      [ { civ: "Rome", rival: "Greece", city: "Ostia" }, { civ: "Rome", rival: "Egypt", city: "Ostia" } ].sort_by { |b| b[:rival] },
      buffer_cities.by_plot.fetch([ 18, 20 ]).sort_by { |b| b[:rival] }
    )
  end

  test "call ignores a city founded after the window turn" do
    capitals
    founded("Rome", "Ostia", 101, 18, 20)

    assert_nil pair[:buffers]["Rome"]
  end

  test "call caps the window turn at the last logged turn" do
    @game.game_events.destroy_all
    logged_through(40)
    capitals
    founded("Rome", "Ostia", 30, 18, 20)

    assert_equal 40, buffer_cities.call[:window_turn]
  end

  test "call does not treat a captured city as a buffer" do
    capitals
    founded("Greece", "Neapolis", 30, 18, 20)
    captured("Neapolis", 40, from: "Greece", to: "Rome", x: 18, y: 20)

    assert_nil pair[:buffers]["Rome"]
  end

  test "call numbers the buffer among its own civ's foundings, ignoring captures" do
    capitals
    founded("Greece", "Neapolis", 10, 20, 20)
    captured("Neapolis", 20, from: "Greece", to: "Rome", x: 20, y: 20)
    founded("Rome", "Ostia", 30, 18, 20)

    assert_equal 2, pair[:buffers]["Rome"][:order]
  end

  test "call reads the capital population as it stood on the founding turn" do
    capitals
    population("Roma", 10, 4, *ROME_CAPITAL)
    population("Roma", 40, 7, *ROME_CAPITAL)
    founded("Rome", "Ostia", 30, 18, 20)

    assert_equal 4, pair[:buffers]["Rome"][:capital_population]
  end

  test "call leaves the capital population nil when the log carries none" do
    capitals
    founded("Rome", "Ostia", 30, 18, 20)

    assert_nil pair[:buffers]["Rome"][:capital_population]
  end

  test "call names the civ that settled the corridor earlier in settled_first" do
    capitals
    founded("Rome", "Ostia", 30, 14, 20)
    founded("Greece", "Sparta", 20, 22, 20)

    assert_equal "Greece", pair[:settled_first]
  end

  test "call leaves settled_first nil when only one side settled the corridor" do
    capitals
    founded("Rome", "Ostia", 30, 18, 20)

    assert_nil pair[:settled_first]
  end

  test "call leaves settled_first nil when both sides settled on the same turn" do
    capitals
    founded("Rome", "Ostia", 30, 14, 20)
    founded("Greece", "Sparta", 30, 22, 20)

    assert_nil pair[:settled_first]
  end

  test "call reports the furthest earlier founding as reach_before" do
    capitals
    founded("Rome", "Neapolis", 10, 10, 27)
    founded("Rome", "Ostia", 30, 18, 20)

    assert_equal 7, pair[:buffers]["Rome"][:reach_before]
  end

  test "call reports reach_before as zero when the buffer is the first expansion" do
    capitals
    founded("Rome", "Ostia", 30, 18, 20)

    assert_equal 0, pair[:buffers]["Rome"][:reach_before]
  end

  test "call excludes foundings on or after the buffer's turn from reach_before" do
    capitals
    founded("Rome", "Ostia", 30, 18, 20)
    founded("Rome", "Neapolis", 30, 10, 27)
    founded("Rome", "Pompeii", 40, 10, 30)

    assert_equal 0, pair[:buffers]["Rome"][:reach_before]
  end

  test "call orders a civ's rivals in priority by the turn it buffered each" do
    capitals
    founded("Egypt", "Thebes", 0, 15, 13)
    founded("Rome", "Neapolis", 20, 14, 17)
    founded("Rome", "Ostia", 30, 18, 20)

    assert_equal({ "Rome" => %w[Egypt Greece] }, buffer_cities.call[:priority])
  end

  test "call omits a civ with a single neighbour from priority" do
    capitals
    founded("Rome", "Ostia", 30, 18, 20)

    assert_empty buffer_cities.call[:priority]
  end

  test "call omits rivals a civ never buffered from priority" do
    capitals
    founded("Egypt", "Thebes", 0, 10, 30)
    founded("Rome", "Ostia", 30, 18, 20)

    assert_equal({ "Rome" => %w[Greece] }, buffer_cities.call[:priority])
  end

  test "by_plot is empty when the map is not Pangaea" do
    @game.update!(map_script: "Continents")
    capitals
    founded("Rome", "Ostia", 30, 18, 20)

    assert_empty buffer_cities.by_plot
  end

  private

  def buffer_cities
    BufferCities.for(@game)
  end

  def pair
    buffer_cities.call[:pairs].find { |entry| entry[:civs].sort == %w[Greece Rome] }
  end

  def capitals
    founded("Rome", "Roma", 0, *ROME_CAPITAL)
    founded("Greece", "Athenai", 0, *GREECE_CAPITAL)
  end

  def founded(civ, city, turn, x, y)
    event(civ, "city_founded", turn, city: city, x: x, y: y)
  end

  def captured(city, turn, from:, to:, x:, y:)
    event(nil, "city_captured", turn, city: city, old_owner: from, new_owner: to, x: x, y: y)
  end

  def population(city, turn, new_population, x, y)
    event(nil, "population_changed", turn, city: city, new_population: new_population, x: x, y: y)
  end

  def logged_through(turn)
    event("Rome", "snapshot", turn, score: 100)
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
