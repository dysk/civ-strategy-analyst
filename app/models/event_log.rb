# A game's events, loaded once and indexed on demand.
#
# Projections used to load what they needed in their own constructors, so a
# row was materialized once per projection that wanted it - a cost that grows
# with events and with projections at the same time. Reading through a shared
# log makes that one pass, and the indexes built here replace the per-civ
# rescans that made a lookup cost a walk of the whole list.
class EventLog
  def self.for(game) = new(game.game_events.order(:seq).to_a)

  def initialize(events)
    @events = events
    @by_type = events.group_by(&:event_type)
    @indexes = {}
  end

  attr_reader :events
  alias all events

  def of_type(type) = @by_type.fetch(type, [])

  # `by("snapshot", :civ)["Rome"]` in place of a scan per civ.
  def by(type, attribute)
    @indexes[[ type, attribute ]] ||= of_type(type).group_by(&attribute)
  end
end
