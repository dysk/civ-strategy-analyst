class AnalysesController < ApplicationController
  before_action :set_game

  def index
    @analyses = @game.analyses.order(created_at: :desc)
  end

  def show
    @analysis = @game.analyses.find(params[:id])
  end

  def prompt
    @analysis = @game.analyses.find(params[:id])
  end

  private

  def set_game
    @game = Game.find(params[:game_id])
  end
end
