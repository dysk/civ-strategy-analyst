class CulturalStandingsController < ApplicationController
  def show
    @game = Game.find(params[:game_id])
    @histories = histories
  end

  private

  def histories
    metrics = MetricSeries.new(@game)
    influence = InfluenceTimeline.new(@game)

    @game.players.order(:id).filter_map do |player|
      tourism_series = tourism_series(metrics, player.civ)
      influence_rows = influence_rows(influence, player.civ)
      next if tourism_series.empty? && influence_rows.empty?

      { civ: player.civ, tourism_series: tourism_series, influence_rows: influence_rows }
    end
  end

  def tourism_series(metrics, civ)
    tourism = metrics.values("tourism", civ).to_h
    civs_influential_on = metrics.values("civs_influential_on", civ).to_h

    (tourism.keys | civs_influential_on.keys).sort.filter_map do |turn|
      value, influential_on = tourism[turn], civs_influential_on[turn]
      next if value.nil? && influential_on.nil?

      { turn: turn, tourism: value, civs_influential_on: influential_on }
    end
  end

  def influence_rows(influence, civ)
    influence.opponents(civ).flat_map do |opponent|
      influence.series(civ, opponent).map { |entry| entry.merge(opponent: opponent) }
    end.sort_by { |entry| entry[:turn] }
  end
end
