class CityStateHistoriesController < ApplicationController
  # A city-state snapshot fires almost every turn, so the raw series would
  # run to hundreds of rows per city-state/civ pair. Sampling reads the
  # trend just as well, as long as the last turn is always among the samples.
  SAMPLE_INTERVAL = 10

  def show
    @game = Game.find(params[:game_id])
    @histories = histories
  end

  private

  def histories
    standing = CityStateStanding.for(@game)
    return [] unless standing.applicable?

    civs = @game.players.order(:id).pluck(:civ)

    standing.traits.filter_map do |trait|
      city_state = trait[:city_state]
      civ_series = civ_series(standing, city_state, civs)
      { city_state: city_state, civs: civ_series } if civ_series.any?
    end
  end

  def civ_series(standing, city_state, civs)
    civs.filter_map do |civ|
      series = sampled(standing.series(city_state, civ))
      { civ: civ, series: series } if series.any?
    end
  end

  def sampled(series)
    last_turn = series.last&.dig(:turn)

    series.select { |entry| (entry[:turn] % SAMPLE_INTERVAL).zero? || entry[:turn] == last_turn }
  end
end
