# Which city holds a plot, and how we know. The log attributes most tiles
# itself - `plot_acquired` and `plot_bought` both name the city - so this
# reads ownership out of the log instead of inferring it from geometry.
# `docs/tile-ownership.md` has the measurements and the stages still to come.
#
# Cities are joined by name, the only handle an acquisition gives. Two cities
# named alike therefore read as one, which a player can arrange and almost
# never does; "the battle was at Delhi" stays true either way.
class TileOwnership
  REPLAYED_EVENTS = %w[city_founded plot_acquired plot_bought city_captured city_destroyed].freeze

  # How far geometry may reach for a name. A city cannot own a plot more than
  # five hexes from its centre - the game's own acquire limit, and no claim in
  # india-diplo, chile-vs-vietnam or babylon-domination breaks it - so beyond
  # that a name would be an invention rather than an inference.
  REACH = 5

  def self.for(game)
    game.projection(self) { new(game, grid: HexGrid.new(width: MapBounds.for(game).width)) }
  end

  def initialize(game, grid:)
    @grid = grid
    @events = REPLAYED_EVENTS.flat_map { |type| game.event_log.of_type(type) }.sort_by(&:seq)
  end

  # Who holds `plot` at the end of `turn`, filled in only as far as the
  # candidates agree - a hex between two empires names neither side, and its
  # `source` is what tells a consumer to go and read them off `candidates`.
  def owner(plot, turn:)
    found = candidates(plot, turn: turn)
    return unless found

    { city: lone(found[:cities]), civ: lone(found[:civs]), source: found[:source] }
  end

  # Every city the log lets us name for `plot` - the one holding it, the ones
  # holding the ring around it, or the nearest standing centres within reach -
  # and nil for a plot too far out for any of them. A capture or a razing
  # counts for the whole turn it happened on.
  def candidates(plot, turn:)
    replay
    holder = holder_at(plot, turn)
    return naming([ holder ], :owned) if holder

    around = @grid.neighbours(plot).filter_map { |neighbour| holder_at(neighbour, turn) }
    return naming(around, :adjacent) if around.any?

    nearest = nearest_cities(plot, turn)
    naming(nearest, :nearest) if nearest.any?
  end

  private

  def holder_at(plot, turn)
    Array(@history[plot]).reverse_each.find { |held_from, _| held_from <= turn }&.last
  end

  # Every city standing at `turn` whose centre is as near `plot` as the
  # nearest is. Equally near cities all come back, since a tiebreak by name or
  # by founding turn would read as a fact and would not be one.
  def nearest_cities(plot, turn)
    within_reach = @centres.filter_map { |centre|
      holder = holder_at(centre, turn)
      distance = @grid.distance(plot, centre)
      [ distance, holder ] if holder && distance <= REACH
    }
    nearest = within_reach.map(&:first).min

    within_reach.select { |distance, _| distance == nearest }.map(&:last)
  end

  def naming(holders, source)
    { cities: holders.map { |h| h[:city] }.uniq, civs: holders.map { |h| h[:civ] }.uniq, source: source }
  end

  def lone(names) = (names.first if names.one?)

  # Ownership moves during a game, so the index is a replay in log order
  # rather than one table. `@held` is the live picture, `@history` is every
  # change each plot went through, and `@plots` is what a city would lose.
  def replay
    @replay ||= begin
      @held = {}
      @history = {}
      @centres = []
      @plots = Hash.new { |plots, city| plots[city] = [] }

      @events.each { |event| apply(event) }
      true
    end
  end

  def apply(event)
    case event.event_type
    when "city_founded" then found(event)
    when "plot_acquired", "plot_bought" then claim(plot_of(event), event.turn, holder_of(event))
    when "city_captured" then capture(event)
    when "city_destroyed" then raze(event)
    end
  end

  # A city takes the plot it stands on and the ring around it. No other
  # centre can be nearer than three hexes, so that ring is unambiguously its
  # own - but a plot another city already holds stays where it is, the way
  # the game leaves settled borders alone.
  def found(event)
    centre = plot_of(event)
    return unless centre

    holder = holder_of(event)
    @centres << centre unless @centres.include?(centre)
    claim(centre, event.turn, holder)
    @grid.neighbours(centre).each { |plot| claim(plot, event.turn, holder) unless @held[plot] }
  end

  def claim(plot, turn, holder)
    return unless plot && holder[:city]

    previous = @held[plot]
    return if previous == holder

    @plots[previous[:city]].delete(plot) if previous
    @held[plot] = holder
    @plots[holder[:city]] << plot
    record(plot, turn, holder)
  end

  # A capture moves the city's whole territory, name and all, to its taker.
  def capture(event)
    city, new_owner = event.payload.values_at("city", "new_owner")
    return unless city && new_owner

    holder = { city: city, civ: new_owner }
    @plots[city].each do |plot|
      @held[plot] = holder
      record(plot, event.turn, holder)
    end
  end

  # Razing releases the land with no event naming the plots, and the log can
  # fire the destruction twice for the same city, so this has to hold up on a
  # city that is already gone.
  def raze(event)
    @plots.delete(event.payload["city"])&.each do |plot|
      @held.delete(plot)
      record(plot, event.turn, nil)
    end
  end

  def record(plot, turn, holder)
    (@history[plot] ||= []) << [ turn, holder ]
  end

  def holder_of(event) = { city: event.payload["city"], civ: event.civ }

  def plot_of(event)
    x, y = event.payload.values_at("x", "y")
    [ x, y ] if x && y
  end
end
