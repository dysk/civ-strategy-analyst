# What builds a civ's science, culture, faith and tourism each turn -
# `snapshot.yield_sources` splits each into named parts (cities, city
# alliances, happiness, religion, a science deficit), and this is the
# first thing that reads it.
#
# The parts don't always sum to the reported total - a golden age's flat
# culture bonus and similar flat modifiers aren't attributed to any
# source - so every point here carries the gap alongside the parts rather
# than hiding it in a normalised percentage. Two of the five example logs
# carry no `yield_sources` at all; check `applicable?` before trusting
# `series`.
class YieldAttribution
  extend Projection

  def initialize(game)
    @snapshots_by_civ = game.event_log.by("snapshot", :civ)
  end

  def applicable? = snapshots.any? { |e| (e.payload["yield_sources"] || {}).values.any?(&:present?) }

  # The yield names this civ has source data for at all, e.g.
  # %w[science culture].
  def yields(civ)
    snapshots_for(civ).flat_map { |e| (e.payload["yield_sources"] || {}).select { |_, v| v.present? }.keys }.uniq
  end

  # turn/total/sources/shortfall for one yield over time. `shortfall` is
  # the reported total minus the sum of the named parts - positive when
  # something is contributing that carries no source label.
  def series(civ, yield_name)
    snapshots_for(civ).filter_map { |e| entry(e, yield_name) }.index_by { |point| point[:turn] }.values
  end

  private

  def snapshots = @snapshots_by_civ.values.flatten

  def snapshots_for(civ) = @snapshots_by_civ.fetch(civ, [])

  def entry(snapshot, yield_name)
    sources = snapshot.payload.dig("yield_sources", yield_name.to_s)
    return unless sources.present?

    total = snapshot.payload[yield_name.to_s]
    { turn: snapshot.turn, total: total, sources: sources.symbolize_keys,
      shortfall: (total - sources.values.sum).round(2) }
  end
end
