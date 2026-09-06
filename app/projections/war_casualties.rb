# What a war cost each side: the units that died fighting, and the ones
# that were led away alive.
#
# unit_lost is "left the map", not "died" - a caravan founding a trade
# route, a settler founding a city and a spent missionary all raise it,
# and in a trading empire those outnumber the war dead. Two records say
# more than that. unit_killed is the game's own combat-death record, and
# it names the civilization that did the killing - never the unit that
# did it, only the one that fell, so a side is described by what it
# destroyed, not by what it destroyed it with. And unit_lost carries a
# killer of its own wherever the game knew one at removal, which is what
# a civilian changing hands looks like: no combat death is recorded, and
# the new owner is named on the loss.
class WarCasualties
  extend Projection

  # Units that cannot fight, taken from LEKMOD's own unit table
  # (LEKMOD/Override/CIV5Units.xml, rows with Combat = 0 and
  # RangedCombat = 0) rather than listed from memory - half of these are
  # civilization uniques whose names give nothing away. The nuclear
  # missile shares those two zeroes and is no civilian, so it is the one
  # row dropped from that query.
  CIVILIAN_UNITS = %w[
    UNIT_ARCHAEOLOGIST UNIT_ARTIST UNIT_AUSTRALIA_WORKER UNIT_BURMA_SETTLER
    UNIT_CARAVAN UNIT_CARGO_SHIP UNIT_DALAILAMA UNIT_ENGINEER UNIT_FAKEPROPHET
    UNIT_FAST_WORKER UNIT_GREAT_ADMIRAL UNIT_GREAT_GENERAL UNIT_INQUISITOR
    UNIT_ITALARTIST UNIT_LEU_COMPARSA_FOLKLORICA UNIT_MABA UNIT_MAURYA_MISSIONARY
    UNIT_MERCHANT UNIT_MISSIONARY UNIT_MONGOLIAN_KHAN UNIT_MUSICIAN UNIT_PROPHET
    UNIT_RANCHERO UNIT_SCIENTIST UNIT_SETTLER UNIT_SS_BOOSTER UNIT_SS_COCKPIT
    UNIT_SS_ENGINE UNIT_SS_STASIS_CHAMBER UNIT_VENETIAN_MERCHANT UNIT_VENEZ_CARAVAN
    UNIT_VENEZ_CARGO_SHIP UNIT_WORKBOAT UNIT_WORKER UNIT_WRITER
  ].freeze

  # UNITCLASS_SCOUT, from the same table. They carry a weapon and count as
  # soldiers everywhere else, but one dying far from home is a wanderer
  # caught, not a war being fought, so a war that opens on one opens on
  # nothing.
  SCOUT_UNITS = %w[UNIT_SCOUT UNIT_SHOSHONE_PATHFINDER UNIT_NUBIAN_BOW UNIT_MC_ZABONAH].freeze

  def initialize(game)
    @casualties = casualties(game.event_log)
  end

  def during(war)
    exchanged = exchanged_in(war)

    (war[:attacker_civs] + war[:defender_civs]).index_with { |civ| tally(exchanged, civ) }
  end

  # What a war opened with, which is as close as the log comes to saying
  # what it was about.
  def first_blood(war)
    opening = exchanged_in(war).first
    return unless opening

    opening.slice(:turn, :civ, :unit, :by, :fate).merge(kind: kind_of(opening[:unit]))
  end

  # A declaration nobody acted on, a raid for a worker and a war of
  # conquest all arrive as the same event, and only what they cost tells
  # them apart. A scout counts on the raid's side of that line: it carries
  # a weapon, but one ridden down far from home stands for no campaign.
  def scale(war)
    exchanged = exchanged_in(war)
    return :bloodless if exchanged.empty?

    exchanged.any? { |casualty| kind_of(casualty[:unit]) == :soldier } ? :war : :raid
  end

  private

  def casualties(log)
    deaths = log.of_type("unit_killed").map { |event| death(event) }

    # By turn, and only then by the order the log kept: an escort cut down
    # and the settler it guarded taken fall on the same turn, and which of
    # them opened the war is what the log says it was.
    (deaths + unrecorded(log, tally_of(deaths))).sort_by { |casualty| casualty.values_at(:turn, :seq) }
  end

  def death(event)
    killer, victim, unit = event.payload.values_at("killer", "victim", "unit")

    { seq: event.seq, turn: event.turn, civ: victim, unit: unit, by: killer, fate: :killed }
  end

  # A unit that can fight cannot be taken, so the same record on a soldier
  # is a death the combat log missed rather than a capture.
  def named_losses(log)
    log.of_type("unit_lost").filter_map do |event|
      unit, taker = event.payload.values_at("unit", "killed_by")
      next unless taker

      { seq: event.seq, turn: event.turn, civ: event.civ, unit: unit, by: taker,
        fate: CIVILIAN_UNITS.include?(unit) ? :captured : :killed }
    end
  end

  # Both records fire for some deaths, so a loss the combat log already
  # holds is dropped - matched one for one, so a civilization that lost
  # two of a kind in one turn does not lose them twice over.
  def unrecorded(log, recorded)
    named_losses(log).reject do |loss|
      next false unless recorded[key(loss)].positive?

      recorded[key(loss)] -= 1
      true
    end
  end

  def tally_of(deaths)
    deaths.each_with_object(Hash.new(0)) { |death, seen| seen[key(death)] += 1 }
  end

  def key(casualty) = casualty.values_at(:turn, :civ, :unit)

  # Barbarians and the neighbours' wars run through the same turns, so a
  # casualty counts only when it crossed this war's front.
  def exchanged_in(war)
    @casualties.select { |casualty| within?(casualty[:turn], war) && across_the_front?(casualty, war) }
  end

  def within?(turn, war)
    turn >= war[:turn] && (war[:turn_peace].nil? || turn <= war[:turn_peace])
  end

  def across_the_front?(casualty, war)
    sides(war).any? { |side, opposition| side.include?(casualty[:by]) && opposition.include?(casualty[:civ]) }
  end

  def sides(war)
    [ [ war[:attacker_civs], war[:defender_civs] ], [ war[:defender_civs], war[:attacker_civs] ] ]
  end

  def tally(exchanged, civ)
    dead, taken = exchanged.select { |c| c[:civ] == civ }.partition { |c| c[:fate] == :killed }
    slain, seized = exchanged.select { |c| c[:by] == civ }.partition { |c| c[:fate] == :killed }

    { losses: dead.size, loss_types: by_type(dead),
      kills: slain.size, kill_types: by_type(slain),
      captured: taken.size, captured_types: by_type(taken),
      seized: seized.size, seized_types: by_type(seized) }
  end

  # Heaviest toll first: a chronicle names the unit that decided the war,
  # not the one that happened to die first.
  def by_type(casualties)
    casualties.each_with_object(Hash.new(0)) { |casualty, counts| counts[casualty[:unit]] += 1 }
              .sort_by { |_type, count| -count }.to_h
  end

  def kind_of(unit) = self.class.kind_of(unit)

  def self.kind_of(unit)
    return :civilian if CIVILIAN_UNITS.include?(unit)
    return :scout if SCOUT_UNITS.include?(unit)

    :soldier
  end
end
