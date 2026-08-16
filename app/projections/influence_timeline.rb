# Cultural standing between a pair of civs: LEKMOD builds tourism output
# somewhat differently than BNW, but we log the resulting influence, not
# its sources, so the projection only needs the payload's influence list.
class InfluenceTimeline
  def initialize(game)
    @snapshots = game.game_events.where(event_type: "snapshot").where.not(civ: nil).order(:seq).to_a
  end

  def opponents(civ)
    snapshots_for(civ).flat_map { |e| Array(e.payload["influence"]).map { |i| i["civ"] } }.uniq
  end

  # A turn can be snapshotted more than once - a resumed session repeats
  # it - and the later snapshot is the state the turn ended in.
  def series(civ, opponent)
    snapshots_for(civ).filter_map { |e| entry(e, opponent) }.index_by { |point| point[:turn] }.values
  end

  def level_changes(civ, opponent)
    previous = nil

    series(civ, opponent).each_with_object([]) do |point, changes|
      changes << { turn: point[:turn], from: previous, to: point[:level] } if previous && point[:level] != previous
      previous = point[:level]
    end
  end

  def latest_points_delta(civ, opponent)
    points = series(civ, opponent).last(2).map { |point| point[:points] }
    return nil unless points.size == 2

    points.last - points.first
  end

  private

  def snapshots_for(civ)
    @snapshots.select { |e| e.civ == civ }
  end

  def entry(snapshot, opponent)
    influence = Array(snapshot.payload["influence"]).find { |i| i["civ"] == opponent }
    return unless influence

    { turn: snapshot.turn, points: influence["points"], level: influence["level"], trend: influence["trend"] }
  end
end
