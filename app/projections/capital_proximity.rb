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
  def self.for(game)
    new(game, grid: HexGrid.new(width: MapBounds.new(game).width))
  end

  def initialize(game, grid:)
    @grid = grid
    @foundings = game.game_events.where(event_type: "city_founded").order(:seq).to_a
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

  def distances
    capitals.values.combination(2).map do |from, to|
      { civs: [ from[:civ], to[:civ] ], distance: @grid.distance(plot(from), plot(to)) }
    end
  end

  private

  def entry(event)
    x, y = event.payload.values_at("x", "y")
    return unless x && y && event.civ

    { civ: event.civ, city: event.payload["city"], turn: event.turn, x: x, y: y }
  end

  def plot(city)
    [ city[:x], city[:y] ]
  end
end
