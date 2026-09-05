# Distances only wrap correctly when the map's width is known. Newer logs
# report it; for older ones the easternmost plot anyone ever touched is the
# best available lower bound.
class MapBounds
  extend Projection

  LATITUDE_BANDS = [ "far south", "southern", "equatorial", "northern", "far north" ].freeze
  LONGITUDE_BANDS = [ "far west", "western", "central", "eastern", "far east" ].freeze
  BAND_EDGES = [ 0.15, 0.4, 0.6, 0.85 ].freeze

  def initialize(game)
    @game = game
  end

  def width
    @game.map_width || easternmost_plot&.succ
  end

  def height
    @game.map_height || northernmost_plot&.succ
  end

  # Where a plot falls between the map's edges. Only a dimension the log
  # reported can name a band: an estimated one is the furthest plot anyone
  # touched, which would put the outermost city at the pole by construction.
  def latitude(y)
    band(y, @game.map_height, LATITUDE_BANDS)
  end

  def longitude(x)
    band(x, @game.map_width, LONGITUDE_BANDS)
  end

  def estimated?
    @game.map_width.nil? && width.present?
  end

  private

  def band(position, extent, names)
    return unless extent&.positive? && position

    names[BAND_EDGES.count { |edge| position.to_f / extent >= edge }]
  end

  def easternmost_plot
    @game.event_log.all.filter_map { |event| event.payload["x"] }.max
  end

  def northernmost_plot
    @game.event_log.all.filter_map { |event| event.payload["y"] }.max
  end
end
