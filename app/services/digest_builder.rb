class DigestBuilder
  CHECKPOINT_INTERVAL = 25

  # The action families PlayerTimeline classifies an expend into: a planted
  # improvement keeps paying out for the turns left in the game, an instant
  # use pays out once.
  INFRASTRUCTURE_ACTIONS = PlayerTimeline::TARGETED_ACTIONS.values.map { |v| v[:action] }.freeze
  CONSUMPTION_ACTIONS = PlayerTimeline::UNTARGETED_ACTIONS.values.uniq.freeze
  SNAPSHOT_METRICS = %w[
    score science culture gold gold_per_turn faith happiness
    military_might military_units population cities techs
    production food gross_gold plots tourism civs_influential_on
  ].freeze

  # LEKMOD rule: every owned city raises the cost of researching a new tech
  # by +5%, and the cost of a culture-bought policy by +10% (additive per
  # city). These multipliers let the LLM interpret raw tech/policy counts
  # correctly instead of comparing wide and tall empires at face value.
  TECH_COST_PER_CITY = 0.05
  POLICY_COST_PER_CITY = 0.10

  def initialize(game, winner_civ: nil, victory_type: nil, lekmod_version: nil,
                 lekmod_root: Rails.root.join("db/lekmod"))
    @game = game
    @winner_civ = winner_civ
    @victory_type = victory_type
    @lekmod_version = lekmod_version
    @lekmod_root = lekmod_root
  end

  def call
    {
      game: game_settings,
      roster: roster,
      outcome: outcome,
      standings: standings,
      early_game: early_game.series,
      metrics: metrics_by_civ,
      timelines: timelines_by_civ,
      capital_proximity: CapitalProximity.for(@game).call,
      buffer_cities: BufferCities.for(@game).call,
      key_moments: key_moments,
      wonder_races: wonder_races,
      espionage: espionage,
      diplomatic_ties: diplomatic_ties,
      trade_routes: trade_routes,
      religion: religion,
      yield_attribution: yield_attribution,
      resource_shortages: resource_shortages,
      deals: deals,
      unit_names: unit_names,
      spy_names: spy_names,
      cultural: cultural_by_civ,
      congress: congress,
      city_states: city_states,
      victory_progress: victory_progress,
      lekmod: lekmod
    }
  end

  private

  def standings
    MetricSeries.for(@game).final_ranking("score")
  end

  def game_settings
    {
      name: @game.name, map_script: @game.map_script, map_size: @game.map_size,
      game_speed: @game.game_speed, max_turns: @game.max_turns, start_era: @game.start_era,
      map_width: map_bounds.width, map_height: map_bounds.height,
      map_width_estimated: map_bounds.estimated?,
      early_game_deadline_turn: early_game.deadline_turn
    }
  end

  def early_game = EarlyGame.for(@game)

  def map_bounds = MapBounds.for(@game)

  def roster
    @game.players.order(:id).map do |player|
      { civ: player.civ, leader_name: player.leader_name, human: player.human, handicap: player.handicap }
    end
  end

  def outcome
    OutcomeResolver.new(@game, winner_civ: @winner_civ, victory_type: @victory_type).call
  end

  def metrics_by_civ
    snapshots_by_civ_turn.each_with_object({}) do |(civ, turns), result|
      result[civ] = checkpoints_for(turns)
    end
  end

  def snapshots_by_civ_turn
    @game.event_log.by("snapshot", :civ).except(nil)
      .transform_values { |events| events.to_h { |e| [ e.turn, e.payload ] } }
  end

  def checkpoints_for(turns)
    max_turn = turns.keys.max
    return {} unless max_turn

    checkpoint_turns(max_turn).each_with_object({}) do |checkpoint, result|
      nearest_turn = turns.keys.select { |t| t <= checkpoint }.max
      next unless nearest_turn

      metrics = turns[nearest_turn].slice(*SNAPSHOT_METRICS)
      result[checkpoint] = metrics
        .merge(cost_multipliers(metrics["cities"]))
        .merge(army_quality(metrics))
    end
  end

  def checkpoint_turns(max_turn)
    checkpoints = (CHECKPOINT_INTERVAL..max_turn).step(CHECKPOINT_INTERVAL).to_a
    checkpoints << max_turn unless checkpoints.last == max_turn
    checkpoints
  end

  def army_quality(metrics)
    might, units, gold = metrics.values_at("military_might", "military_units", "gold")

    {
      "army_power" => ArmyComposition.army_power(might, gold),
      "power_per_unit" => ArmyComposition.power_per_unit(might, units, gold)
    }.compact
  end

  def cost_multipliers(cities)
    return {} unless cities

    cities_beyond_capital = [ cities - 1, 0 ].max

    {
      "tech_cost_multiplier" => (1 + TECH_COST_PER_CITY * cities_beyond_capital).round(3),
      "policy_cost_multiplier" => (1 + POLICY_COST_PER_CITY * cities_beyond_capital).round(3)
    }
  end

  def timelines_by_civ
    timeline = PlayerTimeline.for(@game)
    geometry = EmpireGeometry.for(@game)
    midpoint = game_midpoint

    civs.each_with_object({}) do |civ, result|
      result[civ] = {
        cities: timeline.cities(civ),
        techs: timeline.techs(civ),
        policies: timeline.policies(civ),
        religion: timeline.religion(civ),
        wars: timeline.wars(civ),
        irrelevance: timeline.irrelevance(civ),
        great_people: timeline.great_people(civ),
        great_people_born: timeline.great_people_born(civ),
        great_people_profile: great_people_profile(timeline, civ, midpoint),
        eras: timeline.eras(civ),
        golden_ages: timeline.golden_ages(civ),
        wonders: timeline.wonders(civ),
        city_states: timeline.city_states(civ),
        geometry: geometry.series(civ),
        city_count_mismatches: geometry.discrepancies(civ)
      }
    end
  end

  # Volume by kind (who specialized in what), and how each expend split
  # against the midpoint of the game as actually played - infrastructure
  # before it still had turns to pay for itself, consumption after is the
  # ordinary late-game use. EarlyGame's own boundary (Education/Metal
  # Casting) is the wrong reference here: a great person is typically the
  # product of policies and culture that arrive well past that milestone,
  # so almost every expend would land in "late" regardless of when it
  # actually happened - confirmed on india-diplo, where all six civs' early
  # game ends by turn 100 but expends run turns 61-183. The played-length
  # midpoint has no such gap, self-scales across game speeds, and needs no
  # per-civ join - every civ shares the same clock, unlike the boundary in
  # buffer-city, which was deliberately kept shared for the same reason.
  # Never a verdict on whether the split was the right call, only the facts
  # a report can weigh one against. Splitting the game itself in half is a
  # first hypothesis, not calibrated against a spread of real game lengths.
  def great_people_profile(timeline, civ, midpoint)
    expends = timeline.great_people(civ).select { |g| g[:fate] == :expended }

    {
      by_kind: expends.group_by { |g| PlayerTimeline::GREAT_PERSON_UNITS[g[:great_person]] }.transform_values(&:size),
      infrastructure: phase_split(expends, midpoint) { |g| INFRASTRUCTURE_ACTIONS.include?(g[:action]) },
      consumption: phase_split(expends, midpoint) { |g| CONSUMPTION_ACTIONS.include?(g[:action]) }
    }
  end

  def game_midpoint
    last_turn = @game.event_log.all.map(&:turn).max
    last_turn ? last_turn / 2.0 : 0
  end

  def phase_split(expends, midpoint)
    matches = expends.select { |g| yield(g) }
    { early: matches.count { |g| g[:turn] <= midpoint }, late: matches.count { |g| g[:turn] > midpoint } }
  end

  def cultural_by_civ
    timeline = InfluenceTimeline.for(@game)

    civs.each_with_object({}) do |civ, result|
      result[civ] = timeline.opponents(civ).each_with_object({}) do |opponent, matrix|
        latest = timeline.series(civ, opponent).last
        next unless latest

        matrix[opponent] = latest.slice(:points, :level, :trend)
      end
    end
  end

  # The digest speaks in ids, and the rules the LLM reads beside it speak
  # in names. This is the bridge, and it carries only the units this game
  # actually fielded.
  def unit_names
    UnitNames.for(@lekmod_version, root: @lekmod_root).glossary(logged_units)
  end

  def logged_units
    @game.game_events
         .pluck(Arel.sql("payload->>'unit'"), Arel.sql("payload->>'from'"), Arel.sql("payload->>'to'"))
         .flatten.compact.grep(/\AUNIT_/)
  end

  # Same bridge, for spies: a tenure exists for every spy the log ever
  # located, so it is the whole roster this game names.
  def spy_names
    SpyNames.for(@lekmod_version, root: @lekmod_root).glossary(logged_spy_ids)
  end

  def logged_spy_ids
    Espionage.for(@game).tenures.filter_map { |tenure| tenure[:spy] }
  end

  def key_moments
    detector = KeyMomentDetector.new(@game)

    {
      wars: detector.wars,
      buffer_city_losses: detector.buffer_city_losses,
      influence_level_reached: detector.influence_level_reached,
      cultural_victory_imminent: detector.cultural_victory_imminent,
      leader_changes: detector.leader_changes,
      era_leads: detector.era_leads,
      religion_foundings: detector.religion_foundings,
      pantheon_foundings: detector.pantheon_foundings,
      religion_enhancements: detector.religion_enhancements,
      reformations: detector.reformations,
      ideology_unlocks: detector.ideology_unlocks,
      ideology_adoptions: detector.ideology_adoptions,
      tenet_adoptions: detector.tenet_adoptions,
      policy_branch_adoptions: detector.policy_branch_adoptions,
      policy_branch_completions: detector.policy_branch_completions,
      army_power_swings: detector.army_power_swings,
      happiness_swings: detector.happiness_swings,
      unhappiness_periods: detector.unhappiness_periods,
      snowballs_score: detector.snowballs("score"),
      snowballs_population: detector.snowballs("population"),
      snowballs_science: detector.snowballs("science"),
      snowballs_culture: detector.snowballs("culture"),
      snowballs_production: detector.snowballs("production"),
      snowballs_faith: detector.snowballs("faith"),
      snowballs_gold_per_turn: detector.snowballs("gold_per_turn"),
      snowballs_food: detector.snowballs("food"),
      nuclear_detonations: detector.nuclear_detonations,
      city_state_ally_takeovers: detector.city_state_ally_takeovers,
      congress_host_changes: detector.congress_host_changes,
      united_nations_formed: detector.united_nations_formed,
      diplomatic_victory_imminent: detector.diplomatic_victory_imminent,
      resolutions_passed: detector.resolutions_passed,
      capital_control_changes: detector.capital_control_changes,
      apollo_completions: detector.apollo_completions,
      spaceship_part_assemblies: detector.spaceship_part_assemblies,
      science_victory_imminent: detector.science_victory_imminent,
      players_declared_irrelevant: detector.players_declared_irrelevant,
      wonder_races: detector.wonder_races,
      wonder_races_lost: detector.wonder_races_lost,
      city_state_conquered: detector.city_state_conquered,
      research_rushes: detector.research_rushes
    }
  end

  # Every contested world wonder in full, at its conclusion - the whole
  # race per record, not sampled per turn. Degrades like BufferCities when
  # the log carries no city snapshots to reconstruct a race from.
  def wonder_races
    races = WonderRaces.for(@game)
    return { applicable: false, reason: :no_city_snapshots } unless races.applicable?

    races.races
  end

  # Tenures and coups are whole-game facts and are carried once; everything
  # else splits per civ. Tenures land at conclusion only, never per turn - a
  # game the size of these produces tens of them, and the cross-cutting rule
  # applies if a longer one produces hundreds.
  def espionage
    spies = Espionage.for(@game)
    return { applicable: false, reason: :no_spy_events } unless spies.applicable?

    { by_civ: civs.index_with { |civ| espionage_for(spies, civ) },
      tenures: spies.tenures, coups: spies.coups }
  end

  def espionage_for(spies, civ)
    { capacity: spies.capacity(civ), missions: spies.missions(civ),
      losses: spies.losses(civ), counterspies: spies.counterspies(civ) }
  end

  def civs
    @game.players.order(:id).pluck(:civ)
  end

  # Fact rather than inference - embassies, open borders, friendship, pacts
  # and trade agreements. One entry per pair that ever held a tie; a pair
  # that never did is omitted rather than listed with nothing in it.
  def diplomatic_ties
    ties = DiplomaticTies.for(@game)
    return { applicable: false, reason: :no_tie_events } unless ties.applicable?

    { applicable: true, pairs: civs.combination(2).filter_map { |a, b| pair_ties(ties, a, b) } }
  end

  def pair_ties(ties, a, b)
    spans = ties.spans(a, b)
    { civs: [ a, b ], spans: spans } unless spans.empty?
  end

  # `one_sided` is a whole-game fact list, carried once rather than per civ -
  # same rule as espionage's tenures and coups.
  def trade_routes
    routes = TradeRoutes.for(@game)
    return { applicable: false, reason: :no_trade_route_events } unless routes.applicable?

    { applicable: true, by_civ: civs.index_with { |civ| trade_routes_for(routes, civ) }, one_sided: routes.one_sided }
  end

  def trade_routes_for(routes, civ)
    concurrency = routes.concurrency(civ).to_h { |point| [ point[:turn], point.slice(:count, :flagged) ] }
    { by_destination: routes.by_destination(civ), concurrency: sample_checkpoints(concurrency) }
  end

  # `applicable: false` when the log carries no yield_sources at all - two
  # of the five example logs predate the field. Only the yields a civ has
  # source data for are listed, each sampled at the same ~25-turn
  # checkpoints every other per-turn digest section uses.
  # Holds and inferred missionary/inquisitor uses are both already
  # per-civ - see Religion - so by_civ is a straight read, the same shape
  # espionage and trade_routes split into.
  def religion
    reconstruction = Religion.for(@game)
    return { applicable: false, reason: :no_conversions } unless reconstruction.applicable?

    { applicable: true, by_civ: civs.index_with { |civ| religion_for(reconstruction, civ) } }
  end

  def religion_for(reconstruction, civ)
    { holds: reconstruction.holds(civ), missionary_uses: reconstruction.missionary_uses(civ),
      inquisitor_uses: reconstruction.inquisitor_uses(civ) }
  end

  def yield_attribution
    attribution = YieldAttribution.for(@game)
    return { applicable: false, reason: :no_yield_sources } unless attribution.applicable?

    { applicable: true, by_civ: civs.index_with { |civ| yield_attribution_for(attribution, civ) } }
  end

  def yield_attribution_for(attribution, civ)
    attribution.yields(civ).index_with do |yield_name|
      sample_checkpoints(attribution.series(civ, yield_name).to_h { |point| [ point[:turn], point.except(:turn) ] })
    end
  end

  # `applicable` is false and nothing else is present for the two example
  # logs that predate resources[]. `deficits` is a computed mechanical fact
  # from the DLL's own combat rule, never an observed one - see
  # ResourceShortages.
  def resource_shortages
    shortages = ResourceShortages.new(@game, requirements: ResourceRequirements.for(@lekmod_version, root: @lekmod_root))
    return { applicable: false, reason: :no_resource_data } unless shortages.applicable?

    { applicable: true, by_civ: civs.index_with { |civ| shortages.deficits(civ) } }
  end

  # CvDeal is unreachable from Lua, so both lists here are inference from
  # `snapshot.resources[]`, never an observed deal - see Deals. Whole-game
  # lists, the same rule trade_routes' one_sided and espionage's tenures
  # already follow: neither is a per-turn-per-civ series, so neither needs
  # checkpoint sampling.
  def deals
    reconstruction = Deals.for(@game)
    return { applicable: false, reason: :no_resource_data } unless reconstruction.applicable?

    { applicable: true, matches: reconstruction.matches, unattributed_imports: reconstruction.unattributed_imports }
  end

  def lekmod
    LekmodReference.new(
      @lekmod_version, civs: civs, policy_ids: policy_ids, belief_ids: belief_ids,
      resolution_ids: resolution_ids, root: @lekmod_root
    ).call
  end

  def policy_ids
    @game.event_log.of_type("policy_adopted").filter_map { |e| e.payload["policy"] }.uniq
  end

  def resolution_ids
    congress_timeline.resolutions.map { |r| r[:resolution] }.uniq
  end

  def congress
    {
      host_history: congress_timeline.host_over_time,
      votes_needed: congress_timeline.votes_needed,
      delegates_by_civ: civs.each_with_object({}) { |civ, result| result[civ] = delegate_checkpoints(civ) },
      resolutions: congress_timeline.resolutions
    }
  end

  def victory_progress
    capitals = CapitalsTimeline.for(@game)
    spaceship = SpaceshipTimeline.for(@game)

    civs.each_with_object({}) do |civ, result|
      result[civ] = {
        capitals_held: sample_checkpoints(capitals.capitals_held(civ).to_h),
        spaceship: sample_checkpoints(spaceship.series(civ).to_h { |entry| [ entry[:turn], entry[:spaceship] ] })
      }
    end
  end

  def delegate_checkpoints(civ)
    points = congress_timeline.delegate_votes(civ)

    { votes: sample_checkpoints(points.to_h { |p| [ p[:turn], p[:votes] ] }),
      core_votes: sample_checkpoints(points.to_h { |p| [ p[:turn], p[:core_votes] ] }) }
  end

  def sample_checkpoints(turns)
    max_turn = turns.keys.max
    return {} unless max_turn

    checkpoint_turns(max_turn).each_with_object({}) do |checkpoint, result|
      nearest_turn = turns.keys.select { |t| t <= checkpoint }.max
      result[checkpoint] = turns[nearest_turn] if nearest_turn
    end
  end

  def congress_timeline = CongressTimeline.for(@game)

  # `unexplained` is the headline field of every entry here - see
  # CityStateStanding - and the prompt is taught to read it as a residual
  # covering gold gifts, quests and coups, none of them logged, rather than
  # crediting the whole of it to whichever cause happens to be visible.
  def city_states
    standing = CityStateStanding.for(@game)
    return { applicable: false, reason: :no_city_state_snapshots } unless standing.applicable?

    { applicable: true, traits: standing.traits, by_civ: civs.index_with { |civ| city_state_standing_for(standing, civ) } }
  end

  def city_state_standing_for(standing, civ)
    { alliances: standing.alliances(civ), attribution: attribution_by_city_state(standing, civ) }
  end

  def attribution_by_city_state(standing, civ)
    standing.traits.filter_map { |t|
      city_state = t[:city_state]
      next if standing.series(city_state, civ).empty?

      [ city_state, standing.attribution(city_state, civ) ]
    }.to_h
  end

  def belief_ids
    log = @game.event_log
    singular = %w[pantheon_founded reformation_added]
      .flat_map { |type| log.of_type(type) }.filter_map { |e| e.payload["belief"] }
    plural = %w[religion_founded religion_enhanced]
      .flat_map { |type| log.of_type(type) }.flat_map { |e| Array(e.payload["beliefs"]) }

    (singular + plural).uniq
  end
end
