class EmpireGeometriesController < ApplicationController
  def show
    @game = Game.find(params[:game_id])
    @map_bounds = MapBounds.new(@game)
    @histories = histories
  end

  private

  def histories
    geometry = EmpireGeometry.for(@game)

    @game.players.order(:id).filter_map do |player|
      series = geometry.series(player.civ)
      next if series.empty?

      { civ: player.civ, series: series, mismatches: geometry.discrepancies(player.civ) }
    end
  end
end
