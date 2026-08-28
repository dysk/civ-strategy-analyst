# The in-game year a turn falls on. Civ 5 dates a turn differently on every
# game speed, so the table is read through the column the game was played on.
class TurnCalendar
  PATH = Rails.root.join("db/civ5_turn_years.csv")
  YEAR_COLUMNS = { "QUICK" => 0, "STANDARD" => 2, "EPIC" => 4 }.freeze
  DEFAULT_SPEED = "STANDARD"

  def self.for(game) = game.projection(self) { new(game.game_speed) }

  def initialize(game_speed, path: PATH)
    @game_speed = game_speed.to_s.upcase
    @path = path
  end

  def year_for(turn)
    years.fetch(turn) { years[last_turn] }
  end

  def series(max_turn)
    (0..max_turn).index_with { |turn| year_for(turn) }
  end

  private

  def last_turn = years.keys.max

  def years
    @years ||= File.readlines(@path).drop(1).to_h do |line|
      row = line.split(",")
      [ Integer(row[year_column + 1]), row[year_column].strip ]
    end
  end

  # A speed the table does not cover - marathon - is still dated, on the
  # closest column there is, rather than left without a calendar.
  def year_column
    YEAR_COLUMNS.find { |speed, _| @game_speed.include?(speed) }&.last || YEAR_COLUMNS.fetch(DEFAULT_SPEED)
  end
end
