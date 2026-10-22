class ChroniclesController < ApplicationController
  before_action :set_game

  def show
    @chronicle = @game.chronicles.find(params[:id])
  end

  def prompt
    @chronicle = @game.chronicles.find(params[:id])
  end

  def digest
    @chronicle = @game.chronicles.find(params[:id])
  end

  private

  def set_game
    @game = Game.find(params[:game_id])
  end
end
