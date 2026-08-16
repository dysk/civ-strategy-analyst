class GamesController < ApplicationController
  SNOWBALL_METRICS = %w[score science population culture].freeze

  def index
    @games = Game.order(:id)
  end

  def show
    @game = Game.find(params[:id])
    @outcome = OutcomeResolver.new(@game, winner_civ: @game.winner_civ, victory_type: @game.victory_type).call
    @standings = MetricSeries.new(@game).final_ranking("score")
    @key_moment_groups = key_moment_groups
    @map_bounds = MapBounds.new(@game)
    @geometry_rows = geometry_rows
    @army_rows = army_rows
    @cultural_rows = cultural_rows
    @congress_summary = congress_summary
    @victory_progress_rows = victory_progress_rows
    @latest_analysis = @game.analyses.order(created_at: :desc).first
  end

  private

  # Kinds of moment that tell one story share a section, each keeping its own
  # list inside it. Empty sections and empty lists are left out.
  def key_moment_groups
    moments = KeyMomentDetector.new(@game)

    [
      [ "Wars", { nil => moments.wars } ],
      [ "Leader Changes", { nil => moments.leader_changes } ],
      [ "Era Leads", { nil => moments.era_leads } ],
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
    SNOWBALL_METRICS.index_with { |metric| moments.snowballs(metric) }.transform_keys(&:capitalize)
  end

  def army_rows
    armies = ArmyComposition.new(@game)

    @game.players.order(:id).filter_map do |player|
      armies.latest(player.civ)&.merge(civ: player.civ)
    end
  end

  def cultural_rows
    metrics = MetricSeries.new(@game)
    influence = InfluenceTimeline.new(@game)

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
    timeline = CongressTimeline.new(@game)

    rows = @game.players.order(:id).filter_map do |player|
      votes = timeline.delegate_votes(player.civ).last&.last
      next unless votes

      { civ: player.civ, votes: votes }
    end
    return if rows.empty?

    { host: timeline.host_over_time.last&.dig(:host), votes_needed: timeline.votes_needed, rows: rows }
  end

  def victory_progress_rows
    capitals = CapitalsTimeline.new(@game)
    spaceship = SpaceshipTimeline.new(@game)

    @game.players.order(:id).filter_map do |player|
      capitals_held = capitals.latest(player.civ)&.[](:capitals_held)
      parts_assembled = spaceship.latest(player.civ)&.[](:parts_assembled)
      next if capitals_held.nil? && parts_assembled.nil?

      { civ: player.civ, capitals_held: capitals_held, parts_assembled: parts_assembled }
    end
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
end
