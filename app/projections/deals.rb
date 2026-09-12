# CvDeal is unreachable from Lua, so no event names a deal directly. What
# can: `snapshot.resources[]` gives each civ's own import/export per
# resource per turn, and the only signal available is co-occurrence - one
# civ exporting a resource the same turn another civ imports it.
# docs/reading-the-new-log.md §11.
#
# The doc's own rule reads "a luxury appearing in one import and another's
# export is a deal", but re-measured against three real logs a quarter of
# matched flows are strategic resources, not luxuries - the restriction is
# dropped here. It also doesn't anticipate one exporter serving several
# importers of the same resource at once (Netherlands fed both Zimbabwe and
# Tibet Horse simultaneously in india-diplo): the split can't be recovered
# from a stock's total, so `matches` reports nothing for a turn where more
# than one civ exports or imports the same resource, rather than guess a
# pairing.
class Deals
  extend Projection

  def initialize(game)
    @log = game.event_log
  end

  def applicable? = snapshots.any? { |e| e.payload["resources"].present? }

  # Confirmed major-to-major swaps, collapsed into spans of consecutive
  # turns the same (resource, exporter, importer) pairing held.
  def matches
    flows_by_turn.flat_map { |turn, flows| matched_pairs(turn, flows) }
      .group_by { |m| m.values_at(:resource, :exporter, :importer) }
      .flat_map { |_, ms| collapse(ms.sort_by { |m| m[:turn] }) }
      .sort_by { |m| m[:from_turn] }
  end

  # Imports with no major exporting the same resource the same turn - a
  # city-state ally's gift, most likely, but see the doc: a deal's first
  # turn can look identical when the partner's own snapshot lags by one.
  def unattributed_imports
    flows_by_turn.flat_map { |turn, flows| unattributed(turn, flows) }
  end

  private

  def matched_pairs(turn, flows)
    flows.group_by { |f| f[:resource] }.flat_map do |resource, rows|
      exporters = rows.select { |r| r[:export].positive? }
      importers = rows.select { |r| r[:import].positive? }
      next [] unless exporters.size == 1 && importers.size == 1

      [ { turn: turn, resource: resource, exporter: exporters.first[:civ], importer: importers.first[:civ] } ]
    end
  end

  def unattributed(turn, flows)
    flows.group_by { |f| f[:resource] }.flat_map do |resource, rows|
      next [] if rows.any? { |r| r[:export].positive? }

      rows.select { |r| r[:import].positive? }
        .map { |r| { civ: r[:civ], resource: resource, turn: turn, amount: r[:import] } }
    end
  end

  def collapse(matches)
    matches.chunk_while { |a, b| b[:turn] == a[:turn] + 1 }.map do |run|
      { resource: run.first[:resource], exporter: run.first[:exporter], importer: run.first[:importer],
        from_turn: run.first[:turn], to_turn: run.last[:turn] }
    end
  end

  def flows_by_turn
    @flows_by_turn ||= snapshots.flat_map { |s| resource_flows(s) }.group_by { |f| f[:turn] }
  end

  def resource_flows(snapshot)
    Array(snapshot.payload["resources"]).filter_map do |row|
      import, export = row.values_at("import", "export").map(&:to_i)
      next if import.zero? && export.zero?

      { civ: snapshot.civ, turn: snapshot.turn, resource: row["resource"], import: import, export: export }
    end
  end

  # A reload can log a turn twice; the later payload is the state the turn
  # actually ended in - the same rule ResourceShortages applies.
  def snapshots = @log.of_type("snapshot").group_by(&:civ).flat_map { |_, evs| evs.index_by(&:turn).values }
end
