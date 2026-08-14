class GameEventsController < ApplicationController
  PER_PAGE = 50

  def index
    @game = Game.find(params[:game_id])
    @page = (params[:page] || 1).to_i
    @total_pages = (@game.game_events.count / PER_PAGE.to_f).ceil
    @game_events = @game.game_events.order(:seq).limit(PER_PAGE).offset((@page - 1) * PER_PAGE)
  end
end
