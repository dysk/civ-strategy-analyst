# Civ5 measures distance on a staggered hex grid, not a square one, and its
# maps wrap in X. This reimplements the game's own plotDistance so city
# distances match what a player sees on the map.
class HexGrid
  # An eight-wind compass drops the shorter axis once the longer one is
  # more than 22.5 degrees away from it.
  DIAGONAL_RATIO = Math.tan(Math::PI / 8)

  def initialize(width:)
    @width = width
  end

  def distance(from, to)
    dx = wrapped(hexspace_x(to) - hexspace_x(from))
    dy = to.last - from.last

    if (dx >= 0) == (dy >= 0)
      dx.abs + dy.abs
    else
      [ dx.abs, dy.abs ].max
    end
  end

  # How far `point` lies off the line through `from` and `to`, in hexes.
  # `distance` says a city is near a capital; this says whether it stands on
  # the road between two of them or off to one side. Measured in hexspace so
  # it reads in the same metric as `distance`, not off a straight ruler: a
  # diagonal pair's shortest paths fan into a rhombus, so a city well off the
  # geometric line can still sit only a hex or two off the route.
  def offset_from_line(from, to, point)
    along_x = wrapped(hexspace_x(to) - hexspace_x(from))
    along_y = to.last - from.last
    span = Math.hypot(along_x, along_y)
    return 0.0 if span.zero?

    across_x = wrapped(hexspace_x(point) - hexspace_x(from))
    across_y = point.last - from.last
    (along_x * across_y - along_y * across_x).abs / span
  end

  # Which way `to` lies from `from`, as a compass point - "N", "SW" and so
  # on - in the game's own frame: y counts north from the south edge and x
  # counts east. Rows and columns are close enough to the same size that a
  # reading needs no correction for the stagger.
  def bearing(from, to)
    dx = wrapped(to.first - from.first)
    dy = to.last - from.last

    [ pole(dy, dx), side(dx, dy) ].compact.join.presence
  end

  private

  def pole(dy, dx)
    return if dy.zero? || dy.abs < DIAGONAL_RATIO * dx.abs

    dy.positive? ? "N" : "S"
  end

  def side(dx, dy)
    return if dx.zero? || dx.abs < DIAGONAL_RATIO * dy.abs

    dx.positive? ? "E" : "W"
  end

  # Each row sits half a hex right of the one below it; undoing that stagger
  # turns the offset coordinates into axial ones the arithmetic above expects.
  def hexspace_x(plot)
    x, y = plot
    x - (y / 2)
  end

  # Without a known width there is no seam to cross, so the only honest
  # reading is the distance the long way round.
  def wrapped(dx)
    return dx unless @width

    dx -= @width while dx > @width / 2
    dx += @width while dx < -@width / 2
    dx
  end
end
