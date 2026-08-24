# Which original major capitals a civ currently holds. Own capital is
# included by default, so a fresh empire already reports one.
class CapitalsTimeline
  def initialize(game)
    @snapshots_by_civ = game.event_log.by("snapshot", :civ)
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

  def snapshots_for(civ) = @snapshots_by_civ.fetch(civ, [])

  def entry(snapshot)
    capitals = snapshot.payload["capitals"]
    return unless capitals

    # The Lua logger serializes an empty table as {} rather than [], so a
    # civ holding no capitals reports "capitals":{} instead of "capitals":[].
    capitals = [] if capitals.is_a?(Hash)

    { turn: snapshot.turn, capitals: capitals, capitals_held: capitals.size }
  end
end
