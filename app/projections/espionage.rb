# A spy is a position on the map held over a span of turns, and four separate
# questions join against that position - who watched a wonder go up, what moved
# a city-state, where spies died, whether a drop had a spotter. This projection
# is that primitive and nothing else.
#
# The log never shows that a player looked. It shows the opportunity to know,
# which is why the field is named `visible_from_turn` and why no reading here
# may be phrased as knowledge.
class Espionage
  extend Projection

  SPY_EVENTS = %w[spy_created spy_moved spy_promoted spy_killed spy_revived
                  spy_mission_completed spy_surveillance_established].freeze
  POSTINGS = %w[spy_moved spy_created].freeze
  COUNTER_INTEL = "counter_intel"

  # CvEspionageClasses.cpp:23 and CvCultureClasses.cpp:2919. The wait is cut to
  # one turn at Familiar or better over the target, and a counterspy skips it
  # entirely - a garrison needs no surveillance.
  TRAVEL_TURNS = 1
  SURVEILLANCE_TURNS = 3
  SURVEILLANCE_TURNS_WITH_TOURISM_LEAD = 1
  TOURISM_LEAD_LEVELS = %w[INFLUENCE_LEVEL_FAMILIAR INFLUENCE_LEVEL_POPULAR
                           INFLUENCE_LEVEL_INFLUENTIAL INFLUENCE_LEVEL_DOMINANT].freeze

  def initialize(game)
    @game = game
    @log = game.event_log
  end

  def applicable? = spy_events.any?

  # A tenure is a maximal run of sightings of one spy in one city. Its
  # `from_turn` is the first sighting rather than the arrival, so a span whose
  # posting fell in a reload seam is a lower bound on the time actually served.
  def tenures(civ = nil)
    return all_tenures unless civ

    all_tenures.select { |tenure| tenure[:civ] == civ }
  end

  private

  def spy_events = @spy_events ||= SPY_EVENTS.flat_map { |type| @log.of_type(type) }.sort_by(&:seq)

  def all_tenures
    @all_tenures ||= sightings.group_by { |event| [ event.civ, identity(event) ] }
      .flat_map { |_key, events| tenures_of_one_spy(events) }
      .sort_by.with_index { |tenure, index| [ tenure[:from_turn], index ] }
  end

  def sightings = spy_events.select { |event| event.payload["city"] }

  # The DLL redraws a spy's name when it revives, so the agent slot is the
  # identity wherever the logger writes one. An older log has only the name,
  # and there a revival reads as a spy that never existed.
  def identity(event) = event.payload["agent"] || event.payload["spy"]

  def tenures_of_one_spy(events)
    spans = runs(events)
    spans.map.with_index { |run, index| tenure(run, ended_by(run, last: index == spans.size - 1)) }
  end

  def runs(events)
    events.each_with_object([]) do |event, runs|
      runs << [] if runs.empty? || run_ends?(runs.last, event)
      runs.last << event
    end
  end

  # A death ends the run wherever the agent turns up next, including the city
  # it died in - otherwise a revival on the same spot would read as one
  # unbroken posting.
  def run_ends?(run, event)
    run.last.event_type == "spy_killed" || run.last.payload["city"] != event.payload["city"]
  end

  def ended_by(run, last:)
    return :killed if run.last.event_type == "spy_killed"

    last ? :log_end : :moved
  end

  def tenure(run, ended_by)
    first, vision = run.first, vision(run)

    { civ: first.civ, spy: first.payload["spy"], agent: first.payload["agent"],
      city: first.payload["city"], city_civ: first.payload["city_civ"],
      from_turn: first.turn, to_turn: run.last.turn,
      visible_from_turn: vision[:turn], visible_from_turn_bounded: vision[:bounded],
      states: states(run), ended_by: ended_by }
  end

  def states(run) = run.filter_map { |event| event.payload["state"] }.uniq

  # Three dating rules, in descending order of what they may be used for: the
  # logged turn, the computed one, and a floor a completed mission proves. A
  # `spy_moved` turn is never used unadjusted, and a run holding neither a
  # posting nor a mission carries no date at all.
  def vision(run)
    established = run.find { |event| event.event_type == "spy_surveillance_established" }
    return { turn: established.turn, bounded: false } if established

    posting = run.find { |event| POSTINGS.include?(event.event_type) }
    return { turn: posting.turn + wait(run, posting), bounded: false } if posting

    proof = run.find { |event| event.event_type == "spy_mission_completed" }
    proof ? { turn: proof.turn, bounded: true } : { turn: nil, bounded: false }
  end

  # A garrison needs no surveillance, so a counterspy's posting takes effect on
  # the travel turn alone. The state arrives a turn behind the order, in its
  # own `spy_moved` in the same city, so it is read off the whole run rather
  # than off the event that opened it.
  def wait(run, posting)
    return TRAVEL_TURNS if run.any? { |event| event.payload["state"] == COUNTER_INTEL }

    TRAVEL_TURNS + surveillance_turns(posting)
  end

  def surveillance_turns(posting)
    return SURVEILLANCE_TURNS_WITH_TOURISM_LEAD if tourism_lead?(posting.civ, posting.payload["city_civ"], posting.turn)

    SURVEILLANCE_TURNS
  end

  # Influence is logged between majors only, so a city-state target always
  # takes the base wait. The DLL measures that case against the city-state's
  # ally, which the standings projection reads and this one does not.
  def tourism_lead?(civ, target, turn)
    standing = influence.series(civ, target).select { |point| point[:turn] <= turn }.last

    standing && TOURISM_LEAD_LEVELS.include?(standing[:level])
  end

  def influence = @influence ||= InfluenceTimeline.for(@game)
end
