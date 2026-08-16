# What an army is made of, not how strong it is. Power divided by unit
# count tells a horde of obsolete units from a small modern force, which
# the total cannot.
#
# The game's own military might is not that total: CvPlayer.cpp inflates
# the summed unit power by the treasury, up to double, so a civilization
# sitting on gold reads as fielding better units than it does. Dividing
# the multiplier back out leaves the units alone.
class ArmyComposition
  GOLD_MULTIPLIER_CAP = 2.0

  def self.gold_multiplier(gold)
    [ 1 + Math.sqrt([ gold, 0 ].max) / 100, GOLD_MULTIPLIER_CAP ].min
  end

  def self.army_power(might, gold)
    return unless might && gold

    (might / gold_multiplier(gold)).round
  end

  def self.power_per_unit(might, units, gold)
    power = army_power(might, gold)
    return unless power && units&.positive?

    (power.to_f / units).round(1)
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
    @snapshots.select { |e| e.civ == civ }.filter_map { |e| entry(e) }.index_by { |entry| entry[:turn] }.values
  end

  private

  def entry(snapshot)
    might, units, gold = snapshot.payload.values_at("military_might", "military_units", "gold")
    return unless might || units

    { turn: snapshot.turn, units: units, might: might,
      army_power: self.class.army_power(might, gold),
      power_per_unit: self.class.power_per_unit(might, units, gold) }
  end
end
