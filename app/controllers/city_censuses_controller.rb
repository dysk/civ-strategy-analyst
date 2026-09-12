class CityCensusesController < ApplicationController
  # A city's value is snapshotted almost every turn it's held, so the full
  # series would run to hundreds of rows. Sampling reads the trend just as
  # well, as long as the last turn is always among the samples.
  SAMPLE_INTERVAL = 10

  def show
    @game = Game.find(params[:game_id])
    @histories = histories
  end

  private

  def histories
    census = CityCensus.for(@game)
    return [] unless census.applicable?

    value = CityValue.for(@game)
    last_turn = @game.game_events.maximum(:turn).to_i
    by_civ = census.cities(last_turn).group_by { |city| city[:civ] }

    @game.players.order(:id).filter_map do |player|
      cities = by_civ.fetch(player.civ, []).map do |city|
        { city: city[:city], series: sampled(value.series(city[:city])) }
      end

      { civ: player.civ, cities: cities } if cities.any?
    end
  end

  def sampled(series)
    last_turn = series.last&.dig(:turn)

    series.select { |entry| (entry[:turn] % SAMPLE_INTERVAL).zero? || entry[:turn] == last_turn }
  end
end
