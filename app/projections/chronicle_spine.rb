# The skeleton of a chronicle: which turns earned an entry, which events are
# only texture around them, and where the years passed unrecorded.
#
# Almost every turn of a game carries something - a wonder, a golden age, a
# settler - so entries cannot be found by looking for empty turns. An entry is
# anchored on a moment heavy enough to be remembered; lighter moments only join
# an entry that already exists, or stay behind as background.
class ChronicleSpine
  extend Projection

  MIN_ENTRIES = 12
  MAX_ENTRIES = 30
  TURNS_PER_ENTRY = 9
  CLUSTER_GAP = 3
  CLUSTER_SPAN = 6
  QUIET_GAP = 8
  ANCHOR_WEIGHT = 3

  WEIGHTS = {
    nuclear_detonation: 8, capital_gained: 6, capital_lost: 6,
    cultural_victory_imminent: 6, science_victory_imminent: 6, diplomatic_victory_imminent: 6,
    city_captured: 4, city_destroyed: 4, ideology_adopted: 4,
    united_nations_formed: 4, apollo_completed: 4, era_lead: 3, leader_change: 3,
    religion_founded: 3, world_wonder: 3, city_founded: 2, religion_enhanced: 2,
    reformation_added: 2, congress_host_change: 2, spaceship_part_assembled: 2,
    pantheon_founded: 1, resolution_passed: 1, natural_wonder: 1, golden_age: 1
  }.freeze

  # A war is worth what it cost. A declaration nobody acted on is an act of
  # diplomacy that the chronicle need not stop for, and a raid for a worker
  # earns a sentence where a war of conquest earns an entry.
  WAR_WEIGHTS = { war: 5, raid: 2, bloodless: 1 }.freeze

  FIRST_OF_ITS_KIND_BONUS = 1

  def initialize(game)
    @log = game.event_log
    @detector = KeyMomentDetector.new(game)
  end

  def entries
    @entries ||= chosen_clusters.sort_by(&:first_turn).map { |cluster| entry_for(cluster) }
  end

  def background
    @background ||= moments - chosen_clusters.flat_map(&:moments)
  end

  # Stretches the chronicle jumps over, so it can say the years passed rather
  # than narrate them.
  def quiet_spans
    entries.each_cons(2).filter_map do |before, following|
      gap = following[:from_turn] - before[:to_turn]
      { from_turn: before[:to_turn], to_turn: following[:from_turn] } if gap >= QUIET_GAP
    end
  end

  private

  def entry_for(cluster)
    { turn: cluster.anchor[:turn], from_turn: cluster.first_turn, to_turn: cluster.last_turn,
      era: era_by(cluster.anchor[:turn]), weight: cluster.peak, moments: cluster.moments }
  end

  def era_by(turn)
    @detector.era_leads.select { |lead| lead[:turn] <= turn }.max_by { |lead| lead[:turn] }&.fetch(:era)
  end

  # The heaviest clusters the chronicle has room for, each grown with the
  # light moments that happened around it.
  def chosen_clusters
    @chosen_clusters ||= anchor_clusters.max_by(entry_budget) { |cluster| [ cluster.peak, cluster.weight ] }
      .tap { |chosen| light_moments.each { |moment| nearest(chosen, moment)&.add(moment) } }
  end

  def nearest(clusters, moment)
    clusters.min_by { |cluster| cluster.distance_to(moment) }&.then do |cluster|
      cluster if cluster.distance_to(moment) <= CLUSTER_GAP
    end
  end

  def entry_budget
    (max_turn / TURNS_PER_ENTRY).clamp(MIN_ENTRIES, MAX_ENTRIES)
  end

  def max_turn = moments.last&.fetch(:turn).to_i

  def anchor_clusters
    @anchor_clusters ||= anchor_moments.each_with_object([]) do |moment, clusters|
      open = clusters.last
      open&.accepts?(moment) ? open.add(moment) : clusters << Cluster.new(moment)
    end
  end

  def anchor_moments = moments.select { |moment| moment[:weight] >= ANCHOR_WEIGHT }

  def light_moments = moments - anchor_moments

  def moments
    @moments ||= (detected_moments + logged_moments)
      .map { |moment| moment.merge(weight: weight_of(moment)) }
      .sort_by { |moment| moment[:turn] }
  end

  def weight_of(moment)
    base_weight(moment) + (moment[:order] == 1 ? FIRST_OF_ITS_KIND_BONUS : 0)
  end

  def base_weight(moment)
    return WAR_WEIGHTS.fetch(moment[:scale]) if moment[:type] == :war

    WEIGHTS.fetch(moment[:type], 1)
  end

  def detected_moments
    detector = @detector

    wars + detector.religion_foundings + detector.pantheon_foundings +
      detector.religion_enhancements + detector.reformations + detector.era_leads +
      detector.ideology_adoptions + detector.nuclear_detonations + detector.capital_control_changes +
      detector.united_nations_formed + detector.congress_host_changes + detector.resolutions_passed +
      detector.leader_changes + detector.cultural_victory_imminent + detector.science_victory_imminent +
      detector.diplomatic_victory_imminent + detector.apollo_completions + detector.spaceship_part_assemblies
  end

  # The chronicle is told the shape of a war's losses, never their size,
  # so the detector's raw toll is spent here and does not travel on.
  def wars
    @detector.wars.map { |war| chronicled(war) }
  end

  def chronicled(war)
    toll = war[:toll]
    told = war.except(:toll, :forces)
              .merge(casualties: bleeding(toll), losses_by_type: buried(toll),
                     taken_by_type: taken(toll))

    war[:forces] ? told.merge(armies: armies(war[:forces])) : told
  end

  # What stood on the field and what new thing reached it, and how much of
  # an army was built against how much was re-armed under fire - the
  # difference between a war paid for with production and one paid for
  # with gold. Never the production ledger itself: a table of types by
  # count invites reciting where the entry wants writing.
  def armies(forces)
    forces.transform_values do |side|
      { opening: side[:opening], closing: side[:closing], debuts: side[:debuts],
        built: side[:raised].values.sum, re_armed: side[:upgraded].values.sum }
    end
  end

  # How heavily each side bled, as a multiple of the lightest losses in the
  # war. A chronicle counts casualties against each other, never in units.
  def bleeding(toll)
    losses = toll.transform_values { |side| side[:losses] }
    lightest = losses.values.reject(&:zero?).min

    lightest ? losses.transform_values { |lost| (lost / lightest.to_f).round(1) } : {}
  end

  # The ratio says how heavily a side bled; only the types say what the war
  # was fought with, and how far apart the two arsenals stood.
  def buried(toll) = toll.transform_values { |side| side[:loss_types] }

  # A civilian led away is a discrete act, not a body count, so the count
  # of these does reach the page.
  def taken(toll) = toll.transform_values { |side| side[:captured_types] }

  def logged_moments
    cities + wonders + discoveries
  end

  def cities
    founded = of_type("city_founded").map do |e|
      { type: :city_founded, turn: e.turn, civ: e.civ, city: e.payload["city"] }
    end

    captured = of_type("city_captured").map do |e|
      { type: :city_captured, turn: e.turn, city: e.payload["city"],
        from: e.payload["old_owner"], to: e.payload["new_owner"] }
    end

    destroyed = razings.map do |e|
      { type: :city_destroyed, turn: e.turn, city: e.payload["city"], civ: e.civ }
    end

    founded + captured + destroyed
  end

  # city_destroyed is polled once per turn per player (razing fires no DLL
  # hook to push it), so it can't tell a razing from a city that simply
  # changed hands - both make the previous owner's city vanish from its
  # census, and a capture shows up in that owner's census as late as the
  # turn after the capture itself. A capture already narrates that turn, so
  # only destructions with no matching capture are real razings.
  def razings
    captured = of_type("city_captured").map { |e| [ e.payload["city"], e.turn ] }

    of_type("city_destroyed").reject do |e|
      captured.any? { |city, turn| city == e.payload["city"] && (e.turn - turn).between?(0, 1) }
    end
  end

  # A national wonder is a building every empire raises for itself; only the
  # world wonders are events the world would have heard about.
  def wonders
    of_type("building_constructed").select { |e| e.payload["wonder"] == "world" }.map do |e|
      { type: :world_wonder, turn: e.turn, civ: e.civ, wonder: e.payload["building"], city: e.payload["city"] }
    end
  end

  def discoveries
    natural = of_type("natural_wonder_discovered").map do |e|
      { type: :natural_wonder, turn: e.turn, civ: e.civ, wonder: e.payload["natural_wonder"] }
    end

    golden = of_type("golden_age_started").map { |e| { type: :golden_age, turn: e.turn, civ: e.civ } }

    natural + golden
  end

  def of_type(event_type) = @log.of_type(event_type)

  # Moments close enough in time to belong to one entry of the chronicle.
  class Cluster
    def initialize(moment)
      @moments = [ moment ]
    end

    def accepts?(moment)
      moment[:turn] - last_turn <= CLUSTER_GAP && moment[:turn] - first_turn <= CLUSTER_SPAN
    end

    def add(moment) = @moments << moment

    def distance_to(moment)
      [ first_turn - moment[:turn], moment[:turn] - last_turn, 0 ].max
    end

    def moments = @moments.sort_by { |moment| moment[:turn] }

    def anchor = @moments.max_by { |moment| moment[:weight] }

    def peak = anchor[:weight]

    def weight = @moments.sum { |moment| moment[:weight] }

    def first_turn = @moments.map { |moment| moment[:turn] }.min

    def last_turn = @moments.map { |moment| moment[:turn] }.max
  end
end
