class GamesController < ApplicationController
  SNOWBALL_METRICS = %w[score science population culture production faith gold_per_turn food].freeze
  CAPITAL_LAYOUT_HEIGHT = 600
  CAPITAL_LAYOUT_PADDING = 24
  CAPITAL_LAYOUT_CHARACTER_WIDTH = 8 # approx px per character at the major label's 14px font size
  CIV_COLOUR_SLOTS = 8 # data-viz reference categorical palette; hues live in application.css

  def index
    @games = Game.order(:id)
  end

  def show
    @game = Game.find(params[:id])
    @outcome = OutcomeResolver.new(@game).call
    @standings = MetricSeries.for(@game).final_ranking("score")
    @early_game_rows = early_game.series.values
    @early_game_deadline_turn = early_game.deadline_turn
    @key_moment_groups = key_moment_groups
    @map_bounds = MapBounds.for(@game)
    @geometry_rows = geometry_rows
    @capital_distances = capital_distances
    @buffer_cities = BufferCities.for(@game).call
    @wonder_races = wonder_races_view
    @capital_layout_height = CAPITAL_LAYOUT_HEIGHT
    @capital_layout_width = capital_layout_width
    @capital_positions = map_layout[:capitals]
    @buffer_positions = map_layout[:buffers]
    @corridor_segments = map_layout[:corridors]
    @army_rows = army_rows
    @cultural_rows = cultural_rows
    @congress_summary = congress_summary
    @victory_progress_rows = victory_progress_rows
    @espionage_rows = espionage_rows
    @latest_analysis = @game.analyses.order(created_at: :desc).first
  end

  private

  def early_game = EarlyGame.for(@game)

  # One row per losing contender, plus the winner's own row, so a wonder
  # with two rivals reads top to bottom.
  def wonder_races_view
    races = WonderRaces.for(@game)
    return { applicable: false } unless races.applicable?

    { applicable: true, races: races.races }
  end

  # Kinds of moment that tell one story share a section, each keeping its own
  # list inside it. Empty sections and empty lists are left out.
  def key_moment_groups
    moments = KeyMomentDetector.new(@game)

    [
      [ "Wars", { nil => moments.wars } ],
      [ "Buffer Cities Lost", { nil => moments.buffer_city_losses } ],
      [ "Players Declared Irrelevant", { nil => moments.players_declared_irrelevant } ],
      [ "Leader Changes", { nil => moments.leader_changes } ],
      [ "Era Leads", { nil => moments.era_leads } ],
      [ "Wonder Races", { nil => merge_by_turn(moments.wonder_races, moments.wonder_races_lost) } ],
      [ "Religion", { "Pantheon Foundings" => moments.pantheon_foundings,
                      "Religion Foundings" => moments.religion_foundings,
                      "Religion Enhancements" => moments.religion_enhancements,
                      "Reformations" => moments.reformations } ],
      [ "Policies and Ideologies", { "Ideology Unlocks" => moments.ideology_unlocks,
                                     "Policy Branch Adoptions" => moments.policy_branch_adoptions,
                                     "Policy Branch Completions" => moments.policy_branch_completions } ],
      [ "Ideology Adoptions", { nil => moments.ideology_adoptions } ],
      [ "Tenet Adoptions", { nil => moments.tenet_adoptions } ],
      [ "Army Power Swings", { nil => moments.army_power_swings } ],
      [ "Happiness", { "Happiness Swings" => moments.happiness_swings,
                       "Unhappiness Periods" => moments.unhappiness_periods } ],
      [ "Snowballs", snowballs_by_metric(moments) ],
      [ "Nuclear Detonations", { nil => moments.nuclear_detonations } ],
      [ "City-State Ally Takeovers", { nil => moments.city_state_ally_takeovers } ],
      [ "Cultural Standing", { nil => merge_by_turn(moments.influence_level_reached, moments.cultural_victory_imminent) } ],
      [ "World Congress", { nil => merge_by_turn(moments.congress_host_changes, moments.united_nations_formed,
                                                  moments.diplomatic_victory_imminent, moments.resolutions_passed) } ],
      [ "Victory Progress", { nil => merge_by_turn(moments.capital_control_changes, moments.apollo_completions,
                                                    moments.spaceship_part_assemblies, moments.science_victory_imminent) } ]
    ].filter_map { |title, lists| key_moment_group(title, lists) }
  end

  def key_moment_group(title, lists)
    filled = lists.filter_map { |list_title, moments| { title: list_title, moments: moments } if moments.any? }
    return if filled.empty?

    { title: title, count: filled.sum { |list| list[:moments].size }, lists: filled }
  end

  def merge_by_turn(*lists)
    lists.flatten(1).sort_by { |moment| moment[:turn] }
  end

  # The heading names the metric, so the moments themselves need not.
  def snowballs_by_metric(moments)
    SNOWBALL_METRICS.index_with { |metric| moments.snowballs(metric) }.transform_keys(&:titleize)
  end

  def army_rows
    armies = ArmyComposition.for(@game)

    @game.players.order(:id).filter_map do |player|
      armies.latest(player.civ)&.merge(civ: player.civ)
    end
  end

  # Closest neighbours first: who had to worry about whom is the reason to
  # look at this table at all.
  def capital_distances
    CapitalProximity.for(@game).distances.sort_by { |pair| pair[:distance] }
  end

  # Canvas height is fixed; width follows the map's own aspect ratio so a
  # wide map isn't squeezed into a square. Maps are rarely square.
  def capital_layout_width
    width, height = @map_bounds.width, @map_bounds.height
    return CAPITAL_LAYOUT_HEIGHT unless width && height

    (CAPITAL_LAYOUT_HEIGHT * width / height.to_f).round
  end

  # Capitals, city-states and buffer cities on one canvas, plus a line down
  # each contested corridor. The three lists share a single projection so
  # relative distance holds across all of them. Built once.
  def map_layout
    @map_layout ||= build_map_layout
  end

  def build_map_layout
    anchors = layout_capitals
    return { capitals: [], buffers: [], corridors: [] } if anchors.empty?

    buffers = buffer_city_points
    project = plot_projector(anchors + buffers)

    {
      capitals: anchors.map { |anchor| place(anchor, project).merge(major: anchor[:major]) },
      buffers: buffers.map { |buffer| place(buffer, project).merge(city: buffer[:city]) },
      corridors: corridor_endpoints.map { |from, to| segment(from, to, project) }
    }
  end

  def place(point, project)
    cx, cy = project.call(point[:x], point[:y])
    { civ: point[:civ], colour_slot: colour_slot(point[:civ]), cx: cx, cy: cy }
  end

  def segment(from, to, project)
    x1, y1 = project.call(*from)
    x2, y2 = project.call(*to)
    { x1: x1, y1: y1, x2: x2, y2: y2 }
  end

  # One shared transform from map plots to canvas pixels: the same scale on
  # both axes so relative distance survives, the shorter axis centered
  # rather than stretched, and horizontal padding wide enough for half the
  # widest label so a centered label doesn't clip the canvas edge.
  def plot_projector(points)
    xs = points.map { |point| point[:x] }
    ys = points.map { |point| point[:y] }
    min_x, min_y = xs.min, ys.min
    padding_x = points.map { |point| label_half_width(point[:city] || point[:civ]) }.max
    drawable_width = @capital_layout_width - 2 * padding_x
    drawable_height = CAPITAL_LAYOUT_HEIGHT - 2 * CAPITAL_LAYOUT_PADDING
    x_span = [ xs.max - min_x, 1 ].max
    y_span = [ ys.max - min_y, 1 ].max
    scale = [ drawable_width / x_span.to_f, drawable_height / y_span.to_f ].min
    x_offset = padding_x + (drawable_width - x_span * scale) / 2
    y_offset = CAPITAL_LAYOUT_PADDING + (drawable_height - y_span * scale) / 2

    lambda do |x, y|
      [ (x_offset + (x - min_x) * scale).round(2),
        (CAPITAL_LAYOUT_HEIGHT - y_offset - (y - min_y) * scale).round(2) ]
    end
  end

  # The city-states are drawn too: they are the ground a player's expansion
  # had to go round. `major` is what tells the two apart on the canvas.
  def layout_capitals
    proximity = CapitalProximity.for(@game)

    proximity.capitals.values.map { |capital| capital.merge(major: true) } +
      proximity.city_state_capitals.values.map { |capital| capital.merge(major: false) }
  end

  # A civ's buffer cities as plots, deduped: one city can buffer two rivals
  # and appears once per pair in the digest.
  def buffer_city_points
    return [] unless @buffer_cities[:applicable]

    @buffer_cities[:pairs].flat_map do |pair|
      pair[:buffers].filter_map do |civ, buffer|
        { civ: civ, city: buffer[:city], x: buffer[:x], y: buffer[:y] } if buffer
      end
    end.uniq { |point| [ point[:civ], point[:x], point[:y] ] }
  end

  # Endpoints of the line down each contested corridor - the two capitals of
  # every neighbouring pair.
  def corridor_endpoints
    return [] unless @buffer_cities[:applicable]

    capitals = CapitalProximity.for(@game).capitals
    @buffer_cities[:pairs].filter_map do |pair|
      from, to = pair[:civs].map { |civ| capitals[civ] }
      [ [ from[:x], from[:y] ], [ to[:x], to[:y] ] ] if from && to
    end
  end

  # Which palette slot a civ draws from: its seat order, capped at the
  # palette size so an unusually large game falls back to the neutral fill
  # rather than cycling hues. `nil` for city-states.
  def colour_slot(civ)
    seat = major_civs.index(civ)
    seat if seat && seat < CIV_COLOUR_SLOTS
  end

  def major_civs
    @major_civs ||= @game.players.order(:id).map(&:civ)
  end

  def label_half_width(label)
    CAPITAL_LAYOUT_PADDING + label.length * CAPITAL_LAYOUT_CHARACTER_WIDTH / 2.0
  end

  def cultural_rows
    metrics = MetricSeries.for(@game)
    influence = InfluenceTimeline.for(@game)

    @game.players.order(:id).filter_map do |player|
      tourism = metrics.values("tourism", player.civ).last&.last
      civs_influential_on = metrics.values("civs_influential_on", player.civ).last&.last
      next if tourism.nil? && civs_influential_on.nil?

      influential_on = influence.opponents(player.civ).select do |opponent|
        level = influence.series(player.civ, opponent).last&.dig(:level)
        KeyMomentDetector::INFLUENCE_TARGET_LEVELS.include?(level)
      end

      { civ: player.civ, tourism: tourism, civs_influential_on: civs_influential_on, influential_on: influential_on }
    end
  end

  def congress_summary
    timeline = CongressTimeline.for(@game)

    rows = @game.players.order(:id).filter_map do |player|
      votes = timeline.delegate_votes(player.civ).last&.last
      next unless votes

      { civ: player.civ, votes: votes }
    end
    return if rows.empty?

    { host: timeline.host_over_time.last&.dig(:host), votes_needed: timeline.votes_needed, rows: rows }
  end

  def victory_progress_rows
    capitals = CapitalsTimeline.for(@game)
    spaceship = SpaceshipTimeline.for(@game)

    @game.players.order(:id).filter_map do |player|
      capitals_held = capitals.latest(player.civ)&.[](:capitals_held)
      parts_assembled = spaceship.latest(player.civ)&.[](:parts_assembled)
      next if capitals_held.nil? && parts_assembled.nil?

      { civ: player.civ, capitals_held: capitals_held, parts_assembled: parts_assembled }
    end
  end

  def espionage_rows
    espionage = Espionage.for(@game)
    return [] unless espionage.applicable?

    @game.players.order(:id).map do |player|
      capacity = espionage.capacity(player.civ)
      { civ: player.civ, made: capacity[:created], lost: capacity[:killed],
        missions: espionage.missions(player.civ).size, garrisoned: espionage.counterspies(player.civ).any? }
    end
  end

  # The empire's shape as it stands, plus the first turn its city count
  # stopped adding up - after which the shape is only approximate.
  def geometry_rows
    geometry = EmpireGeometry.new(@game, grid: HexGrid.new(width: @map_bounds.width))

    @game.players.order(:id).filter_map do |player|
      shape = geometry.series(player.civ).last
      shape&.merge(civ: player.civ, mismatch: geometry.discrepancies(player.civ).first)
    end
  end
end
