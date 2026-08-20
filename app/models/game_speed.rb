class GameSpeed
  FACTORS = { "QUICK" => Rational(2, 3) }.freeze
  STANDARD_FACTOR = 1

  def self.for(game) = new(game.game_speed)

  def initialize(raw)
    @raw = raw.to_s.upcase
  end

  def turns(standard_turns)
    (standard_turns * factor).round
  end

  private

  def factor
    FACTORS.find { |name, _| @raw.include?(name) }&.last || STANDARD_FACTOR
  end
end
