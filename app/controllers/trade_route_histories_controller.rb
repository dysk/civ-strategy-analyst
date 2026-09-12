class TradeRouteHistoriesController < ApplicationController
  def show
    @game = Game.find(params[:game_id])
    @histories = histories
  end

  private

  def histories
    routes = TradeRoutes.for(@game)
    return [] unless routes.applicable?

    @game.players.order(:id).filter_map do |player|
      series = routes.concurrency(player.civ)
      { civ: player.civ, series: series } if series.any?
    end
  end
end
