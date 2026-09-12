class GameProjectionsController < ApplicationController
  SNOWBALL_METRICS = %w[score science population culture production faith gold_per_turn food].freeze

  def show
    @game = Game.find(params[:game_id])
    @map_bounds = MapBounds.for(@game)
    @capital_distances = capital_distances
    @buffer_cities = BufferCities.for(@game).call
    @geometry_rows = geometry_rows
    @early_game_rows = early_game.series.values
    @early_game_deadline_turn = early_game.deadline_turn
    @key_moment_groups = key_moment_groups
    @wonder_races = wonder_races_view
    @army_rows = army_rows
    @cultural_rows = cultural_rows
    @congress_summary = congress_summary
    @victory_progress_rows = victory_progress_rows
    @espionage_rows = espionage_rows
    @diplomatic_tie_rows = diplomatic_tie_rows
    @trade_route_destination_rows = trade_route_destination_rows
    @trade_route_one_sided_rows = trade_route_one_sided_rows
    @religion_hold_rows = religion_hold_rows
    @religion_use_rows = religion_use_rows
    @yield_attribution_rows = yield_attribution_rows
    @resource_shortage_rows = resource_shortage_rows
    @deal_match_rows = deal_match_rows
    @deal_unattributed_import_rows = deal_unattributed_import_rows
    @city_state_trait_rows = city_state_trait_rows
    @city_state_alliance_rows = city_state_alliance_rows
    @city_state_attribution_rows = city_state_attribution_rows
  end

  private

  # Closest neighbours first: who had to worry about whom is the reason to
  # look at this table at all.
  def capital_distances
    CapitalProximity.for(@game).distances.sort_by { |pair| pair[:distance] }
  end

  # The empire's shape as it stands, plus the first turn its city count
  # stopped adding up - after which the shape is only approximate.
  def geometry_rows
    geometry = EmpireGeometry.new(@game, grid: HexGrid.new(width: @map_bounds.width))

    @game.players.order(:id).filter_map do |player|
      shape = geometry.series(player.civ).last
      shape&.merge(civ: player.civ, mismatch: geometry.discrepancies(player.civ).first)
    end
  end

  def early_game = EarlyGame.for(@game)

  # One row per losing contender, plus the winner's own row, so a wonder
  # with two rivals reads top to bottom.
  def wonder_races_view
    races = WonderRaces.for(@game)
    return { applicable: false } unless races.applicable?

    { applicable: true, races: races.races }
  end

  # Kinds of moment that tell one story share a section, each keeping its own
  # list inside it. Empty sections and empty lists are left out.
  def key_moment_groups
    moments = KeyMomentDetector.new(@game)

    [
      [ "Wars", { nil => moments.wars } ],
      [ "Buffer Cities Lost", { nil => moments.buffer_city_losses } ],
      [ "Players Declared Irrelevant", { nil => moments.players_declared_irrelevant } ],
      [ "Leader Changes", { nil => moments.leader_changes } ],
      [ "Era Leads", { nil => moments.era_leads } ],
      [ "Wonder Races", { nil => merge_by_turn(moments.wonder_races, moments.wonder_races_lost) } ],
      [ "Religion", { "Pantheon Foundings" => moments.pantheon_foundings,
                      "Religion Foundings" => moments.religion_foundings,
                      "Religion Enhancements" => moments.religion_enhancements,
                      "Reformations" => moments.reformations } ],
      [ "Policies and Ideologies", { "Ideology Unlocks" => moments.ideology_unlocks,
                                     "Policy Branch Adoptions" => moments.policy_branch_adoptions,
                                     "Policy Branch Completions" => moments.policy_branch_completions } ],
      [ "Ideology Adoptions", { nil => moments.ideology_adoptions } ],
      [ "Tenet Adoptions", { nil => moments.tenet_adoptions } ],
      [ "Army Power Swings", { nil => moments.army_power_swings } ],
      [ "Happiness", { "Happiness Swings" => moments.happiness_swings,
                       "Unhappiness Periods" => moments.unhappiness_periods } ],
      [ "Snowballs", snowballs_by_metric(moments) ],
      [ "Nuclear Detonations", { nil => moments.nuclear_detonations } ],
      [ "City-State Ally Takeovers", { nil => moments.city_state_ally_takeovers } ],
      [ "Cultural Standing", { nil => merge_by_turn(moments.influence_level_reached, moments.cultural_victory_imminent) } ],
      [ "World Congress", { nil => merge_by_turn(moments.congress_host_changes, moments.united_nations_formed,
                                                  moments.diplomatic_victory_imminent, moments.resolutions_passed) } ],
      [ "Victory Progress", { nil => merge_by_turn(moments.capital_control_changes, moments.apollo_completions,
                                                    moments.spaceship_part_assemblies, moments.science_victory_imminent) } ]
    ].filter_map { |title, lists| key_moment_group(title, lists) }
  end

  def key_moment_group(title, lists)
    filled = lists.filter_map { |list_title, moments| { title: list_title, moments: moments } if moments.any? }
    return if filled.empty?

    { title: title, count: filled.sum { |list| list[:moments].size }, lists: filled }
  end

  def merge_by_turn(*lists)
    lists.flatten(1).sort_by { |moment| moment[:turn] }
  end

  # The heading names the metric, so the moments themselves need not.
  def snowballs_by_metric(moments)
    SNOWBALL_METRICS.index_with { |metric| moments.snowballs(metric) }.transform_keys(&:titleize)
  end

  def army_rows
    armies = ArmyComposition.for(@game)

    @game.players.order(:id).filter_map do |player|
      armies.latest(player.civ)&.merge(civ: player.civ)
    end
  end

  def cultural_rows
    metrics = MetricSeries.for(@game)
    influence = InfluenceTimeline.for(@game)

    @game.players.order(:id).filter_map do |player|
      tourism = metrics.values("tourism", player.civ).last&.last
      civs_influential_on = metrics.values("civs_influential_on", player.civ).last&.last
      next if tourism.nil? && civs_influential_on.nil?

      influential_on = influence.opponents(player.civ).select do |opponent|
        level = influence.series(player.civ, opponent).last&.dig(:level)
        KeyMomentDetector::INFLUENCE_TARGET_LEVELS.include?(level)
      end

      { civ: player.civ, tourism: tourism, civs_influential_on: civs_influential_on, influential_on: influential_on }
    end
  end

  def congress_summary
    timeline = CongressTimeline.for(@game)

    rows = @game.players.order(:id).filter_map do |player|
      votes = timeline.delegate_votes(player.civ).last&.[](:votes)
      next unless votes

      { civ: player.civ, votes: votes }
    end
    return if rows.empty?

    { host: timeline.host_over_time.last&.dig(:host), votes_needed: timeline.votes_needed, rows: rows }
  end

  def victory_progress_rows
    capitals = CapitalsTimeline.for(@game)
    spaceship = SpaceshipTimeline.for(@game)

    @game.players.order(:id).filter_map do |player|
      capitals_held = capitals.latest(player.civ)&.[](:capitals_held)
      parts_assembled = spaceship.latest(player.civ)&.[](:parts_assembled)
      next if capitals_held.nil? && parts_assembled.nil?

      { civ: player.civ, capitals_held: capitals_held, parts_assembled: parts_assembled }
    end
  end

  def espionage_rows
    espionage = Espionage.for(@game)
    return [] unless espionage.applicable?

    @game.players.order(:id).map do |player|
      capacity = espionage.capacity(player.civ)
      { civ: player.civ, made: capacity[:created], lost: capacity[:killed],
        missions: espionage.missions(player.civ).size, garrisoned: espionage.counterspies(player.civ).any? }
    end
  end

  # Every tie ever held between any two civs, oldest first - the same
  # ground DigestBuilder covers pair by pair for the prompt.
  def diplomatic_tie_rows
    ties = DiplomaticTies.for(@game)
    return [] unless ties.applicable?

    civs.combination(2).flat_map { |a, b| ties.spans(a, b).map { |span| span.merge(civs: [ a, b ]) } }
      .sort_by { |row| row[:from_turn] }
  end

  def trade_route_destination_rows
    routes = TradeRoutes.for(@game)
    return [] unless routes.applicable?

    civs.map do |civ|
      destination = routes.by_destination(civ)
      { civ: civ, own_food: destination[:own][:food], own_production: destination[:own][:production],
        city_state: destination[:city_state], major: destination[:major] }
    end
  end

  # A civ feeding a rival's science or tourism without ever seeing a return -
  # invisible unless the two sides of the same route are put side by side.
  def trade_route_one_sided_rows
    routes = TradeRoutes.for(@game)
    return [] unless routes.applicable?

    routes.one_sided.sort_by { |row| row[:turn] }
  end

  def religion_hold_rows
    religion = Religion.for(@game)
    return [] unless religion.applicable?

    religion.holds
  end

  def religion_use_rows
    religion = Religion.for(@game)
    return [] unless religion.applicable?

    civs.map do |civ|
      { civ: civ, missionary_uses: religion.missionary_uses(civ).size, inquisitor_uses: religion.inquisitor_uses(civ).size }
    end
  end

  # Latest checkpoint per (civ, yield) a civ has source data for - the same
  # slice DigestBuilder samples, at its most recent point.
  def yield_attribution_rows
    attribution = YieldAttribution.for(@game)
    return [] unless attribution.applicable?

    civs.flat_map do |civ|
      attribution.yields(civ).filter_map do |yield_name|
        latest = attribution.series(civ, yield_name).max_by { |point| point[:turn] }
        latest&.merge(civ: civ, yield_name: yield_name)
      end
    end
  end

  def resource_shortage_rows
    shortages = ResourceShortages.for(@game)
    return [] unless shortages.applicable?

    civs.flat_map { |civ| shortages.deficits(civ).map { |deficit| deficit.merge(civ: civ) } }
      .sort_by { |row| row[:turn] }
  end

  def deal_match_rows
    deals = Deals.for(@game)
    return [] unless deals.applicable?

    deals.matches
  end

  def deal_unattributed_import_rows
    deals = Deals.for(@game)
    return [] unless deals.applicable?

    deals.unattributed_imports.sort_by { |row| row[:turn] }
  end

  def city_state_trait_rows
    standing = CityStateStanding.for(@game)
    return [] unless standing.applicable?

    standing.traits
  end

  def city_state_alliance_rows
    standing = CityStateStanding.for(@game)
    return [] unless standing.applicable?

    civs.flat_map { |civ| standing.alliances(civ).map { |span| span.merge(civ: civ) } }.sort_by { |row| row[:from_turn] }
  end

  # Same guard DigestBuilder's attribution_by_city_state applies: only a
  # civ/city-state pair with a standing series at all gets an attribution row.
  def city_state_attribution_rows
    standing = CityStateStanding.for(@game)
    return [] unless standing.applicable?

    civs.flat_map do |civ|
      standing.traits.filter_map do |trait|
        city_state = trait[:city_state]
        next if standing.series(city_state, civ).empty?

        standing.attribution(city_state, civ).merge(civ: civ, city_state: city_state)
      end
    end
  end

  def civs = @civs ||= @game.players.order(:id).pluck(:civ)
end
