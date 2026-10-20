# A city's religious history is a run, not a reading (docs/religion.md). A
# single `city_converted` row is never itself evidence of a lasting
# conversion - population churn moves the payload's follower count under an
# unchanged majority far more often than the majority itself changes - so a
# hold is the maximal run of consecutive rows naming the same religion for
# one city, collapsing that churn away.
#
# `city_converted` only fires on a gain, never on a loss to atheism or
# pantheon, so a hold that runs to the log's last row for its city is a
# lower bound on how long the religion actually stood. A silent atheism
# round-trip between two rows naming the same religion would otherwise read
# as one unbroken hold; where city_snapshot exists, its own religion field
# going absent between those two rows catches it and splits the run.
class Religion
  extend Projection

  # The span a hold must cross to count as settled when no city_snapshot
  # exists to check it against - the user's own number from play, not a
  # measurement. Docs/religion.md's own figures put the median span at 4 and
  # 47% of transitions at 3 turns or less, so this sits right at that edge
  # rather than clear of it.
  SETTLED_MIN_SPAN = 4

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

  # Neither unit's spread fires a hook of its own (docs/religion.md) - both
  # kill(true) themselves right after acting, so an absent killed_by on their
  # own unit_lost is that self-kill, the only trace a use leaves. A present
  # killed_by means an enemy ended the unit first, so nothing was spread.
  def missionary_uses(civ) = uses(civ, "UNIT_MISSIONARY")

  def inquisitor_uses(civ) = uses(civ, "UNIT_INQUISITOR")

  private

  def uses(civ, unit_type)
    @log.of_type("unit_lost")
      .select { |event| event.civ == civ && event.payload["unit"] == unit_type && !event.payload["killed_by"] }
      .sort_by(&:turn)
      .map { |event| use(event) }
  end

  # Where a use happened matters as much as that it happened, since a hold
  # is only worth setting against a use near the same city. The loss record
  # names a city for 7 of 116 uses across the logs, so the plot it carries
  # is what places the rest - and 83 of those sit on somebody else's land,
  # which is where a missionary does its work.
  def use(event)
    x, y = event.payload.values_at("x", "y")
    logged = event.payload["city"]
    place = tiles.owner([ x, y ], turn: event.turn) if x && y

    { turn: event.turn, city: logged || place&.dig(:city), owner: place&.dig(:civ),
      located: logged ? :logged : place&.dig(:source), x: x, y: y, inferred: true }
  end

  def tiles = @tiles ||= TileOwnership.for(@game)

  def conversions = @conversions ||= @log.of_type("city_converted")

  def city_snapshots = @city_snapshots ||= @log.of_type("city_snapshot")

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
      runs << [] if runs.empty? || breaks_run?(runs.last.last, event)
      runs.last << event
    end
  end

  def breaks_run?(previous, event)
    previous.payload["religion"] != event.payload["religion"] || lapsed_between?(previous, event)
  end

  # A gap the event stream can't see: the religion held at `previous` and
  # `event` is the same, but a snapshot strictly between them shows the
  # field absent, so the city lost and regained it silently in between.
  def lapsed_between?(previous, event)
    snapshots_of(previous.payload["city"]).any? do |snapshot|
      snapshot.turn > previous.turn && snapshot.turn < event.turn && !snapshot.payload.key?("religion")
    end
  end

  def hold(run)
    first = run.first
    city, religion, to_turn = first.payload["city"], first.payload["religion"], run.last.turn

    { civ: first.civ, city: city, religion: religion, from_turn: first.turn, to_turn: to_turn,
      settled: settled?(city, religion, first.turn, to_turn) }
  end

  # The snapshot channel outranks the span wherever it can answer at all - it
  # says plainly when a city holds no religion, rather than staying silent the
  # way the event stream does. The span is only a fallback for a hold nothing
  # confirms either way.
  def settled?(city, religion, from_turn, to_turn)
    confirmation = next_snapshot(city, to_turn)
    return confirmation.payload["religion"] == religion if confirmation

    to_turn - from_turn >= SETTLED_MIN_SPAN
  end

  def next_snapshot(city, to_turn)
    snapshots_of(city).find { |event| event.turn > to_turn }
  end

  # One city's snapshots in turn order. Every run and every hold asks about
  # a single city, so indexing once replaces a walk of every snapshot in the
  # game per question - the cost that grew with snapshots and conversions
  # multiplied together.
  def snapshots_of(city)
    @snapshots_by_city ||= city_snapshots
      .sort_by { |event| [ event.turn, event.seq ] }
      .group_by { |event| event.payload["city"] }

    @snapshots_by_city.fetch(city, [])
  end
end
