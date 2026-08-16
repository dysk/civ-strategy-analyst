# How an empire is laid out on the map, recomputed whenever a civilization
# gains or loses a city. Cities are tracked by plot rather than by name,
# since a plot survives every way a city can change hands.
class EmpireGeometry
  OWNERSHIP_EVENTS = %w[city_founded city_captured].freeze
  REPLAYED_EVENTS = (OWNERSHIP_EVENTS + %w[snapshot]).freeze

  def initialize(game, grid:)
    @grid = grid
    @events = game.game_events.where(event_type: REPLAYED_EVENTS).order(:seq).to_a
  end

  def series(civ)
    replay
    @series[civ] || []
  end

  # Turns where the game's own city count parted ways with the one we can
  # place on the map - a city razed out of existence leaves no event behind.
  def discrepancies(civ)
    replay
    @discrepancies[civ] || []
  end

  private

  def replay
    @replay ||= begin
      @owned = Hash.new { |plots, civ| plots[civ] = [] }
      @series = Hash.new { |entries, civ| entries[civ] = [] }
      @discrepancies = Hash.new { |entries, civ| entries[civ] = [] }
      @gaps = Hash.new(0)

      @events.each { |event| event.event_type == "snapshot" ? reconcile(event) : transfer(event) }
      true
    end
  end

  def transfer(event)
    plot = plot_of(event)
    return unless plot

    transfers_of(event).each do |civ, change|
      change == :gained ? @owned[civ] << plot : @owned[civ].delete(plot)
      @series[civ] << entry(event.turn, @owned[civ])
    end
  end

  # Events are replayed in log order rather than by turn: a snapshot reports
  # the state before that turn's own foundings and captures.
  def reconcile(event)
    reported = event.payload["cities"]
    return unless event.civ && reported

    counted = @owned[event.civ].size
    gap = counted - reported
    return if gap == @gaps[event.civ]

    @gaps[event.civ] = gap
    @discrepancies[event.civ] << { turn: event.turn, counted: counted, reported: reported } unless gap.zero?
  end

  # A capture moves one plot between two empires, so both sides' shape changes.
  def transfers_of(event)
    return [ [ event.civ, :gained ] ] if event.event_type == "city_founded"

    [ [ event.payload["new_owner"], :gained ], [ event.payload["old_owner"], :lost ] ]
      .reject { |civ, _change| civ.nil? }
  end

  def plot_of(event)
    x, y = event.payload.values_at("x", "y")
    [ x, y ] if x && y
  end

  def entry(turn, plots)
    distances = plots.combination(2).map { |a, b| @grid.distance(a, b) }

    {
      turn: turn,
      cities: plots.size,
      span: plots.any? ? (distances.max || 0) : nil,
      mean_spacing: mean_spacing(plots),
      elongation: elongation(distances)
    }
  end

  # How far a city sits from its closest neighbour, averaged over the empire.
  def mean_spacing(plots)
    return nil if plots.size < 2

    nearest = plots.map { |plot| (plots - [ plot ]).map { |other| @grid.distance(plot, other) }.min }
    (nearest.sum.to_f / nearest.size).round(1)
  end

  # The widest reach measured against the typical one: a compact empire sits
  # near 1.4, one strung out along a line at 2 and above.
  def elongation(distances)
    return nil if distances.empty?

    (distances.max / (distances.sum.to_f / distances.size)).round(2)
  end
end
