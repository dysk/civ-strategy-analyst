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

  # The causes that leave a casualty, on a log that names causes at all.
  # The ones left out - a great person spent, a settler founding a city, a
  # caravan that finished its route - are removals, never deaths.
  CASUALTY_CAUSES = %i[killed city_captured].freeze

  BARBARIANS = "Barbarians"

  # The combat record is not written from every civilization's point of
  # view. unit_killed names Babylon as a victim 3 times across
  # babylon-domination and as a killer 59 times, because the hook fires on
  # the host's own machine, so all 55 of Babylon's war dead fell through
  # the reconciler's rules into the branch that names barbarians by
  # elimination. Where a civilization's inferred deaths outnumber the ones
  # the record itself names several times over, that branch is answering a
  # default rather than reading evidence. The other civilizations in the
  # two reconciled logs sit between 1.6 and 2.6 inferred per recorded
  # death; Babylon sits at 18.
  MAX_INFERRED_PER_RECORDED = 4

  def initialize(game)
    @game = game
    @unit_losses = UnitLosses.for(game)
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

  # What the barbarians took from each empire. They belong to no war, so
  # these casualties cross no front and `during` never sees them, and
  # nothing else counts them either - which is also why no war toll ever
  # holds an inferred casualty, and `inferred` is reported here alone.
  # Empty on a log without attributed losses, where a barbarian kill is
  # recorded only when it took a civilian.
  def barbarian_losses
    return {} unless @unit_losses.applicable?

    @casualties.select { |casualty| casualty[:by] == BARBARIANS }
      .group_by { |casualty| casualty[:civ] }
      .transform_values { |losses| raids(losses) }
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
    @recorded_deaths = deaths.each_with_object(Hash.new(0)) { |one, by_civ| by_civ[one[:civ]] += 1 }

    # By turn, and only then by the order the log kept: an escort cut down
    # and the settler it guarded taken fall on the same turn, and which of
    # them opened the war is what the log says it was.
    (deaths + unrecorded(log, tally_of(deaths))).sort_by { |casualty| casualty.values_at(:turn, :seq) }
  end

  def death(event)
    killer, victim, unit = event.payload.values_at("killer", "victim", "unit")

    { seq: event.seq, turn: event.turn, civ: victim, unit: unit, by: killer,
      fate: :killed, confidence: recorded_confidence }
  end

  # The combat record is the game's own, so a death it holds was named
  # rather than inferred. Confidence is the reconciler's field, though, and
  # a log it never ran over carries none anywhere.
  def recorded_confidence = (:confirmed if @unit_losses.applicable?)

  # A loss the hook named barbarians on stands however the game stood. An
  # inferred one is kept only where the combat record covers this
  # civilization at all, and where no war of its own explains the death
  # better than a raid does.
  def raids(losses)
    civ = losses.first[:civ]
    named, inferred = losses.partition { |casualty| casualty[:confidence] == :confirmed }
    return tallied(named, war_dead: 0, unrecorded: inferred.size) unless covered?(civ, inferred.size)

    raided, war_dead = inferred.partition { |casualty| !at_war?(civ, casualty[:turn]) }
    tallied(named + raided, war_dead: war_dead.size, unrecorded: 0)
  end

  def tallied(losses, war_dead:, unrecorded:)
    { losses: losses.size, loss_types: by_type(losses),
      turns: losses.map { |casualty| casualty[:turn] }.uniq.sort,
      inferred: losses.count { |casualty| casualty[:confidence] == :inferred },
      set_aside: { war_dead: war_dead, no_combat_record: unrecorded } }
  end

  def covered?(civ, inferred)
    inferred <= @recorded_deaths[civ] * MAX_INFERRED_PER_RECORDED
  end

  # Its own wars, the ones against city-states included: a unit that fell
  # inside one of them has a war to explain it, and the reconciler reaches
  # for barbarians only because no record named the killer.
  def at_war?(civ, turn)
    wars_of(civ).any? do |war|
      turn >= war[:turn_declared] && (war[:turn_peace].nil? || turn <= war[:turn_peace])
    end
  end

  def wars_of(civ)
    @wars_of ||= {}
    @wars_of[civ] ||= PlayerTimeline.for(@game).wars(civ)
  end

  # A removal counts only where something named who took the unit - the
  # hook's own killed_by, or the killer a reconciled log worked out - and
  # only where the cause is a death or a capture rather than a job
  # finished. A unit that can fight cannot be taken, so the same record on
  # a soldier is a death the combat log missed rather than a capture.
  def named_losses(log)
    log.of_type("unit_lost").filter_map do |event|
      unit = event.payload["unit"]
      taker = @unit_losses.killer(event) || event.payload["killed_by"]
      next unless taker && casualty?(event)

      { seq: event.seq, turn: event.turn, civ: event.civ, unit: unit, by: taker,
        fate: fate_of(event, unit), confidence: @unit_losses.confidence(event) }
    end
  end

  def casualty?(event)
    cause = @unit_losses.cause(event)

    cause.nil? || CASUALTY_CAUSES.include?(cause)
  end

  # Where a reconciled log says the city itself fell, the unit inside it
  # was taken with it, whatever the unit was.
  def fate_of(event, unit)
    return :captured if @unit_losses.cause(event) == :city_captured

    CIVILIAN_UNITS.include?(unit) ? :captured : :killed
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
