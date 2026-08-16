class CongressHistoriesController < ApplicationController
  def show
    @game = Game.find(params[:game_id])
    @timeline = CongressTimeline.new(@game)
    @sessions = @timeline.host_over_time
    @delegate_histories = delegate_histories
    @resolutions = @timeline.resolutions.sort_by { |r| r[:proposed_turn] }
  end

  private

  def delegate_histories
    @game.players.order(:id).filter_map do |player|
      series = @timeline.delegate_votes(player.civ)
      { civ: player.civ, series: series } if series.any?
    end
  end
end
