class GamesController < ApplicationController
  def index
    @games = Game.order(:id)
  end

  def show
    @game = Game.find(params[:id])
    @outcome = OutcomeResolver.new(@game, winner_civ: @game.winner_civ, victory_type: @game.victory_type).call
    @standings = MetricSeries.new(@game).final_ranking("score")
    @key_moments = KeyMomentDetector.new(@game)
    @map_bounds = MapBounds.new(@game)
    @geometry_rows = geometry_rows
    @latest_analysis = @game.analyses.order(created_at: :desc).first
  end

  private

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
