# Who holds the ground between two capitals.
#
# `CapitalProximity` says how close two civilizations started and
# `EmpireGeometry` says how each one is shaped; neither says who settled the
# gap in between. A city standing in that gap absorbs the first attack, buys
# the turns a capital needs to raise a defence, and stages the attack going
# the other way. The corridor often fits only one city, so the side that
# settles it first usually keeps it - and the side without one has nothing
# between its capital and the rival's army.
#
# Nothing here is a verdict. The projection reports where the cities are and
# when they were founded; the prompt weighs what that was worth.
class BufferCities
  NEIGHBOUR_DISTANCE = 17
  DETOUR_TOLERANCE = 6
  MIN_NEIGHBOURS_FOR_PRIORITY = 2
  PANGAEA = /pangaea/i

  # Pangaea puts every player on one landmass with ocean at the map's edges,
  # so the seam HexGrid wraps across is not a route anyone can march.
  def self.for(game) = new(game, grid: HexGrid.new(width: nil))

  def initialize(game, grid:)
    @game = game
    @grid = grid
  end

  # `applicable: false` says the map was never examined. An empty `pairs`
  # says it was, and no two capitals started close enough to matter.
  def call
    return { applicable: false, reason: :map_not_pangaea } unless pangaea?

    {
      applicable: true, neighbour_distance: NEIGHBOUR_DISTANCE, detour_tolerance: DETOUR_TOLERANCE,
      window_turn: window_turn, pairs: pairs, priority: priority
    }
  end

  # Every buffer keyed by its plot, so a capture can be matched against it.
  # One city can hold the corridor against two rivals at once.
  def by_plot
    return {} unless pangaea?

    pairs.each_with_object({}) do |pair, plots|
      each_buffer(pair) do |civ, rival, buffer|
        (plots[[ buffer[:x], buffer[:y] ]] ||= []) << { civ: civ, rival: rival, city: buffer[:city] }
      end
    end
  end

  private

  def pairs
    @pairs ||= neighbours.map { |pair| pair_entry(pair) }
  end

  # Closest neighbours first: who had to worry about whom is the reason to
  # read this at all.
  def neighbours
    proximity.distances
      .select { |pair| pair[:distance] <= NEIGHBOUR_DISTANCE }
      .sort_by { |pair| pair[:distance] }
  end

  def pair_entry(pair)
    buffers = pair[:civs].to_h { |civ| [ civ, buffer(civ, rival_of(pair, civ), pair[:distance]) ] }

    {
      civs: pair[:civs], distance: pair[:distance], settled_first: settled_first(buffers),
      buffers: buffers, without_buffer: buffers.select { |_civ, entry| entry.nil? }.keys
    }
  end

  # Of the corridor cities a civilization owns, the one furthest forward.
  def buffer(civ, rival, distance)
    own, target = capital(civ), capital(rival)
    return unless own && target

    candidates(civ, own, target, distance).min_by { |city| [ city[:from_rival_capital], city[:turn] ] }
  end

  # Foundings only. A city taken by conquest is a different fact, and the
  # window is the game-wide deadline so both sides of one contested corridor
  # are judged against one clock.
  def candidates(civ, own, rival, distance)
    foundings_by_civ.fetch(civ, [])
      .select { |event| event.turn <= window_turn && plot_of(event) != own }
      .filter_map { |event| entry(event, own, rival, distance) }
  end

  # The detour is what an army marching from one capital to the other pays
  # for passing through this city. Betweenness is the second condition: a
  # city three hexes behind your own capital scores the same detour as one
  # three hexes to the side of the road, and is a back city, not a buffer.
  def entry(event, own, rival, distance)
    plot = plot_of(event)
    from_own = @grid.distance(own, plot)
    from_rival = @grid.distance(plot, rival)
    detour = from_own + from_rival - distance
    return unless detour <= DETOUR_TOLERANCE && from_own < distance && from_rival < distance

    {
      city: event.payload["city"], turn: event.turn, x: plot.first, y: plot.last, detour: detour,
      from_own_capital: from_own, from_rival_capital: from_rival, order: order[[ event.civ, plot ]],
      capital_population: capital_population(event.civ, event.turn),
      reach_before: reach_before(event.civ, event.turn)
    }
  end

  # Only a race both sides ran has a winner. Where one side never settled the
  # corridor the honest fact is `without_buffer`, not a won race.
  def settled_first(buffers)
    return if buffers.values.any?(&:nil?)

    earliest = buffers.min_by { |_civ, entry| entry[:turn] }
    return if buffers.count { |_civ, entry| entry[:turn] == earliest.last[:turn] } > 1

    earliest.first
  end

  # Which gap a civilization closed first, for the ones that had a choice.
  # Names only: the turns are already in the pairs.
  def priority
    secured
      .select { |civ, _rivals| neighbour_counts[civ] >= MIN_NEIGHBOURS_FOR_PRIORITY }
      .transform_values { |rivals| rivals.sort_by { |rival, turn| [ turn, rival ] }.map(&:first) }
  end

  def secured
    pairs.each_with_object({}) do |pair, civs|
      each_buffer(pair) { |civ, rival, buffer| (civs[civ] ||= []) << [ rival, buffer[:turn] ] }
    end
  end

  def each_buffer(pair)
    pair[:buffers].each do |civ, buffer|
      yield civ, rival_of(pair, civ), buffer if buffer
    end
  end

  def neighbour_counts
    @neighbour_counts ||= pairs.flat_map { |pair| pair[:civs] }.tally
  end

  # What the civilization chose to settle, so captures do not shift it and
  # the capital is always 1.
  def order
    @order ||= foundings_by_civ.each_with_object({}) do |(civ, events), numbers|
      events.each_with_index { |event, index| numbers[[ civ, plot_of(event) ]] = index + 1 }
    end
  end

  # The capital is matched by plot, never by name: one game can hold two
  # cities called the same thing.
  def capital_population(civ, turn)
    plot = capital(civ)

    populations
      .select { |event| plot_of(event) == plot && event.turn <= turn }
      .last&.payload&.[]("new_population")
  end

  # How far out the civilization had already settled before it settled the
  # corridor. A distance, never a verdict - the comparison against
  # `from_own_capital` belongs to whoever reads it.
  def reach_before(civ, turn)
    own = capital(civ)

    foundings_by_civ.fetch(civ, [])
      .select { |event| event.turn < turn }
      .map { |event| @grid.distance(own, plot_of(event)) }
      .max || 0
  end

  # Never past the end of the data.
  def window_turn
    @window_turn ||= [ EarlyGame.new(@game).deadline_turn, @game.game_events.maximum(:turn) ].compact.min
  end

  def pangaea?
    @game.map_script.to_s.match?(PANGAEA)
  end

  def proximity
    @proximity ||= CapitalProximity.new(@game, grid: @grid)
  end

  def capital(civ)
    city = proximity.capitals[civ]
    [ city[:x], city[:y] ] if city
  end

  def rival_of(pair, civ)
    (pair[:civs] - [ civ ]).first
  end

  def foundings_by_civ
    @foundings_by_civ ||= events("city_founded").select { |event| plot_of(event) }.group_by(&:civ)
  end

  def populations
    @populations ||= events("population_changed")
  end

  def events(event_type)
    @game.game_events.where(event_type: event_type).order(:seq).to_a
  end

  def plot_of(event)
    x, y = event.payload.values_at("x", "y")
    [ x, y ] if x && y
  end
end
