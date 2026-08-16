# What an army is made of, not how strong it is. Might divided by unit
# count tells a horde of obsolete units from a small modern force, which
# the total might alone cannot.
class ArmyComposition
  def self.might_per_unit(might, units)
    return unless might && units&.positive?

    (might.to_f / units).round(1)
  end

  def initialize(game)
    @snapshots = game.game_events.where(event_type: "snapshot").where.not(civ: nil).order(:seq).to_a
  end

  def latest(civ)
    series(civ).last
  end

  def series(civ)
    @snapshots.select { |e| e.civ == civ }.filter_map { |e| entry(e) }
  end

  private

  def entry(snapshot)
    might = snapshot.payload["military_might"]
    units = snapshot.payload["military_units"]
    return unless might || units

    { turn: snapshot.turn, units: units, might: might,
      might_per_unit: self.class.might_per_unit(might, units) }
  end
end
