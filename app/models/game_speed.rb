class GameSpeed
  FACTORS = { "QUICK" => Rational(2, 3) }.freeze

  # A golden age keeps a pace of its own. The mod's GameSpeeds table carries
  # a GoldenAgePercent apart from the general turn percentage, and on quick
  # speed the two disagree - turns run at 67%, a golden age at 80%.
  GOLDEN_AGE_FACTORS = {
    "MARATHON" => 2,
    "EPIC" => Rational(5, 4),
    "QUICK" => Rational(4, 5),
    "ONLINE" => Rational(1, 2)
  }.freeze

  STANDARD_FACTOR = 1

  def self.for(game) = new(game.game_speed)

  def initialize(raw)
    @raw = raw.to_s.upcase
  end

  def turns(standard_turns)
    scale(standard_turns, FACTORS)
  end

  def golden_age_turns(standard_turns)
    scale(standard_turns, GOLDEN_AGE_FACTORS)
  end

  private

  def scale(standard_turns, factors)
    (standard_turns * factor_in(factors)).round
  end

  def factor_in(factors)
    factors.find { |name, _| @raw.include?(name) }&.last || STANDARD_FACTOR
  end
end
