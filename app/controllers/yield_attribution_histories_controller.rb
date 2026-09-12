class YieldAttributionHistoriesController < ApplicationController
  # A snapshot fires almost every turn, so the raw series would run to
  # hundreds of rows per civ/yield pair. Sampling reads the trend just as
  # well, as long as the last turn is always among the samples.
  SAMPLE_INTERVAL = 10

  def show
    @game = Game.find(params[:game_id])
    @histories = histories
  end

  private

  def histories
    attribution = YieldAttribution.for(@game)
    return [] unless attribution.applicable?

    @game.players.order(:id).filter_map do |player|
      yields = yield_histories(attribution, player.civ)
      { civ: player.civ, yields: yields } if yields.any?
    end
  end

  def yield_histories(attribution, civ)
    attribution.yields(civ).filter_map do |yield_name|
      series = sampled(attribution.series(civ, yield_name))
      { yield_name: yield_name, series: series } if series.any?
    end
  end

  def sampled(series)
    last_turn = series.last&.dig(:turn)

    series.select { |entry| (entry[:turn] % SAMPLE_INTERVAL).zero? || entry[:turn] == last_turn }
  end
end
