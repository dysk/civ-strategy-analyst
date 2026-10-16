require "test_helper"

class TileOwnershipTest < ActiveSupport::TestCase
  # The six plots a hex away from [ 10, 10 ], which lean west above and
  # below the row because of the grid's stagger.
  DELHI_RING = [ [ 11, 10 ], [ 9, 10 ], [ 10, 11 ], [ 9, 9 ], [ 10, 9 ], [ 9, 11 ] ].freeze

  setup do
    @game = Game.create!(name: "Tile Ownership Test Game")
    @seq = 0
  end

  test "a plot nobody has settled or claimed belongs to no city" do
    founded("India", "Delhi", 1, 10, 10)

    assert_nil tiles.owner([ 20, 20 ], turn: 5)
  end

  test "a plot out of the index is read as an inference, not as a holding" do
    founded("India", "Delhi", 1, 10, 10)

    assert_equal :nearest, tiles.owner([ 13, 10 ], turn: 1)[:source]
  end

  test "a city owns the plot it stands on" do
    founded("India", "Delhi", 1, 10, 10)

    assert_equal({ city: "Delhi", civ: "India", source: :owned }, tiles.owner([ 10, 10 ], turn: 1))
  end

  test "a city owns the ring around it from the turn it was founded" do
    founded("India", "Delhi", 1, 10, 10)

    assert_equal [ "Delhi" ] * 6, DELHI_RING.map { |plot| tiles.owner(plot, turn: 1)&.fetch(:city) }
  end

  test "a founding claims no further than its own ring" do
    founded("India", "Delhi", 1, 10, 10)

    assert_equal :adjacent, tiles.owner([ 12, 10 ], turn: 1)[:source]
  end

  test "a founding leaves a plot another city already holds alone" do
    founded("India", "Delhi", 1, 10, 10)
    acquired("India", "Delhi", 4, 12, 10)
    founded("Tibet", "Lhasa", 10, 13, 10)

    assert_equal "Delhi", tiles.owner([ 12, 10 ], turn: 10)[:city]
  end

  test "an acquired plot belongs to the city that acquired it" do
    founded("India", "Delhi", 1, 10, 10)
    acquired("India", "Delhi", 4, 12, 10)

    assert_equal({ city: "Delhi", civ: "India", source: :owned }, tiles.owner([ 12, 10 ], turn: 4))
  end

  test "a bought plot belongs to the city that bought it" do
    founded("Tibet", "Lhasa", 1, 20, 20)
    bought("Tibet", "Lhasa", 6, 22, 20)

    assert_equal({ city: "Lhasa", civ: "Tibet", source: :owned }, tiles.owner([ 22, 20 ], turn: 6))
  end

  test "a plot is out of the index on the turns before it was claimed" do
    founded("India", "Delhi", 1, 10, 10)
    acquired("India", "Delhi", 4, 12, 10)

    assert_equal :adjacent, tiles.owner([ 12, 10 ], turn: 3)[:source]
  end

  test "an acquisition names its city even when the founding predates the log" do
    acquired("Iroquois", "Onondaga", 4, 29, 29)

    assert_equal({ city: "Onondaga", civ: "Iroquois", source: :owned }, tiles.owner([ 29, 29 ], turn: 4))
  end

  test "a captured city keeps its plots and hands them to the new owner" do
    founded("Iroquois", "Onondaga", 1, 29, 29)
    acquired("Iroquois", "Onondaga", 4, 31, 29)
    captured("Onondaga", 152, 29, 29, from: "Iroquois", to: "India")

    assert_equal({ city: "Onondaga", civ: "India", source: :owned }, tiles.owner([ 31, 29 ], turn: 152))
  end

  test "a captured city's plots are the old owner's up to the capture" do
    founded("Iroquois", "Onondaga", 1, 29, 29)
    captured("Onondaga", 152, 29, 29, from: "Iroquois", to: "India")

    assert_equal "Iroquois", tiles.owner([ 29, 29 ], turn: 151)[:civ]
  end

  test "the capture turn reads as the new owner's, the way a turn's last snapshot does" do
    founded("Iroquois", "Onondaga", 1, 29, 29)
    captured("Onondaga", 152, 29, 29, from: "Iroquois", to: "India")

    assert_equal({ city: "Onondaga", civ: "India", source: :owned }, tiles.owner([ 29, 29 ], turn: 152))
  end

  test "a destroyed city's land is nobody's" do
    founded("Iroquois", "Onondaga", 1, 29, 29)
    acquired("Iroquois", "Onondaga", 4, 31, 29)
    destroyed("Iroquois", "Onondaga", 153, 29, 29)

    assert_nil tiles.owner([ 31, 29 ], turn: 153)
  end

  test "a destruction logged twice leaves the land released" do
    founded("Iroquois", "Onondaga", 1, 29, 29)
    destroyed("Iroquois", "Onondaga", 153, 29, 29)
    destroyed("Iroquois", "Onondaga", 153, 29, 29)

    assert_nil tiles.owner([ 29, 29 ], turn: 160)
  end

  test "a destroyed city still held its land before it fell" do
    founded("Iroquois", "Onondaga", 1, 29, 29)
    destroyed("Iroquois", "Onondaga", 153, 29, 29)

    assert_equal "Onondaga", tiles.owner([ 29, 29 ], turn: 152)[:city]
  end

  test "a plot beside a city's land is read as that city's, as an inference" do
    founded("India", "Delhi", 1, 10, 10)

    assert_equal({ city: "Delhi", civ: "India", source: :adjacent }, tiles.owner([ 12, 10 ], turn: 1))
  end

  test "a plot is beside nothing until the city next to it exists" do
    founded("India", "Delhi", 10, 10, 10)

    assert_nil tiles.owner([ 12, 10 ], turn: 9)
  end

  test "the ring beats the nearest centre" do
    founded("India", "Delhi", 1, 10, 10)
    founded("Tibet", "Lhasa", 2, 13, 10)

    assert_equal({ city: nil, civ: nil, source: :adjacent }, tiles.owner([ 11, 9 ], turn: 2))
  end

  test "holding a plot beats standing next to one" do
    founded("India", "Delhi", 1, 10, 10)
    founded("Tibet", "Lhasa", 2, 14, 10)
    acquired("Tibet", "Lhasa", 5, 12, 10)

    assert_equal({ city: "Lhasa", civ: "Tibet", source: :owned }, tiles.owner([ 12, 10 ], turn: 5))
  end

  test "two of a civ's cities beside a plot name the civ and leave the city open" do
    founded("India", "Delhi", 1, 10, 10)
    founded("India", "Agra", 2, 13, 10)

    assert_equal({ city: nil, civ: "India", source: :adjacent }, tiles.owner([ 11, 9 ], turn: 2))
  end

  test "a border hex between two rivals names neither of them" do
    founded("India", "Delhi", 1, 10, 10)
    founded("Tibet", "Lhasa", 2, 13, 10)

    assert_equal({ city: nil, civ: nil, source: :adjacent }, tiles.owner([ 11, 9 ], turn: 2))
  end

  test "a border hex keeps both its neighbours as candidates" do
    founded("India", "Delhi", 1, 10, 10)
    founded("Tibet", "Lhasa", 2, 13, 10)

    found = tiles.candidates([ 11, 9 ], turn: 2)

    assert_equal(
      { cities: [ "Delhi", "Lhasa" ], civs: [ "India", "Tibet" ], source: :adjacent },
      { cities: found[:cities].sort, civs: found[:civs].sort, source: found[:source] }
    )
  end

  test "a plot in the index has itself as its only candidate" do
    founded("India", "Delhi", 1, 10, 10)

    assert_equal(
      { cities: [ "Delhi" ], civs: [ "India" ], source: :owned },
      tiles.candidates([ 10, 10 ], turn: 1)
    )
  end

  test "the ring is the six plots a hex away, not the eight a square has" do
    founded("Tibet", "Lhasa", 1, 20, 20)
    acquired("Tibet", "Lhasa", 5, 11, 11)

    assert_nil tiles.owner([ 10, 10 ], turn: 5)
  end

  test "a plot beyond everybody's borders is read off the nearest city centre" do
    founded("India", "Delhi", 1, 10, 10)

    assert_equal({ city: "Delhi", civ: "India", source: :nearest }, tiles.owner([ 13, 10 ], turn: 1))
  end

  test "the nearer centre wins" do
    founded("India", "Delhi", 1, 10, 10)
    founded("Tibet", "Lhasa", 2, 17, 10)

    assert_equal({ city: "Delhi", civ: "India", source: :nearest }, tiles.owner([ 13, 10 ], turn: 2))
  end

  test "a plot five hexes out can still be named, the furthest a city ever claims" do
    founded("India", "Delhi", 1, 10, 10)

    assert_equal({ city: "Delhi", civ: "India", source: :nearest }, tiles.owner([ 15, 10 ], turn: 1))
  end

  test "a plot further out than any city can reach is nowhere" do
    founded("India", "Delhi", 1, 10, 10)

    assert_nil tiles.owner([ 16, 10 ], turn: 1)
  end

  test "two of a civ's centres equally near name the civ and leave the city open" do
    founded("India", "Delhi", 1, 10, 10)
    founded("India", "Agra", 2, 16, 10)

    assert_equal({ city: nil, civ: "India", source: :nearest }, tiles.owner([ 13, 10 ], turn: 2))
  end

  test "two rivals equally near name neither of them" do
    founded("India", "Delhi", 1, 10, 10)
    founded("Tibet", "Lhasa", 2, 16, 10)

    assert_equal({ city: nil, civ: nil, source: :nearest }, tiles.owner([ 13, 10 ], turn: 2))
  end

  test "equally near centres both stay as candidates" do
    founded("India", "Delhi", 1, 10, 10)
    founded("Tibet", "Lhasa", 2, 16, 10)

    found = tiles.candidates([ 13, 10 ], turn: 2)

    assert_equal(
      { cities: [ "Delhi", "Lhasa" ], civs: [ "India", "Tibet" ], source: :nearest },
      { cities: found[:cities].sort, civs: found[:civs].sort, source: found[:source] }
    )
  end

  test "a city is no centre to measure from before it is founded" do
    founded("India", "Delhi", 10, 10, 10)

    assert_nil tiles.owner([ 13, 10 ], turn: 9)
  end

  test "a razed city is no centre to measure from either" do
    founded("Iroquois", "Onondaga", 1, 29, 29)
    destroyed("Iroquois", "Onondaga", 10, 29, 29)

    assert_nil tiles.owner([ 32, 29 ], turn: 11)
  end

  test "a captured centre is measured as its new owner's" do
    founded("Iroquois", "Onondaga", 1, 29, 29)
    captured("Onondaga", 152, 29, 29, from: "Iroquois", to: "India")

    assert_equal({ city: "Onondaga", civ: "India", source: :nearest }, tiles.owner([ 32, 29 ], turn: 152))
  end

  private

  def tiles
    TileOwnership.new(@game, grid: HexGrid.new(width: 46))
  end

  def founded(civ, city, turn, x, y)
    event(turn, "city_founded", civ: civ, payload: { "city" => city, "x" => x, "y" => y })
  end

  def acquired(civ, city, turn, x, y)
    event(turn, "plot_acquired", civ: civ, payload: { "city" => city, "x" => x, "y" => y })
  end

  def bought(civ, city, turn, x, y)
    event(turn, "plot_bought", civ: civ, payload: { "city" => city, "x" => x, "y" => y, "bought_with" => "culture" })
  end

  def captured(city, turn, x, y, from:, to:)
    event(turn, "city_captured",
      payload: { "city" => city, "x" => x, "y" => y, "old_owner" => from, "new_owner" => to })
  end

  def destroyed(civ, city, turn, x, y)
    event(turn, "city_destroyed", civ: civ, payload: { "city" => city, "x" => x, "y" => y })
  end

  def event(turn, event_type, payload:, civ: nil)
    @seq += 1
    @game.game_events.create!(
      seq: @seq, session_index: 0, turn: turn, event_type: event_type, civ: civ, payload: payload
    )
  end
end
