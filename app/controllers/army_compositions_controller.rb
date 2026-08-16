class ArmyCompositionsController < ApplicationController
  # An army changes almost every turn, so the whole series would run to
  # hundreds of rows per civilization. Sampling reads the trend just as
  # well, as long as the last turn is always among the samples.
  SAMPLE_INTERVAL = 10

  def show
    @game = Game.find(params[:game_id])
    @histories = histories
  end

  private

  def histories
    armies = ArmyComposition.new(@game)

    @game.players.order(:id).filter_map do |player|
      series = sampled(armies.series(player.civ))
      { civ: player.civ, series: series } if series.any?
    end
  end

  def sampled(series)
    last_turn = series.last&.dig(:turn)

    series.select { |entry| (entry[:turn] % SAMPLE_INTERVAL).zero? || entry[:turn] == last_turn }
  end
end
