class GamesController < ApplicationController
  CAPITAL_LAYOUT_HEIGHT = 600
  CAPITAL_LAYOUT_PADDING = 24
  CAPITAL_LAYOUT_CHARACTER_WIDTH = 8 # approx px per character at the major label's 14px font size
  CIV_COLOUR_SLOTS = 8 # data-viz reference categorical palette; hues live in application.css

  def index
    @games = Game.order(:id)
  end

  def show
    @game = Game.find(params[:id])
    @outcome = OutcomeResolver.new(@game).call
    @standings = MetricSeries.for(@game).final_ranking("score")
    @map_bounds = MapBounds.for(@game)
    @buffer_cities = BufferCities.for(@game).call
    @capital_layout_height = CAPITAL_LAYOUT_HEIGHT
    @capital_layout_width = capital_layout_width
    @capital_positions = map_layout[:capitals]
    @buffer_positions = map_layout[:buffers]
    @corridor_segments = map_layout[:corridors]
    @latest_analysis = @game.analyses.order(created_at: :desc).first
  end

  private

  # Canvas height is fixed; width follows the map's own aspect ratio so a
  # wide map isn't squeezed into a square. Maps are rarely square.
  def capital_layout_width
    width, height = @map_bounds.width, @map_bounds.height
    return CAPITAL_LAYOUT_HEIGHT unless width && height

    (CAPITAL_LAYOUT_HEIGHT * width / height.to_f).round
  end

  # Capitals, city-states and buffer cities on one canvas, plus a line down
  # each contested corridor. The three lists share a single projection so
  # relative distance holds across all of them. Built once.
  def map_layout
    @map_layout ||= build_map_layout
  end

  def build_map_layout
    anchors = layout_capitals
    return { capitals: [], buffers: [], corridors: [] } if anchors.empty?

    buffers = buffer_city_points
    project = plot_projector(anchors + buffers)

    {
      capitals: anchors.map { |anchor| place(anchor, project).merge(major: anchor[:major]) },
      buffers: buffers.map { |buffer| place(buffer, project).merge(city: buffer[:city]) },
      corridors: corridor_endpoints.map { |from, to| segment(from, to, project) }
    }
  end

  def place(point, project)
    cx, cy = project.call(point[:x], point[:y])
    { civ: point[:civ], colour_slot: colour_slot(point[:civ]), cx: cx, cy: cy }
  end

  def segment(from, to, project)
    x1, y1 = project.call(*from)
    x2, y2 = project.call(*to)
    { x1: x1, y1: y1, x2: x2, y2: y2 }
  end

  # One shared transform from map plots to canvas pixels: the same scale on
  # both axes so relative distance survives, the shorter axis centered
  # rather than stretched, and horizontal padding wide enough for half the
  # widest label so a centered label doesn't clip the canvas edge.
  def plot_projector(points)
    xs = points.map { |point| point[:x] }
    ys = points.map { |point| point[:y] }
    min_x, min_y = xs.min, ys.min
    padding_x = points.map { |point| label_half_width(point[:city] || point[:civ]) }.max
    drawable_width = @capital_layout_width - 2 * padding_x
    drawable_height = CAPITAL_LAYOUT_HEIGHT - 2 * CAPITAL_LAYOUT_PADDING
    x_span = [ xs.max - min_x, 1 ].max
    y_span = [ ys.max - min_y, 1 ].max
    scale = [ drawable_width / x_span.to_f, drawable_height / y_span.to_f ].min
    x_offset = padding_x + (drawable_width - x_span * scale) / 2
    y_offset = CAPITAL_LAYOUT_PADDING + (drawable_height - y_span * scale) / 2

    lambda do |x, y|
      [ (x_offset + (x - min_x) * scale).round(2),
        (CAPITAL_LAYOUT_HEIGHT - y_offset - (y - min_y) * scale).round(2) ]
    end
  end

  # The city-states are drawn too: they are the ground a player's expansion
  # had to go round. `major` is what tells the two apart on the canvas.
  def layout_capitals
    proximity = CapitalProximity.for(@game)

    proximity.capitals.values.map { |capital| capital.merge(major: true) } +
      proximity.city_state_capitals.values.map { |capital| capital.merge(major: false) }
  end

  # A civ's buffer cities as plots, deduped: one city can buffer two rivals
  # and appears once per pair in the digest.
  def buffer_city_points
    return [] unless @buffer_cities[:applicable]

    @buffer_cities[:pairs].flat_map do |pair|
      pair[:buffers].filter_map do |civ, buffer|
        { civ: civ, city: buffer[:city], x: buffer[:x], y: buffer[:y] } if buffer
      end
    end.uniq { |point| [ point[:civ], point[:x], point[:y] ] }
  end

  # Endpoints of the line down each contested corridor - the two capitals of
  # every neighbouring pair.
  def corridor_endpoints
    return [] unless @buffer_cities[:applicable]

    capitals = CapitalProximity.for(@game).capitals
    @buffer_cities[:pairs].filter_map do |pair|
      from, to = pair[:civs].map { |civ| capitals[civ] }
      [ [ from[:x], from[:y] ], [ to[:x], to[:y] ] ] if from && to
    end
  end

  # Which palette slot a civ draws from: its seat order, capped at the
  # palette size so an unusually large game falls back to the neutral fill
  # rather than cycling hues. `nil` for city-states.
  def colour_slot(civ)
    seat = major_civs.index(civ)
    seat if seat && seat < CIV_COLOUR_SLOTS
  end

  def major_civs
    @major_civs ||= @game.players.order(:id).map(&:civ)
  end

  def label_half_width(label)
    CAPITAL_LAYOUT_PADDING + label.length * CAPITAL_LAYOUT_CHARACTER_WIDTH / 2.0
  end
end
