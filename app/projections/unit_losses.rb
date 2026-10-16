# What a unit_lost row says about itself, where the log says anything.
#
# unit_lost fires on every unit removal whatever the reason, and the
# in-game hook cannot tell them apart - separating a spent caravan from a
# dead one needs the whole file. civ-narrative-logger's
# tools/reconcile-unit-lost.jq joins the file afterwards and writes
# `cause`, `confidence` and `killer`, so a log carries the three fields on
# every removal or on none at all. `applicable?` says which kind of log
# this is, and every reader must ask before trusting a fate.
class UnitLosses
  extend Projection

  # The reconciler's own great-person list. It holds the nine vanilla great
  # people and none of the mod's unique ones, so an expend of a Dalai Lama
  # or a Pittore matches none of its rules and falls through to its
  # by-elimination branch as a barbarian kill. A great person outside this
  # list is therefore read as unclassified rather than trusted.
  RECONCILED_GREAT_PEOPLE = %w[
    UNIT_PROPHET UNIT_SCIENTIST UNIT_ENGINEER UNIT_WRITER UNIT_ARTIST
    UNIT_MUSICIAN UNIT_MERCHANT UNIT_GREAT_ADMIRAL UNIT_GREAT_GENERAL
  ].freeze

  NOTHING = {}.freeze

  def initialize(game)
    @log = game.event_log
  end

  def applicable? = losses.any? { |event| event.payload["cause"] }

  # :killed, :expended, :founded_city, :city_captured, :used_up or
  # :unknown - nil where this row cannot answer.
  def cause(event) = classified(event)["cause"]&.to_sym

  # :confirmed when a record named the fate outright, :inferred when it
  # follows by elimination.
  def confidence(event) = classified(event)["confidence"]&.to_sym

  # Whoever the record names as having taken the unit off the map, which
  # for a civilian lost with its city is the captor rather than a killer.
  def killer(event) = classified(event).values_at("killer", "captured_by").compact.first

  private

  def classified(event)
    payload = event.payload
    return NOTHING unless payload["cause"] && reconciled?(payload["unit"])

    payload
  end

  def reconciled?(unit)
    !PlayerTimeline::GREAT_PERSON_UNITS.key?(unit) || RECONCILED_GREAT_PEOPLE.include?(unit)
  end

  def losses = @losses ||= @log.of_type("unit_lost")
end
