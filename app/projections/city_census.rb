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
  def sizes(civ, turn)
    rows = snapshots_by_civ.fetch(civ, [])
    census_turn = rows.map(&:turn).select { |t| t <= turn }.max
    return [] unless census_turn

    rows.select { |e| e.turn == census_turn }
      .index_by { |e| e.payload["city"] }.values
      .map { |e| e.payload["population"].to_i }
      .sort.reverse
  end

  private

  def snapshots_by_civ = @snapshots_by_civ ||= snapshots.group_by(&:civ)

  def snapshots = @log.of_type("city_snapshot")
end
