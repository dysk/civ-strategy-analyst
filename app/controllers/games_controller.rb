class GamesController < ApplicationController
  def index
    @games = Game.order(:id)
  end

  def show
    @game = Game.find(params[:id])
    @outcome = OutcomeResolver.new(@game, winner_civ: @game.winner_civ, victory_type: @game.victory_type).call
    @standings = MetricSeries.new(@game).final_ranking("score")
    @key_moments = KeyMomentDetector.new(@game)
    @latest_analysis = @game.analyses.order(created_at: :desc).first
  end
end
