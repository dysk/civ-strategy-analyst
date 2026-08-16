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
      [ "Technology Rushes", { nil => moments.rush_tech_leads } ],
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
      [ "City-State Ally Takeovers", { nil => moments.city_state_ally_takeovers } ]
    ].filter_map { |title, lists| key_moment_group(title, lists) }
  end

  def key_moment_group(title, lists)
    filled = lists.filter_map { |list_title, moments| { title: list_title, moments: moments } if moments.any? }
    return if filled.empty?

    { title: title, count: filled.sum { |list| list[:moments].size }, lists: filled }
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
