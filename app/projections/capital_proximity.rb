# How far apart the civilizations started.
#
# `EmpireGeometry` measures the shape of one empire; this measures the gaps
# between them. A large army is a different fact depending on who is within
# reach of it, and two capitals fifteen hexes apart describe a game where
# early aggression is possible in a way that fifty hexes does not.
#
# Only capitals are measured. Every civilization has exactly one, it is
# usually founded on turn zero (a settler moved before founding can push
# that a turn or two), and it never moves afterward - so the distances
# hold for the whole game and cannot be skewed by how much either side
# later expanded.
class CapitalProximity
  # On Pangaea the seam the coordinates wrap across is ocean, so neither a
  # distance nor a bearing may take the short way round it.
  def self.for(game)
    game.projection(self) { new(game, grid: grid_for(game), bounds: MapBounds.for(game)) }
  end

  def self.grid_for(game)
    HexGrid.new(width: (MapBounds.for(game).width unless game.pangaea?))
  end

  def initialize(game, grid:, bounds:)
    @game = game
    @grid = grid
    @bounds = bounds
    @foundings = game.event_log.of_type("city_founded")
  end

  def call
    { capitals: capitals, distances: distances }
  end

  # A civilization's capital is the first city it founded. Cities captured
  # later are somebody else's capital and do not replace it.
  def capitals
    @capitals ||= @foundings
      .filter_map { |event| entry(event) }
      .group_by { |city| city[:civ] }
      .transform_values(&:first)
  end

  # `bearing` reads from the first civilization towards the second.
  def distances
    capitals.values.combination(2).map do |from, to|
      {
        civs: [ from[:civ], to[:civ] ],
        distance: @grid.distance(plot(from), plot(to)),
        bearing: @grid.bearing(plot(from), plot(to))
      }
    end
  end

  private

  def entry(event)
    x, y = event.payload.values_at("x", "y")
    return unless x && y && event.civ

    {
      civ: event.civ, city: event.payload["city"], turn: event.turn, x: x, y: y,
      latitude: @bounds.latitude(y), longitude: longitude(x)
    }
  end

  # A map that wraps has no fixed east or west - only Pangaea's ocean edges
  # make a longitude something a reader can point at.
  def longitude(x)
    @bounds.longitude(x) if @game.pangaea?
  end

  def plot(city)
    [ city[:x], city[:y] ]
  end
end
