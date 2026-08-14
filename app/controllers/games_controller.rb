class GamesController < ApplicationController
  def index
    @games = Game.order(:id)
  end

  def show
    @game = Game.find(params[:id])
    @outcome = OutcomeResolver.new(@game, winner_civ: @game.winner_civ, victory_type: @game.victory_type).call
    @standings = final_standings(@game)
    @key_moments = KeyMomentDetector.new(@game)
    @latest_analysis = @game.analyses.order(created_at: :desc).first
  end

  private

  def final_standings(game)
    ranking = MetricSeries.new(game).ranking("score")
    last_turn = ranking.keys.max
    last_turn ? ranking[last_turn] : []
  end
end
