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

    assert_nil tiles.owner([ 12, 10 ], turn: 1)
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

  test "a plot belongs to nobody on the turns before it was claimed" do
    founded("India", "Delhi", 1, 10, 10)
    acquired("India", "Delhi", 4, 12, 10)

    assert_nil tiles.owner([ 12, 10 ], turn: 3)
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
