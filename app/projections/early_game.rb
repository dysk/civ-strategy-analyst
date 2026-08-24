# When each civ leaves the development phase: the first turn it holds both
# Education and Metal Casting with one of the two buildings they unlock
# standing, or the deadline, whichever comes first.
class EarlyGame
  extend Projection

  DEADLINE_STANDARD_TURNS = 150
  MILESTONES = [
    { tech: "TECH_EDUCATION",     building: "BUILDING_WORKSHOP" },
    { tech: "TECH_METAL_CASTING", building: "BUILDING_UNIVERSITY" }
  ].freeze

  # A wonder that hands its city the milestone building for free. The DLL
  # grants those without firing CityConstructed, so the building never
  # reaches the log and the wonder is the only evidence it is standing.
  GRANTED_BY = { "BUILDING_UNIVERSITY" => %w[BUILDING_ANGKOR_WAT] }.freeze

  # The unique buildings civs get in place of a milestone building. The log
  # names the building type, so a civ that never builds the base type still
  # holds its building class.
  REPLACED_BY = {
    "BUILDING_WORKSHOP"   => %w[BUILDING_LONGHOUSE BUILDING_CORALSHOP],
    "BUILDING_UNIVERSITY" => %w[BUILDING_WAT BUILDING_AYYUBIDS_UNIVERSITY]
  }.freeze

  def initialize(game)
    @game = game
    @timeline = PlayerTimeline.for(game)
    @last_turn = game.event_log.all.map(&:turn).max
  end

  def deadline_turn
    @deadline_turn ||= GameSpeed.for(@game).turns(DEADLINE_STANDARD_TURNS)
  end

  def for_civ(civ)
    reached = earliest_milestone(civ)

    { civ: civ, **boundary(reached), **reached.except(:turn), deadline_turn: deadline_turn }
  end

  def series
    @game.players.order(:id).to_h { |player| [ player.civ, for_civ(player.civ) ] }
  end

  private

  # A milestone past the deadline is still reported, it just no longer sets
  # the boundary. We never report a boundary past the end of the data.
  def boundary(reached)
    milestone_turn = reached[:turn]

    if milestone_turn && milestone_turn <= deadline_turn
      { end_turn: milestone_turn, reason: :milestone, milestone_turn: milestone_turn }
    elsif @last_turn && @last_turn < deadline_turn
      { end_turn: @last_turn, reason: :game_end, milestone_turn: milestone_turn }
    else
      { end_turn: deadline_turn, reason: :deadline, milestone_turn: milestone_turn }
    end
  end

  def earliest_milestone(civ)
    candidates = MILESTONES.filter_map { |milestone| reach(civ, milestone) }

    candidates.min_by { |candidate| candidate[:turn] } ||
      { milestone: nil, turn: nil, tech_turn: nil, building_turn: nil }
  end

  def reach(civ, milestone)
    tech_turn = first_turn(@timeline.techs(civ), :tech, [ milestone[:tech] ])
    building_turn = first_turn(@timeline.buildings(civ), :building, evidence_of(milestone[:building]))
    return if tech_turn.nil? || building_turn.nil?

    { milestone: milestone, turn: [ tech_turn, building_turn ].max,
      tech_turn: tech_turn, building_turn: building_turn }
  end

  def evidence_of(building)
    [ building, *REPLACED_BY[building], *GRANTED_BY[building] ]
  end

  def first_turn(entries, key, names)
    entries.find { |entry| names.include?(entry[key]) }&.fetch(:turn)
  end
end
