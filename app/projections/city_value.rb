# What a city was worth to the empire that owned it: its share of that
# empire's population, buildings and yields at a given turn, and its rank
# among its owner's cities by each.
#
# Shares are taken over the owner's own `city_snapshot` rows, never over
# the empire-wide `snapshot` yields, which fold in sources that are not
# cities. Two of the three example logs carry no `city_snapshot`, so a
# reader must check `applicable?` before trusting `at`.
class CityValue
  extend Projection

  METRICS = {
    population: "population", buildings: "buildings", science: "yield_science",
    production: "yield_production", gold: "yield_gold", culture: "yield_culture",
    faith: "yield_faith"
  }.freeze

  def initialize(game)
    @log = game.event_log
  end

  def applicable? = snapshots.any?

  # The city's share and rank across every measured yield at the last
  # snapshot on or before `turn`, or nil when the city was not snapshotted
  # by then. A reload can snapshot one turn twice; the later payload wins,
  # as CityCensus resolves the same case.
  def at(city, turn)
    own = latest_row(city, turn)
    return unless own

    peers = deduped(rows_for(own.civ).select { |e| e.turn == own.turn })

    { city: city, civ: own.civ, turn: own.turn }
      .merge(METRICS.flat_map { |name, field| share_and_rank(name, field, own, peers) }.to_h)
  end

  # `at`, run over every turn `city` was itself snapshotted, in turn order -
  # the full history a single lookup only samples one point of.
  def series(city)
    rows_by_city.fetch(city, []).map(&:turn).uniq.sort.filter_map { |turn| at(city, turn) }
  end

  private

  # The last snapshot of `city` on or before `turn`; among ties on the
  # census turn the later payload wins, the log being in seq order.
  def latest_row(city, turn)
    rows = rows_by_city.fetch(city, []).select { |e| e.turn <= turn }
    census_turn = rows.map(&:turn).max
    return unless census_turn

    rows.select { |e| e.turn == census_turn }.last
  end

  def share_and_rank(name, field, own, peers)
    values = peers.map { |e| e.payload[field].to_f }
    total = values.sum
    mine = own.payload[field].to_f
    return [ [ :"#{name}_share", nil ], [ :"#{name}_rank", nil ] ] if total.zero?

    [ [ :"#{name}_share", (mine / total).round(3) ],
      [ :"#{name}_rank", values.count { |v| v > mine } + 1 ] ]
  end

  # One row per city; a turn logged twice keeps the later payload.
  def deduped(rows) = rows.index_by { |e| e.payload["city"] }.values

  def rows_for(civ) = rows_by_civ.fetch(civ, [])

  def rows_by_civ = @rows_by_civ ||= snapshots.group_by(&:civ)

  def rows_by_city = @rows_by_city ||= snapshots.group_by { |e| e.payload["city"] }

  def snapshots = @log.of_type("city_snapshot")
end
