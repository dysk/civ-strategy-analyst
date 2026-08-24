# Distances only wrap correctly when the map's width is known. Newer logs
# report it; for older ones the easternmost plot anyone ever touched is the
# best available lower bound.
class MapBounds
  extend Projection

  def initialize(game)
    @game = game
  end

  def width
    @game.map_width || easternmost_plot&.succ
  end

  def height
    @game.map_height || northernmost_plot&.succ
  end

  def estimated?
    @game.map_width.nil? && width.present?
  end

  private

  def easternmost_plot
    @game.event_log.all.filter_map { |event| event.payload["x"] }.max
  end

  def northernmost_plot
    @game.event_log.all.filter_map { |event| event.payload["y"] }.max
  end
end
