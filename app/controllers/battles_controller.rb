class BattlesController < ApplicationController
  def show
    @game = Game.find(params[:game_id])
    @battles = KeyMomentDetector.new(@game).battles
  end
end
