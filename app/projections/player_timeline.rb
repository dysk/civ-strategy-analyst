class PlayerTimeline
  extend Projection

  def initialize(game)
    @game = game
    @log = game.event_log
  end

  def cities(civ)
    founded = of_type("city_founded").select { |e| e.civ == civ }.map do |e|
      { turn: e.turn, city: e.payload["city"], action: :founded }
    end

    captured = of_type("city_captured").select { |e| e.payload["new_owner"] == civ }.map do |e|
      { turn: e.turn, city: e.payload["city"], action: :captured,
        from: e.payload["old_owner"], conquest: e.payload["conquest"], valuation: valuation(e) }
    end

    lost = of_type("city_captured").select { |e| e.payload["old_owner"] == civ }.map do |e|
      { turn: e.turn, city: e.payload["city"], action: :lost,
        to: e.payload["new_owner"], conquest: e.payload["conquest"], valuation: valuation(e) }
    end

    sort_events(founded + captured + lost)
  end

  def techs(civ)
    research = of_type("tech_researched").select { |e| Array(e.payload["civs"]).include?(civ) }.map do |e|
      { turn: e.turn, tech: e.payload["tech"], source: :research }
    end

    ruins = of_type("tech_from_ruins").select { |e| e.civ == civ }.map do |e|
      { turn: e.turn, tech: e.payload["tech"], source: :ruins }
    end

    sort_events(research + ruins)
  end

  def policies(civ)
    unlocked = of_type("policy_branch_unlocked").select { |e| e.civ == civ }.map do |e|
      { turn: e.turn, type: :branch_unlocked, name: e.payload["branch"] }
    end

    adopted = of_type("policy_adopted").select { |e| e.civ == civ }.map do |e|
      { turn: e.turn, type: :policy_adopted, name: e.payload["policy"] }
    end

    branch_adopted = of_type("policy_branch_adopted").select { |e| e.civ == civ }.map do |e|
      { turn: e.turn, type: :branch_adopted, name: e.payload["branch"] }
    end

    sort_events(unlocked + adopted + branch_adopted)
  end

  def religion(civ)
    pantheon = of_type("pantheon_founded").select { |e| e.civ == civ }.map do |e|
      { turn: e.turn, type: :pantheon_founded, city: e.payload["city"], belief: e.payload["belief"] }
    end

    founded = of_type("religion_founded").select { |e| e.civ == civ }.map do |e|
      { turn: e.turn, type: :religion_founded, holy_city: e.payload["holy_city"],
        religion: e.payload["religion"], beliefs: e.payload["beliefs"] }
    end

    enhanced = of_type("religion_enhanced").select { |e| e.civ == civ }.map do |e|
      { turn: e.turn, type: :religion_enhanced, religion: e.payload["religion"], beliefs: e.payload["beliefs"] }
    end

    reformation = of_type("reformation_added").select { |e| e.civ == civ }.map do |e|
      { turn: e.turn, type: :reformation_added, religion: e.payload["religion"], belief: e.payload["belief"] }
    end

    sort_events(pantheon + founded + enhanced + reformation)
  end

  # Every great person's departure from play - expended, killed by an enemy,
  # or disbanded - never its birth (see great_people_born).
  def great_people(civ)
    expends = of_type("great_person_expended").select { |e| e.civ == civ }
    expended_turns = expends.map(&:turn).to_set

    losses = of_type("unit_lost").select do |e|
      e.civ == civ && GREAT_PERSON_UNITS.key?(e.payload["unit"]) && lost?(e, expended_turns)
    end

    sort_events(expends.map { |e| expended_row(e) } + losses.map { |e| lost_row(e) })
  end

  # The births timeline appearance alone can give: which great person, on
  # what turn, in which city (nil where the log didn't carry one - a
  # barbarian-adjacent spawn quirk, not unique to great people).
  def great_people_born(civ)
    sort_events(
      of_type("unit_created").select { |e| e.civ == civ && GREAT_PERSON_UNITS.key?(e.payload["unit"]) }.map do |e|
        { turn: e.turn, great_person: e.payload["unit"], city: e.payload["city"] }
      end
    )
  end

  def eras(civ)
    of_type("era_entered").select { |e| Array(e.payload["civs"]).include?(civ) }.map do |e|
      { turn: e.turn, era: e.payload["era"] }
    end
  end

  def golden_ages(civ)
    of_type("golden_age_started").select { |e| e.civ == civ }.map do |e|
      { turn: e.turn }
    end
  end

  def buildings(civ)
    sort_events(
      of_type("building_constructed").select { |e| e.civ == civ }.map do |e|
        { turn: e.turn, building: e.payload["building"], city: e.payload["city"],
          class: e.payload["wonder"]&.to_sym }
      end
    )
  end

  def wonders(civ)
    buildings(civ).select { |building| building[:class].in?(%i[world national]) }
  end

  def city_states(civ)
    friendship = of_type("city_state_friendship_changed").select { |e| e.civ == civ }.map do |e|
      { turn: e.turn, type: :friendship_changed, city_state: e.payload["city_state"],
        friends: e.payload["friends"], old_friendship: e.payload["old_friendship"],
        new_friendship: e.payload["new_friendship"] }
    end

    alliance = of_type("city_state_alliance_changed").select { |e| e.civ == civ }.map do |e|
      { turn: e.turn, type: :alliance_changed, city_state: e.payload["city_state"],
        allied: e.payload["allied"], old_friendship: e.payload["old_friendship"],
        new_friendship: e.payload["new_friendship"] }
    end

    ally_gained = of_type("city_state_ally_changed").select { |e| e.payload["new_ally"] == civ }.map do |e|
      { turn: e.turn, type: :ally_gained, city_state: e.payload["city_state"] }
    end

    ally_lost = of_type("city_state_ally_changed").select { |e| e.payload["old_ally"] == civ }.map do |e|
      { turn: e.turn, type: :ally_lost, city_state: e.payload["city_state"] }
    end

    sort_events(friendship + alliance + ally_gained + ally_lost)
  end

  def wars(civ)
    war_periods.select { |war| war[:civ] == civ }.map { |war| war.except(:civ) }
  end

  # The single vote, if any, that removed this civ from the game. A passed
  # irrelevance proposal happens once and ends the civ's contention.
  def irrelevance(civ)
    event = of_type("mp_proposal_result").find do |e|
      e.payload["type"] == "irrelevance" && e.payload["status"] == "passed" && e.payload["subject"] == civ
    end
    return unless event

    { turn: event.turn, proposer: event.payload["owner"],
      yes_votes: event.payload["yes_votes"], no_votes: event.payload["no_votes"] }
  end

  private

  # The mod's great-person units, mapped to the kind they act as below.
  # UNIT_DALAILAMA, UNIT_FAKEPROPHET and UNIT_MABA are civilization-unique
  # reskins of the Prophet, UNIT_ITALARTIST of the Artist,
  # UNIT_LEU_COMPARSA_FOLKLORICA of the Musician and UNIT_VENETIAN_MERCHANT
  # of the Merchant - all read off the mod's own Units and Unit_Builds
  # tables, except the three prophet analogues, which sit alongside
  # UNIT_PROPHET in WarCasualties::CIVILIAN_UNITS and are grouped on that
  # basis.
  GREAT_PERSON_UNITS = {
    "UNIT_SCIENTIST" => :scientist,
    "UNIT_ENGINEER" => :engineer,
    "UNIT_MERCHANT" => :merchant,
    "UNIT_VENETIAN_MERCHANT" => :merchant,
    "UNIT_ARTIST" => :artist,
    "UNIT_ITALARTIST" => :artist,
    "UNIT_MUSICIAN" => :musician,
    "UNIT_LEU_COMPARSA_FOLKLORICA" => :musician,
    "UNIT_WRITER" => :writer,
    "UNIT_PROPHET" => :prophet,
    "UNIT_MABA" => :prophet,
    "UNIT_FAKEPROPHET" => :prophet,
    "UNIT_DALAILAMA" => :prophet,
    "UNIT_GREAT_GENERAL" => :general,
    "UNIT_GREAT_ADMIRAL" => :admiral
  }.freeze

  # The improvements each kind can plant, from Unit_Builds joined to Builds
  # in the mod's own tables. A kind can plant more than one improvement, and
  # one action can answer to more than one improvement name where a
  # civilization reskins it. A landmark belongs to the archaeologist, not to
  # any great person; writer and artist plant nothing at all.
  PLANTED_ACTIONS = {
    scientist: { "IMPROVEMENT_ACADEMY" => :academy },
    engineer: { "IMPROVEMENT_MANUFACTORY" => :manufactory },
    merchant: { "IMPROVEMENT_CUSTOMS_HOUSE" => :customs_house },
    prophet: { "IMPROVEMENT_HOLY_SITE" => :holy_site, "IMPROVEMENT_SACRED_GROVE" => :sacred_grove },
    musician: { "IMPROVEMENT_CONCERT" => :festival },
    general: { "IMPROVEMENT_CITADEL" => :citadel },
    admiral: { "IMPROVEMENT_DOCK" => :dock, "IMPROVEMENT_CHILE_DOCK" => :dock }
  }.freeze

  # The use that leaves no plot behind, where the log can name it. A writer
  # and a musician each have two such uses the log cannot tell apart - a
  # great work against a culture award, a great work against a concert tour
  # - so they get :instant and the prompt names both readings. General and
  # admiral have none at all.
  UNPLANTED_ACTIONS = {
    scientist: :bulb,
    engineer: :hurry,
    merchant: :trade_mission,
    prophet: :religious_action,
    artist: :great_work,
    writer: :instant,
    musician: :instant
  }.freeze

  # The units that can begin a golden age, in the order they claim one.
  GOLDEN_AGE_UNITS = [ "UNIT_ARTIST", "UNIT_ITALARTIST", "UNIT_LEU_COMPARSA_FOLKLORICA", "UNIT_DALAILAMA" ].freeze

  # What an act pays, not whether it touched a tile. A great work is a
  # permanent yield with no plot behind it, and a golden age pays once
  # however long it runs. Anything else - :instant, or a nil action where a
  # general or admiral left no trace - is unresolved, which is a limit of
  # the record rather than a use of its own.
  PERMANENT_ACTIONS = %i[academy manufactory customs_house holy_site sacred_grove festival citadel dock great_work].freeze
  ONE_OFF_ACTIONS = %i[bulb hurry trade_mission religious_action golden_age].freeze

  # A planted improvement is the only great-person act that leaves a plot
  # behind, so it is the only one that can name a city. The plot sits on the
  # expending civ's own land in 54 of the 55 planted expends across the
  # logs; a citadel is the one kind that can land on a rival's border, and
  # then the city it names is the one it was planted against.
  def expended_row(event)
    planted = planted_improvement(GREAT_PERSON_UNITS[event.payload["great_person"]], event.civ, event.turn)
    place = planted && place_of(planted)

    { turn: event.turn, great_person: event.payload["great_person"], fate: :expended,
      action: expended_action(event, planted), city: place&.dig(:city),
      located: place&.dig(:source), civ: place&.dig(:civ), killed_by: nil, confidence: nil }
  end

  def expended_action(event, planted)
    kind = GREAT_PERSON_UNITS[event.payload["great_person"]]
    return PLANTED_ACTIONS.dig(kind, planted.payload["improvement"]) if planted
    return :golden_age if golden_age_claims(event.civ).include?(event.seq)

    UNPLANTED_ACTIONS[kind]
  end

  # (turn, civ) coincidence, not an id - the log has no other way to say a
  # planted improvement belongs to a particular expend. Filtering candidate
  # improvements to the ones this kind can plant is what separates three
  # great people expended the same turn against three unrelated
  # improvements finished that same turn.
  def planted_improvement(kind, civ, turn)
    plantable = PLANTED_ACTIONS[kind]
    return unless plantable

    of_type("improvement_built").find do |e|
      e.civ == civ && e.turn == turn && plantable.key?(e.payload["improvement"])
    end
  end

  # A golden age leaves nothing on the expend that began it, so it is
  # claimed by (turn, civ) coincidence the way a planted improvement is. 13
  # of the 31 artist expends across the logs share a turn with one, against
  # a 3.6% chance of a golden age starting on any given civ-turn, so the
  # coincidence is the artist's doing in nearly all of them. Each
  # golden_age_started is claimed once and by one expend, so two artists and
  # one age give one golden_age and one great_work.
  def golden_age_claims(civ)
    @golden_age_claims ||= {}
    @golden_age_claims[civ] ||= begin
      ages = of_type("golden_age_started").select { |e| e.civ == civ }.group_by(&:turn)

      golden_age_candidates(civ).flat_map do |turn, expends|
        expends
          .sort_by { |e| GOLDEN_AGE_UNITS.index(e.payload["great_person"]) }
          .first(ages.fetch(turn, []).size)
          .map(&:seq)
      end.to_set
    end
  end

  # An expend that planted an improvement spent itself on the plot, so it
  # cannot have begun an age and must not claim one away from an artist
  # expended the same turn.
  def golden_age_candidates(civ)
    of_type("great_person_expended")
      .select { |e| e.civ == civ && GOLDEN_AGE_UNITS.include?(e.payload["great_person"]) }
      .reject { |e| planted_improvement(GREAT_PERSON_UNITS[e.payload["great_person"]], civ, e.turn) }
      .group_by(&:turn)
  end

  def place_of(event)
    x, y = event.payload.values_at("x", "y")
    tiles.owner([ x, y ], turn: event.turn) if x && y
  end

  def tiles = @tiles ||= TileOwnership.for(@game)

  def unit_losses = @unit_losses ||= UnitLosses.for(@game)

  # A reconciled log names which removals were expends, so a loss it kept
  # is a loss. Without one, unit_lost fires for an expend too (UnitPrekill
  # runs before the consuming effect), and a loss on the same turn as an
  # expend for this civ is read as that echo - the fallback, and wrong
  # where one great person was killed the same turn another was spent.
  def lost?(event, expended_turns)
    cause = unit_losses.cause(event)
    return cause == :killed if cause

    !expended_turns.include?(event.turn)
  end

  # `civ` is whose ground the great person stood on, not whose great person
  # it was - the row already sits under its owner. `located` grades the
  # claim: a logged city, land the civ held, land it bordered, or the
  # nearest city the log can reach. The hook names a killer on the loss for
  # a captured civilian alone, so a reconciled log's `killer` is what fills
  # `killed_by` for every other death.
  def lost_row(event)
    logged = event.payload["city"]
    killed_by = unit_losses.killer(event) || event.payload["killed_by"]
    place = place_of(event) unless logged

    { turn: event.turn, great_person: event.payload["unit"],
      fate: killed_by ? :killed : :disbanded, action: nil, city: logged || place&.dig(:city),
      located: logged ? :logged : place&.dig(:source), civ: place&.dig(:civ),
      killed_by: killed_by, confidence: unit_losses.confidence(event) }
  end

  # What a capture cost the side that lost it: the city's share of that
  # empire before the transfer, its size before and after, the resistance
  # the captor then sat through, and the captor's cultural standing over
  # the former owner on the capture turn. Nil where the log carries no
  # city snapshot to read any of it from.
  def valuation(capture)
    return unless city_value.applicable?

    city = capture.payload["city"]
    before = last_snapshot(city, capture.turn - 1)
    after = first_snapshot_from(city, capture.turn, capture.payload["new_owner"])

    { value: city_value.at(city, capture.turn - 1),
      before: size_of(before), after: size_of(after),
      resistance: resistance_after(city, capture),
      captor_influence: captor_influence(capture) }
  end

  def size_of(snapshot)
    return unless snapshot

    { population: snapshot.payload["population"].to_i, buildings: snapshot.payload["buildings"].to_i }
  end

  # The captor's snapshots of the city from the capture turn on, up to and
  # including the first turn its resistance had run out.
  def resistance_after(city, capture)
    rows = snapshots_of(city)
      .select { |e| e.turn >= capture.turn && e.civ == capture.payload["new_owner"] }
      .index_by(&:turn).values.sort_by(&:turn)
    settled = rows.index { |e| e.payload["resistance_turns"].to_i.zero? }

    (settled ? rows.first(settled + 1) : rows).map do |e|
      { turn: e.turn, resistance_turns: e.payload["resistance_turns"].to_i,
        occupied: e.payload["occupied"], puppet: e.payload["puppet"], razing: e.payload["razing"] }
    end
  end

  def captor_influence(capture)
    points = InfluenceTimeline.for(@game)
      .series(capture.payload["new_owner"], capture.payload["old_owner"])
      .select { |point| point[:turn] <= capture.turn }.last
    return unless points

    points.slice(:points, :level, :trend)
  end

  def last_snapshot(city, turn)
    snapshots_of(city).select { |e| e.turn <= turn }.max_by(&:turn)
  end

  def first_snapshot_from(city, turn, civ)
    snapshots_of(city).select { |e| e.turn >= turn && e.civ == civ }.min_by(&:turn)
  end

  def snapshots_of(city) = snapshots_by_city.fetch(city, [])

  def snapshots_by_city = @snapshots_by_city ||= of_type("city_snapshot").group_by { |e| e.payload["city"] }

  def city_value = @city_value ||= CityValue.for(@game)

  def of_type(event_type) = @log.of_type(event_type)

  def sort_events(events)
    events.sort_by { |e| e[:turn] }
  end

  def war_periods
    @war_periods ||= build_war_periods
  end

  def build_war_periods
    declarations = of_type("war_declared").group_by { |e| team_pair(e.payload["attacker_team"], e.payload["defender_team"]) }
    peaces = of_type("peace_made").group_by { |e| team_pair(e.payload["team_a"], e.payload["team_b"]) }

    declarations.flat_map do |pair, wars|
      wars.each_with_index.flat_map do |war_declared, index|
        peace = peaces[pair]&.[](index)
        periods_for(war_declared, peace)
      end
    end
  end

  def periods_for(war_declared, peace)
    attacker_civs = Array(war_declared.payload["attacker_civs"])
    defender_civs = Array(war_declared.payload["defender_civs"])

    (attacker_civs.map { |civ| [ civ, :attacker, defender_civs ] } +
     defender_civs.map { |civ| [ civ, :defender, attacker_civs ] }).map do |civ, role, opponents|
      {
        civ: civ,
        role: role,
        opponents: opponents,
        turn_declared: war_declared.turn,
        turn_peace: peace&.turn,
        ties_at_declaration: ties_at_declaration(civ, opponents, war_declared.turn)
      }.merge(balance(civ, opponents, war_declared.turn, peace&.turn))
    end
  end

  # Diplomacy standing with an opponent at the moment war opened on them -
  # docs/reading-the-new-log.md §6's join, the one the plan called out by
  # name. DiplomaticTies already cuts a span to the declaration turn, so a
  # tie found here is one that stood right up to the moment war broke it,
  # never past it.
  def ties_at_declaration(civ, opponents, turn)
    opponents.flat_map { |opponent|
      diplomatic_ties.spans(civ, opponent)
        .select { |span| span[:from_turn] <= turn && (span[:to_turn].nil? || span[:to_turn] >= turn) }
        .map { |span| span.merge(with: opponent) }
    }
  end

  def diplomatic_ties = @diplomatic_ties ||= DiplomaticTies.for(@game)

  def balance(civ, opponents, turn_declared, turn_peace)
    in_window = ->(turn) { turn >= turn_declared && (turn_peace.nil? || turn <= turn_peace) }

    kills = of_type("unit_killed").select { |e| in_window.call(e.turn) }
    captures = of_type("city_captured").select { |e| in_window.call(e.turn) }

    {
      units_killed: kills.count { |e| e.payload["killer"] == civ && opponents.include?(e.payload["victim"]) },
      units_lost: kills.count { |e| e.payload["victim"] == civ && opponents.include?(e.payload["killer"]) },
      cities_captured: captures.count { |e| e.payload["new_owner"] == civ && opponents.include?(e.payload["old_owner"]) },
      cities_lost: captures.count { |e| e.payload["old_owner"] == civ && opponents.include?(e.payload["new_owner"]) }
    }
  end

  def team_pair(a, b)
    [ a, b ].sort
  end
end
