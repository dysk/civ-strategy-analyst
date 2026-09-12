# Every city's size, civ by civ, turn by turn.
#
# `snapshot` carries an empire-wide population and a city count; `Demographics`
# had to spread the one evenly over the other. `city_snapshot` carries the real
# per-city figure, so the curve can be applied city by city instead of to an
# average that understates it.
#
# Two of the three example logs carry no `city_snapshot` at all, so a reader
# must check `applicable?` before trusting `sizes`.
class CityCensus
  extend Projection

  def initialize(game)
    @log = game.event_log
  end

  def applicable? = snapshots.any?

  # The populations of a civ's cities at the last snapshot on or before `turn`,
  # largest first. A reload can snapshot one turn twice, so a city is taken once
  # per turn - the later payload wins, as CongressTimeline resolves the same case.
  def sizes(civ, turn) = snapshot(civ, turn).map { |city| city[:population] }

  # `sizes` without the city's name discarded - `{city, population}`, largest
  # first, at the same last-snapshot-on-or-before-`turn` rule.
  def snapshot(civ, turn)
    rows = snapshots_by_civ.fetch(civ, [])
    census_turn = rows.map(&:turn).select { |t| t <= turn }.max
    return [] unless census_turn

    rows.select { |e| e.turn == census_turn }
      .index_by { |e| e.payload["city"] }.values
      .map { |e| { city: e.payload["city"], population: e.payload["population"].to_i } }
      .sort_by { |city| -city[:population] }
  end

  # Every city the log has ever snapshotted, each at its own last snapshot
  # on or before `turn` - unlike `snapshot`, which fixes one census turn per
  # civ and so still lists a city under an owner who lost it turns ago, this
  # asks each city for its own last owner. `civ` is whoever that snapshot
  # names, so a capture surfaces the city under its new owner from the turn
  # of capture on. Largest population first.
  def cities(turn)
    snapshots.group_by { |e| e.payload["city"] }.filter_map do |city, rows|
      census_turn = rows.map(&:turn).select { |t| t <= turn }.max
      next unless census_turn

      row = rows.select { |e| e.turn == census_turn }.last
      { city: city, civ: row.civ, population: row.payload["population"].to_i }
    end.sort_by { |c| -c[:population] }
  end

  private

  def snapshots_by_civ = @snapshots_by_civ ||= snapshots.group_by(&:civ)

  def snapshots = @log.of_type("city_snapshot")
end
