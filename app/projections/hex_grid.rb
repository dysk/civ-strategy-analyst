# Civ5 measures distance on a staggered hex grid, not a square one, and its
# maps wrap in X. This reimplements the game's own plotDistance so city
# distances match what a player sees on the map.
class HexGrid
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

  private

  # Each row sits half a hex right of the one below it; undoing that stagger
  # turns the offset coordinates into axial ones the arithmetic above expects.
  def hexspace_x(plot)
    x, y = plot
    x - (y / 2)
  end

  def wrapped(dx)
    dx -= @width while dx > @width / 2
    dx += @width while dx < -@width / 2
    dx
  end
end
