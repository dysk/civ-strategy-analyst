class EspionageOperationsController < ApplicationController
  MISSION_KIND_LABELS = { tech_theft: "Tech Theft", election_rigging: "Election Rigging" }.freeze

  def show
    @game = Game.find(params[:game_id])
    @espionage = Espionage.for(@game)
    return unless @espionage.applicable?

    @capacity_rows = capacity_rows
    @tenure_histories = tenure_histories
    @mission_groups = mission_groups
    @garrison_rows = garrison_rows
    @coup_rows = @espionage.coups
  end

  private

  def capacity_rows
    @game.players.order(:id).map { |player| @espionage.capacity(player.civ).merge(civ: player.civ) }
  end

  def tenure_histories
    @game.players.order(:id).filter_map do |player|
      tenures = @espionage.tenures(player.civ)
      { civ: player.civ, tenures: tenures } if tenures.any?
    end
  end

  def mission_groups
    missions = @espionage.missions

    MISSION_KIND_LABELS.filter_map do |kind, label|
      rows = missions.select { |mission| mission[:kind] == kind }
      { kind: kind, label: label, missions: rows } if rows.any?
    end
  end

  def garrison_rows
    @game.players.order(:id).flat_map { |player| @espionage.counterspies(player.civ) }
  end
end
