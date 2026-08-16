# Spaceship assembly progress. A part being built (unit_trained) is not
# the same as a part being assembled - no event fires on assembly, only
# the snapshot's spaceship field. A complete ship needs 6 physical parts
# (3 booster + 1 cockpit + 1 stasis chamber + 1 engine, confirmed via the
# mod's Project_VictoryThresholds/MaxTeamInstances); apollo is a
# prerequisite unlock, not a counted part, and is excluded from the total.
class SpaceshipTimeline
  PARTS_REQUIRED = { "booster" => 3, "cockpit" => 1, "stasis_chamber" => 1, "engine" => 1 }.freeze
  PARTS = PARTS_REQUIRED.keys.freeze
  TOTAL_PARTS_REQUIRED = PARTS_REQUIRED.values.sum

  def self.complete?(spaceship)
    return false unless spaceship

    PARTS_REQUIRED.all? { |part, required| spaceship[part].to_i >= required }
  end

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

  private

  def snapshots_for(civ)
    @snapshots.select { |e| e.civ == civ }
  end

  def entry(snapshot)
    spaceship = snapshot.payload["spaceship"]
    return unless spaceship

    { turn: snapshot.turn, spaceship: spaceship, parts_assembled: PARTS.sum { |part| spaceship[part].to_i } }
  end
end
