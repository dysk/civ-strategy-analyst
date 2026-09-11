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
                  spy_evicted spy_mission_completed spy_surveillance_established].freeze

  # The two events that take a spy out of a city where it stood. Taking a
  # city or razing one throws out every major's spy that sat in it, the
  # captor's own included, and the DLL leaves the spy unassigned rather
  # than anywhere (CvPlayer.cpp:2775-2829, CvCity.cpp:2069-2073).
  ENDINGS = { "spy_killed" => :killed, "spy_evicted" => :evicted }.freeze

  # The mission state names its kind outright, so nothing is inferred from
  # whose city it was. A stolen technology is never named: no API exposes it.
  MISSION_KINDS = { "gathering_intel" => :tech_theft, "rigging_election" => :election_rigging }.freeze

  # Travel plus surveillance, at either branch of the wait, plus the slack a
  # missed poll adds. A completion landing in this window after the posting is
  # the shared progress counter restarting, not a mission.
  TRANSITION_WINDOW = (3..6).freeze
  POSTINGS = %w[spy_moved spy_created].freeze
  COUNTER_INTEL = "counter_intel"

  # CvEspionageClasses.cpp:23 and CvCultureClasses.cpp:2919. The wait is cut to
  # one turn at Familiar or better over the target, and a counterspy skips it
  # entirely - a garrison needs no surveillance.
  # CvEspionageClasses.cpp:2110. A failed coup kills the spy and sets its
  # owner's influence at the target to a flat -10. The margin absorbs the turn
  # of recovery the next snapshot has already applied and the integer the log
  # rounds it to, and it is the same margin the swap test uses.
  COUP_PENALTY = -10
  COUP_MARGIN = 2.0
  RIGGING_WINDOW = 1

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

  # A completed mission, minus the ones that never happened. Counts from a
  # pre-fix log are upper bounds from this side and lower bounds from the
  # other: a kill hides the completion that provoked it in every log, because
  # the DLL takes the death branch before it writes the completion.
  def missions(civ = nil)
    return all_missions unless civ

    all_missions.select { |mission| mission[:civ] == civ }
  end

  def losses(civ = nil)
    return all_losses unless civ

    all_losses.select { |loss| loss[:civ] == civ }
  end

  # The tenures that granted a rival vision of `city` over the window, which is
  # the whole of the wonder-race join. Three kinds observe nothing whatever the
  # window says: one the log never dated, one the spy left before its
  # surveillance would have gone live, and one a civ holds in its own city -
  # nobody needs a spy to watch themselves build.
  def observers_of(city, from_turn, to_turn)
    tenures.select do |tenure|
      tenure[:city] == city && tenure[:civ] != tenure[:city_civ] &&
        saw?(tenure) && overlaps?(tenure, from_turn, to_turn)
    end
  end

  # A garrison, read off the log where it says so and inferred where it does not.
  # A counterspy is the only spy posted to one of its owner's own cities, and
  # the `counter_intel` state is what proves it arrived: the Sioux ordered one
  # spy home five times without it ever settling, and those legs are transits.
  def counterspies(civ)
    logged = logged_garrisons(civ)
    logged.any? ? logged : inferred_garrisons(civ)
  end

  # Neither outcome of a coup fires an event, so both are read from what they
  # leave behind. A failure is a spy dying at a city-state with its owner's
  # influence there driven to the penalty; a success is an alliance changing
  # hands while two civs' influence trades places, with no rigged election to
  # account for it. Both halves of each signature are required - a death alone
  # is a garrison's work and a -10 alone has other causes.
  def coups(civ = nil)
    return all_coups unless civ

    all_coups.select { |coup| coup[:civ] == civ }
  end

  # What a civ spent on espionage and how much of it sat at home. Revivals are
  # reported beside creations and never summed into them: the DLL redraws the
  # name, so a sum would count one spy twice.
  def capacity(civ)
    events = spy_events.select { |event| event.civ == civ }

    { created: count(events, "spy_created"), revived: count(events, "spy_revived"),
      killed: count(events, "spy_killed"), promoted: count(events, "spy_promoted"),
      never_located: never_located(events) }
  end

  private

  def spy_events = @spy_events ||= SPY_EVENTS.flat_map { |type| @log.of_type(type) }.sort_by(&:seq)

  def saw?(tenure)
    tenure[:visible_from_turn] && tenure[:visible_from_turn] <= tenure[:until_turn]
  end

  def overlaps?(tenure, from_turn, to_turn)
    tenure[:visible_from_turn] <= to_turn && tenure[:until_turn] >= from_turn
  end

  def all_tenures
    @all_tenures ||= events_by_spy
      .flat_map { |_key, events| tenures_of_one_spy(events) }
      .sort_by.with_index { |tenure, index| [ tenure[:from_turn], index ] }
  end

  def events_by_spy = @events_by_spy ||= spy_events.group_by { |event| identity(event) }

  # The DLL redraws a spy's name when it revives, so the agent slot is the
  # identity wherever the logger writes one. An older log has only the name,
  # and there a revival reads as a spy that never existed.
  def identity(event) = [ event.civ, event.payload["agent"] || event.payload["spy"] ]

  def career(event) = events_by_spy.fetch(identity(event), [])

  def tenures_of_one_spy(events)
    spans = runs(events.select { |event| event.payload["city"] })
    unlocated = events.reject { |event| event.payload["city"] }.select { |event| ENDINGS.key?(event.event_type) }
    spans.map.with_index { |run, index| tenure(run, exit_of(run, spans[index + 1], unlocated)) }
  end

  def runs(events)
    events.each_with_object([]) do |event, runs|
      runs << [] if runs.empty? || run_ends?(runs.last, event)
      runs.last << event
    end
  end

  # A death or an eviction ends the run wherever the agent turns up next,
  # including the city it left - otherwise a revival or a re-posting on the
  # same spot would read as one unbroken tenure. The city changing hands ends
  # it too: that is an eviction the log failed to record, which happens when
  # the spy is sent back on the turn it was thrown out.
  def run_ends?(run, event)
    ENDINGS.key?(run.last.event_type) ||
      run.last.payload["city"] != event.payload["city"] ||
      run.last.payload["city_civ"] != event.payload["city_civ"]
  end

  # `to_turn` is the last turn the log proves the spy stood there. This is
  # when it left, by the best evidence the log offers: the turn it died or was
  # thrown out, the order that sent it elsewhere, and for a tenure nothing ever
  # closed, the last turn the game logged. The `observers_of` join runs against
  # this; a digest reports `to_turn`.
  #
  # A death the logger could not place still closes the tenure it falls in.
  # India-diplo's nine kills in Delhi carry no city, and without this those
  # nine spies would read as watching to the end of the game.
  def exit_of(run, next_run, unlocated)
    return [ run.last.turn, ENDINGS.fetch(run.last.event_type) ] if ENDINGS.key?(run.last.event_type)

    ending = unlocated.find { |event| ends_the_run?(event, run, next_run) }
    return [ ending.turn, ENDINGS.fetch(ending.event_type) ] if ending

    next_run ? [ next_run.first.turn, :moved ] : [ last_logged_turn, :log_end ]
  end

  def ends_the_run?(event, run, next_run)
    event.turn >= run.last.turn && (next_run.nil? || event.turn <= next_run.first.turn)
  end

  def last_logged_turn = @last_logged_turn ||= @log.all.map(&:turn).max

  def tenure(run, (until_turn, ended_by))
    first, vision = run.first, vision(run)

    { civ: first.civ, spy: first.payload["spy"], agent: first.payload["agent"],
      city: first.payload["city"], city_civ: first.payload["city_civ"],
      from_turn: first.turn, to_turn: run.last.turn, until_turn: until_turn,
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

  def all_missions
    @all_missions ||= @log.of_type("spy_mission_completed").filter_map { |event| mission(event) }
  end

  def mission(event)
    anchor = posting_before(event)
    return if artifact?(event, anchor)

    { civ: event.civ, spy: event.payload["spy"], agent: event.payload["agent"],
      city: event.payload["city"], city_civ: event.payload["city_civ"], turn: event.turn,
      kind: MISSION_KINDS[event.payload["state"]], anchored: post_fix? || !anchor.nil? }
  end

  # Travelling, surveillance and gathering intel share one progress counter and
  # each new state restarts it, so surveillance finishing used to read as a
  # mission finishing - 23 of india-diplo's 53 completions are that transition.
  # A log that reports surveillance in its own right has had them split off
  # upstream and is counted straight.
  def artifact?(event, anchor)
    return false if post_fix? || anchor.nil?

    TRANSITION_WINDOW.cover?(event.turn - anchor.turn)
  end

  def post_fix? = @post_fix ||= @log.of_type("spy_surveillance_established").any?

  # The nearest preceding order, and only if it can be about this city. A
  # creation the logger could not place still anchors, because a spy granted
  # and sent the same turn is most of india-diplo's lost postings; a posting to
  # somewhere else does not, because the return that followed it went unlogged
  # and nothing dates the completion.
  def posting_before(completion)
    posting = career(completion)
      .select { |event| POSTINGS.include?(event.event_type) && event.turn <= completion.turn }.last
    return unless posting

    city = posting.payload["city"]
    posting if city.nil? || city == completion.payload["city"]
  end

  def logged_garrisons(civ)
    tenures(civ).select { |tenure| tenure[:states].include?(COUNTER_INTEL) }.map { |tenure| garrison(tenure) }
  end

  def garrison(tenure)
    { civ: tenure[:civ], city: tenure[:city], spy: tenure[:spy], agent: tenure[:agent],
      from_turn: tenure[:from_turn], to_turn: tenure[:to_turn], until_turn: tenure[:until_turn],
      kills: kills_at(tenure[:civ], tenure[:city], tenure[:from_turn]..tenure[:until_turn]),
      inferred: false, confidence: nil }
  end

  def kills_at(civ, city, span)
    all_losses.count { |loss| loss[:civ] != civ && loss[:city] == city && span.cover?(loss[:turn]) }
  end

  # Three signals that agree, and a record that says how many did. A kill is
  # impossible in a city its owner has not garrisoned - the KILLED branch sits
  # inside HasCounterSpy (CvEspionageClasses.cpp:538-582) - a spy that never
  # appears in a city is the garrison the log failed to place, and the defender
  # is what levels up on a kill. A spy dying at a city-state is a failed coup
  # and proves nothing, so those deaths are left out.
  def inferred_garrisons(civ)
    deaths, career = deaths_at_home(civ), unlocated_spy(civ)
    return [] if deaths.empty? && career.nil?

    [ inferred_garrison(civ, deaths, career) ]
  end

  def inferred_garrison(civ, deaths, career)
    city = modal_city(deaths)
    first = career&.first

    { civ: civ, city: city, spy: first&.payload&.dig("spy"), agent: first&.payload&.dig("agent"),
      from_turn: evidence(deaths, career).min, to_turn: evidence(deaths, career).max,
      until_turn: departure(career),
      kills: deaths.count { |loss| loss[:city] == city },
      inferred: true, confidence: confidence(civ, deaths, career) }
  end

  # Every turn something placed the garrison there. The named spy's own death
  # is not one of them - it ends the garrison rather than proving it stood.
  def evidence(deaths, career)
    deaths.map { |loss| loss[:turn] } +
      Array(career).reject { |event| ENDINGS.key?(event.event_type) }.map(&:turn)
  end

  def departure(career)
    end_of_it = Array(career).find { |event| ENDINGS.key?(event.event_type) }

    end_of_it ? end_of_it.turn : last_logged_turn
  end

  def confidence(civ, deaths, career)
    [ !career.nil?, deaths.any?, promoted_on_a_death?(civ, deaths) ].count { |signal| signal }
  end

  def promoted_on_a_death?(civ, deaths)
    turns = deaths.map { |loss| loss[:turn] }
    @log.of_type("spy_promoted").any? { |event| event.civ == civ && turns.include?(event.turn) }
  end

  def deaths_at_home(civ)
    return [] if city_states.include?(civ)

    all_losses.select { |loss| loss[:civ] != civ && loss[:city_civ] == civ }
  end

  def city_states = snapshots.keys

  def snapshots
    @snapshots ||= @log.of_type("city_state_snapshot").group_by { |event| event.payload["city_state"] }
  end

  def unlocated_spy(civ)
    events_by_spy.filter_map { |(owner, _), career| career if owner == civ }
      .find { |career| career.none? { |event| event.payload["city"] } }
  end

  def modal_city(deaths)
    deaths.group_by { |loss| loss[:city] }.max_by { |_city, group| group.size }&.first
  end

  def all_losses = @all_losses ||= @log.of_type("spy_killed").map { |event| loss(event) }

  def loss(event)
    { civ: event.civ, spy: event.payload["spy"], agent: event.payload["agent"],
      turn: event.turn }.merge(death_site(event))
  end

  # A post-fix log carries the death site, read off the last live poll before
  # the DLL empties it. An older one carries none at all, so the site is the
  # last place the spy was seen and the record says how stale that is.
  def death_site(event)
    return site(event, inferred: false, stale: 0) if event.payload["city"]

    seen = last_sighting_before(event)
    return { city: nil, city_civ: nil, city_inferred: nil, turns_since_last_seen: nil } unless seen

    site(seen, inferred: true, stale: event.turn - seen.turn)
  end

  def site(event, inferred:, stale:)
    { city: event.payload["city"], city_civ: event.payload["city_civ"],
      city_inferred: inferred, turns_since_last_seen: stale }
  end

  def last_sighting_before(kill)
    career(kill).select { |event| event.payload["city"] && event.turn <= kill.turn }.last
  end

  def all_coups = @all_coups ||= (failed_coups + succeeded_coups).sort_by { |coup| coup[:turn] }

  def failed_coups
    all_losses.select { |loss| city_states.include?(loss[:city_civ]) }.filter_map { |loss| failed_coup(loss) }
  end

  def failed_coup(loss)
    penalty = influence_at(loss[:city_civ], loss[:civ], loss[:turn])
    return unless penalty && near?(penalty, COUP_PENALTY)

    coup(loss[:civ], loss[:city_civ], loss[:turn], :failed, spy: loss[:spy], influence: penalty)
  end

  # CanStageCoup requires the city-state to already have an ally, so a coup
  # transfers an alliance and can never create one. That makes the ally change
  # the anchor, and the influence swap around it the discriminator.
  def succeeded_coups
    @log.of_type("city_state_ally_changed").filter_map { |event| succeeded_coup(event) }
  end

  def succeeded_coup(event)
    city_state, winner, loser = event.payload.values_at("city_state", "new_ally", "old_ally")
    return unless winner.present? && loser.present?
    return if rigged?(city_state, winner, event.turn)
    return unless traded_places?(city_state, winner, loser, event.turn)

    coup(winner, city_state, event.turn, :succeeded,
         spy: nil, influence: influence_at(city_state, winner, event.turn))
  end

  def traded_places?(city_state, winner, loser, turn)
    gained, lost = influence_at(city_state, winner, turn), influence_at(city_state, loser, turn)
    held, held_by_loser = influence_before(city_state, winner, turn), influence_before(city_state, loser, turn)
    return false if [ gained, lost, held, held_by_loser ].any?(&:nil?)

    near?(gained, held_by_loser) && near?(lost, held)
  end

  def rigged?(city_state, civ, turn)
    @log.of_type("spy_mission_completed").any? do |event|
      event.civ == civ && event.payload["city"] == city_state &&
        event.payload["state"] == "rigging_election" && (event.turn - turn).abs <= RIGGING_WINDOW
    end
  end

  # Influence on a turn no snapshot covers, walked back from the nearest one
  # that reports the civ at all. A city-state names only the civs it has a
  # standing with, so the snapshot on the turn itself is often silent about the
  # one that matters.
  def influence_at(city_state, civ, turn)
    reported = standings(city_state, civ).find { |snapshot, _| snapshot.turn >= turn }

    reported && projected(reported, turn)
  end

  def influence_before(city_state, civ, turn)
    reported = standings(city_state, civ).reverse.find { |snapshot, _| snapshot.turn < turn }

    reported && projected(reported, turn)
  end

  def projected((snapshot, standing), turn)
    standing["influence"] - standing["per_turn"].to_f * (snapshot.turn - turn)
  end

  def standings(city_state, civ)
    snapshots.fetch(city_state, []).filter_map do |snapshot|
      standing = Array(snapshot.payload["relations"]).find { |relation| relation["civ"] == civ }
      [ snapshot, standing ] if standing
    end
  end

  def near?(value, target) = (value - target).abs <= COUP_MARGIN

  def coup(civ, city_state, turn, outcome, spy:, influence:)
    { civ: civ, city_state: city_state, spy: spy, turn: turn, outcome: outcome, influence: influence }
  end

  def count(events, type) = events.count { |event| event.event_type == type }

  # The cheapest honest measure of how much of a civ's investment never left
  # home: a spy that appears in the log but never with a city.
  def never_located(events)
    events.group_by { |event| identity(event) }
      .count { |_spy, career| career.none? { |event| event.payload["city"] } }
  end
end
