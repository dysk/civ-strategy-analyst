# How many people stand behind an empire's population points.
#
# A chronicle cannot quote population points, and multiplying them by a
# thousand makes a modern nation the size of a town. The series curves them
# instead: a citizen is a thousand souls, and every citizen after it counts
# for more, so a city of twelve holds a million people.
#
# Two ways in. `city_sizes:` applies the curve to each real city size and is
# what `city_snapshot` now affords; `population:`/`cities:` spreads the
# empire's citizens evenly first and is the fallback for logs without city
# snapshots. `source` says which one ran, because the curve is convex and the
# averaged figure understates a lopsided empire.
class Demographics
  SOULS_PER_CITIZEN = 1_000
  GROWTH_EXPONENT = 2.8
  ROUNDED_TO = 1_000

  def initialize(population: nil, cities: nil, city_sizes: nil)
    @city_sizes = city_sizes&.map(&:to_i)
    @population = population.to_i
    @cities = cities.to_i
  end

  def source = @city_sizes ? :cities : :average

  def souls = round(city_sizes.sum { |size| souls_for(size) })

  # The souls of each city on its own, largest first - only meaningful on the
  # per-city path, where `city_sizes` are the real sizes rather than an average.
  def per_city = city_sizes.map { |size| round(souls_for(size)) }

  private

  def city_sizes
    @city_sizes || Array.new(@cities, average_city_size)
  end

  def souls_for(size) = SOULS_PER_CITIZEN * size**GROWTH_EXPONENT

  def average_city_size
    return 0 if @cities.zero?

    @population.to_f / @cities
  end

  def round(value) = value.round(-Math.log10(ROUNDED_TO).to_i)
end
