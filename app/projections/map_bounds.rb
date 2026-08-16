# Distances only wrap correctly when the map's width is known. Newer logs
# report it; for older ones the easternmost plot anyone ever touched is the
# best available lower bound.
class MapBounds
  def initialize(game)
    @game = game
  end

  def width
    @game.map_width || easternmost_plot&.succ
  end

  def estimated?
    @game.map_width.nil?
  end

  private

  def easternmost_plot
    @game.game_events.filter_map { |event| event.payload["x"] }.max
  end
end
