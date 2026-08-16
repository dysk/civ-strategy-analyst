# Which original major capitals a civ currently holds. Own capital is
# included by default, so a fresh empire already reports one.
class CapitalsTimeline
  def initialize(game)
    @snapshots = game.game_events.where(event_type: "snapshot").where.not(civ: nil).order(:seq).to_a
  end

  def latest(civ)
    series(civ).last
  end

  # A turn can be snapshotted more than once - a resumed session repeats
  # it - and the later snapshot is the state the turn ended in.
  def series(civ)
    snapshots_for(civ).filter_map { |e| entry(e) }.index_by { |entry| entry[:turn] }.values
  end

  def capitals_held(civ)
    series(civ).map { |entry| [ entry[:turn], entry[:capitals_held] ] }
  end

  private

  def snapshots_for(civ)
    @snapshots.select { |e| e.civ == civ }
  end

  def entry(snapshot)
    capitals = snapshot.payload["capitals"]
    return unless capitals

    { turn: snapshot.turn, capitals: capitals, capitals_held: capitals.size }
  end
end
