class VictoryProgressHistoriesController < ApplicationController
  def show
    @game = Game.find(params[:game_id])
    @histories = histories
  end

  private

  def histories
    capitals = CapitalsTimeline.new(@game)
    spaceship = SpaceshipTimeline.new(@game)

    @game.players.order(:id).filter_map do |player|
      capitals_series = capitals.series(player.civ)
      spaceship_series = spaceship.series(player.civ)
      next if capitals_series.empty? && spaceship_series.empty?

      { civ: player.civ, capitals_series: capitals_series, spaceship_series: spaceship_series }
    end
  end
end
