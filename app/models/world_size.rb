# The map size's pace, from the mod's Worlds table. A larger map makes every
# tech dearer and each city beyond the capital cheaper. Duel, tiny and small
# share the base row, which is also the fallback for an unknown size.
class WorldSize
  Pace = Data.define(:research_factor, :tech_cost_per_city, :policy_cost_per_city)

  BASE = Pace.new(1, 0.05, 0.10)

  PACES = {
    "STANDARD" => Pace.new(Rational(11, 10), 0.05, 0.10),
    "LARGE" => Pace.new(Rational(6, 5), 0.0375, 0.075),
    "HUGE" => Pace.new(Rational(13, 10), 0.025, 0.05)
  }.freeze

  delegate :tech_cost_per_city, :policy_cost_per_city, to: :@pace

  def self.for(game) = new(game.map_size)

  def initialize(raw)
    @pace = PACES.find { |name, _| raw.to_s.upcase.include?(name) }&.last || BASE
  end

  def research_turns(turns)
    (turns * @pace.research_factor).round
  end
end
