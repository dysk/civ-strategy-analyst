# A strategic resource run below what a civilization's units are using -
# every unit already built that needs it fights weaker, per LEKMOD's own
# combat rule. docs/plan.md "strategic resource shortages" records the
# rule, verified against LEKMOD_DLL/CvGameCoreDLL_Expansion2/CvUnit.cpp:12631.
#
# This is a computed mechanical fact, never an observed one: no event logs a
# unit's actual combat strength, so nothing here confirms a fight was lost
# to it. A reader must say "exposed to a penalty", never "fought weaker" or
# "lost because of this".
class ResourceShortages
  extend Projection

  PENALTY_FLOOR = -50

  def initialize(game, requirements: ResourceRequirements.for(game.lekmod_version))
    @log = game.event_log
    @order_of_battle = OrderOfBattle.for(game)
    @requirements = requirements
  end

  # False for the two example logs that predate the resources[] field.
  def applicable? = @log.of_type("snapshot").any? { |e| e.payload["resources"].present? }

  # Every (turn, resource) this civ ran a strategic deficit on, oldest first.
  def deficits(civ)
    snapshots_for(civ).flat_map { |snapshot| deficits_at(civ, snapshot) }.sort_by { |d| d[:turn] }
  end

  private

  def deficits_at(civ, snapshot)
    Array(snapshot.payload["resources"]).filter_map { |row| deficit(civ, snapshot.turn, row) }
  end

  def deficit(civ, turn, row)
    resource, total, used = row.values_at("resource", "total", "used")
    return unless total && used && total < used && @requirements.strategic?(resource)

    fraction = ((used - total).to_f / used).round(3)
    { turn: turn, resource: resource, total: total, used: used,
      deficit_fraction: fraction, penalty: penalty(fraction),
      exposed_units: exposed_units(civ, turn, resource) }
  end

  def penalty(fraction) = [ (fraction * PENALTY_FLOOR).floor, PENALTY_FLOOR ].max

  def exposed_units(civ, turn, resource)
    @order_of_battle.at(turn, civ).keys.select { |unit| @requirements.requires?(unit, resource) }
  end

  # A reload can log a turn twice; the later payload is the state the turn
  # actually ended in - the same rule WonderRaces applies to city snapshots.
  def snapshots_for(civ) = @log.by("snapshot", :civ).fetch(civ, []).index_by(&:turn).values
end
