# How many people stand behind an empire's population points.
#
# A chronicle cannot quote population points, and multiplying them by a
# thousand makes a modern nation the size of a town. The series has always
# curved them instead: a citizen is a thousand souls, and every citizen after
# it counts for more, so a city of twelve holds a million people.
#
# Per-city sizes are not carried in the snapshots, so the empire's citizens
# are spread evenly over its cities before the curve is applied.
class Demographics
  SOULS_PER_CITIZEN = 1_000
  GROWTH_EXPONENT = 2.8
  ROUNDED_TO = 1_000

  def initialize(population:, cities:)
    @population = population.to_i
    @cities = cities.to_i
  end

  def souls
    return 0 if @cities.zero?

    (@cities * SOULS_PER_CITIZEN * average_city_size**GROWTH_EXPONENT).round(-Math.log10(ROUNDED_TO).to_i)
  end

  private

  def average_city_size = @population.to_f / @cities
end
