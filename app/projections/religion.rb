# A city's religious history is a run, not a reading (docs/religion.md). A
# single `city_converted` row is never itself evidence of a lasting
# conversion - population churn moves the payload's follower count under an
# unchanged majority far more often than the majority itself changes - so a
# hold is the maximal run of consecutive rows naming the same religion for
# one city, collapsing that churn away.
#
# `city_converted` only fires on a gain, never on a loss to atheism or
# pantheon, so a hold that runs to the log's last row for its city is a
# lower bound on how long the religion actually stood, and a silent
# atheism round-trip between two rows naming the same religion reads as
# one unbroken hold. Neither is corrected here yet.
class Religion
  extend Projection

  def initialize(game)
    @game = game
    @log = game.event_log
  end

  def applicable? = conversions.any?

  # One record per maximal run of one religion holding one city's majority,
  # earliest first. Unfiltered when `civ` is nil - the caller decides which
  # civs matter, the same convention `ResearchBeelines` and `Espionage` use.
  def holds(civ = nil)
    return all_holds unless civ

    all_holds.select { |hold| hold[:civ] == civ }
  end

  private

  def conversions = @conversions ||= @log.of_type("city_converted")

  def all_holds
    @all_holds ||= conversions
      .group_by { |event| [ event.civ, event.payload["city"] ] }
      .flat_map { |_key, events| holds_of_one_city(events) }
      .sort_by.with_index { |hold, index| [ hold[:from_turn], index ] }
  end

  def holds_of_one_city(events)
    runs(events.sort_by { |event| [ event.turn, event.seq ] }).map { |run| hold(run) }
  end

  def runs(events)
    events.each_with_object([]) do |event, runs|
      runs << [] if runs.empty? || runs.last.last.payload["religion"] != event.payload["religion"]
      runs.last << event
    end
  end

  def hold(run)
    first = run.first

    { civ: first.civ, city: first.payload["city"], religion: first.payload["religion"],
      from_turn: first.turn, to_turn: run.last.turn }
  end
end
