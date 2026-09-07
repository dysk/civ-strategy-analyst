require "test_helper"

class ChronicleSpineTest < ActiveSupport::TestCase
  setup do
    @game = Game.create!(name: "Chronicle Spine Game")
    @seq = 0
  end

  test "a war anchors an entry of its own" do
    event(nil, "war_declared", 40, attacker_team: 1, attacker_civs: %w[Rome], defender_team: 2, defender_civs: %w[Greece])
    killed("Rome", "Greece", "UNIT_ARCHER", 41)
    event(nil, "peace_made", 50, team_a: 1, team_a_civs: %w[Rome], team_b: 2, team_b_civs: %w[Greece])

    assert_equal [ 40 ], spine.entries.map { |entry| entry[:turn] }
  end

  test "moments close to an anchor join its entry instead of starting one" do
    event(nil, "war_declared", 40, attacker_team: 1, attacker_civs: %w[Rome], defender_team: 2, defender_civs: %w[Greece])
    event(nil, "city_captured", 42, city: "Athens", old_owner: "Greece", new_owner: "Rome")

    entry = spine.entries.sole

    assert_equal [ 40, 42 ], [ entry[:from_turn], entry[:to_turn] ]
  end

  test "a war records how much more heavily one side bled than the other" do
    declare_war
    5.times { |i| killed("Rome", "Greece", "UNIT_ARCHER", 11 + i) }
    killed("Greece", "Rome", "UNIT_WARRIOR", 12)

    assert_equal({ "Greece" => 5.0, "Rome" => 1.0 }, war_moment[:casualties])
  end

  # unit_lost is "left the map", not "died": a caravan founding a trade
  # route raises it, and a trading empire would read as the bloodiest.
  test "a unit that left the map without dying in combat is no part of the toll" do
    declare_war
    5.times { |i| event("Greece", "unit_lost", 11 + i, unit: "UNIT_CARAVAN") }

    assert_empty war_moment[:casualties]
  end

  test "a side that came through the war untouched is recorded as having lost nothing" do
    declare_war
    killed("Rome", "Greece", "UNIT_ARCHER", 11)

    assert_equal 0.0, war_moment[:casualties]["Rome"]
  end

  # The chronicle is told the shape of the losses, never their size: the
  # raw toll the detector counts stays out of the moment it is built from.
  test "a war keeps its counts out of the chronicle" do
    declare_war
    killed("Rome", "Greece", "UNIT_ARCHER", 11)

    assert_not war_moment.key?(:toll)
  end

  # A civilian led away is a discrete act, not a body count, so the
  # chronicle is trusted with how many.
  test "a war names the civilians led away" do
    declare_war
    event("Greece", "unit_lost", 11, unit: "UNIT_WORKER", killed_by: "Rome")

    assert_equal({ "UNIT_WORKER" => 1 }, war_moment[:taken_by_type]["Greece"])
  end

  test "a war carries what it opened with" do
    declare_war
    event("Greece", "unit_lost", 11, unit: "UNIT_WORKER", killed_by: "Rome")

    assert_equal :civilian, war_moment[:first_blood][:kind]
  end

  # A declaration nobody acted on and a raid for a worker are not the
  # moment a war of conquest is, and the chronicle should not spend an
  # entry on them as though they were.
  test "a raid weighs less than a war" do
    declare_war
    killed("Rome", "Greece", "UNIT_ARCHER", 11)
    event(nil, "war_declared", 60, attacker_team: 3, attacker_civs: %w[Rome], defender_team: 4, defender_civs: %w[Egypt])
    event("Egypt", "unit_lost", 61, unit: "UNIT_WORKER", killed_by: "Rome")

    assert_operator war_weight_at(10), :>, war_weight_at(60)
  end

  test "a declaration nobody acted on weighs less than a raid" do
    event(nil, "war_declared", 60, attacker_team: 3, attacker_civs: %w[Rome], defender_team: 4, defender_civs: %w[Egypt])
    event("Egypt", "unit_lost", 61, unit: "UNIT_WORKER", killed_by: "Rome")
    event(nil, "war_declared", 100, attacker_team: 5, attacker_civs: %w[Rome], defender_team: 6, defender_civs: %w[Persia])

    assert_operator war_weight_at(60), :>, war_weight_at(100)
  end

  # The ratio says how heavily a side bled; only the types say what the
  # war was fought with, and how far apart the two arsenals stood.
  test "a war names what each side buried" do
    declare_war
    killed("Rome", "Greece", "UNIT_ARCHER", 11)
    killed("Rome", "Greece", "UNIT_ARCHER", 12)
    killed("Rome", "Greece", "UNIT_SPEARMAN", 13)

    assert_equal({ "UNIT_ARCHER" => 2, "UNIT_SPEARMAN" => 1 }, war_moment[:losses_by_type]["Greece"])
  end

  test "an entry carries the most advanced era reached by its turn" do
    event(nil, "era_entered", 30, era: "ERA_CLASSICAL", civs: %w[Rome])
    event(nil, "era_entered", 60, era: "ERA_MEDIEVAL", civs: %w[Greece])
    event(nil, "war_declared", 70, attacker_team: 1, attacker_civs: %w[Rome], defender_team: 2, defender_civs: %w[Greece])
    killed("Rome", "Greece", "UNIT_ARCHER", 71)

    assert_equal "ERA_MEDIEVAL", spine.entries.find { |entry| entry[:turn] == 70 }[:era]
  end

  test "a world wonder is chronicle material" do
    event("Rome", "building_constructed", 45, building: "BUILDING_PYRAMIDS", city: "Rome", wonder: "world")

    assert_equal [ :world_wonder ], spine.entries.sole[:moments].map { |moment| moment[:type] }
  end

  test "a national wonder is not chronicle material" do
    event("Rome", "building_constructed", 45, building: "BUILDING_NATIONAL_COLLEGE", city: "Rome", wonder: "national")

    assert_empty spine.entries
  end

  test "the first religion founded outweighs the ones that follow" do
    event("Rome", "religion_founded", 40, religion: "RELIGION_CHRISTIANITY", holy_city: "Rome", beliefs: [])
    event("Greece", "religion_founded", 80, religion: "RELIGION_HELLENISM", holy_city: "Athens", beliefs: [])

    first, second = spine.entries.flat_map { |entry| entry[:moments] }.select { |m| m[:type] == :religion_founded }

    assert_operator first[:weight], :>, second[:weight]
  end

  test "a capital changing hands outweighs an ordinary city falling" do
    event("Rome", "snapshot", 30, capitals: %w[Rome])
    event("Rome", "snapshot", 80, capitals: %w[Rome Greece])
    event(nil, "city_captured", 40, city: "Corinth", old_owner: "Greece", new_owner: "Rome")

    moments = spine.entries.flat_map { |entry| entry[:moments] }
    capital = moments.find { |m| m[:type] == :capital_gained }
    city = moments.find { |m| m[:type] == :city_captured }

    assert_operator capital[:weight], :>, city[:weight]
  end

  test "a player voted out of the game anchors an entry of its own" do
    event(nil, "mp_proposal_result", 60, type: "irrelevance", status: "passed",
      owner: "India", subject: "Rome", yes_votes: 4, no_votes: 1)

    moment = spine.entries.flat_map { |entry| entry[:moments] }.find { |m| m[:type] == :player_declared_irrelevant }

    assert_equal 60, moment[:turn]
    assert_operator moment[:weight], :>=, ChronicleSpine::ANCHOR_WEIGHT
  end

  test "a long game earns more entries than a short one" do
    60.times { |i| event(nil, "city_captured", i * 4 + 1, city: "City #{i}", old_owner: "Greece", new_owner: "Rome") }
    short_game = Game.create!(name: "Short Game")
    60.times { |i| event(nil, "city_captured", i + 1, game: short_game, city: "City #{i}", old_owner: "Greece", new_owner: "Rome") }

    assert_operator spine.entries.size, :>, ChronicleSpine.for(short_game).entries.size
  end

  test "a game full of moments still stops at the chronicle's entry ceiling" do
    crowd_the_game

    assert_equal ChronicleSpine::MAX_ENTRIES, spine.entries.size
  end

  test "a heavy moment earns an entry however crowded the years around it" do
    crowd_the_game
    event(nil, "war_declared", 601, attacker_team: 1, attacker_civs: %w[Rome], defender_team: 2, defender_civs: %w[Greece])
    killed("Rome", "Greece", "UNIT_ARCHER", 602)

    assert_includes spine.entries.flat_map { |entry| entry[:moments] }.map { |moment| moment[:type] }, :war
  end

  test "every moment that fits no entry is left as background" do
    crowd_the_game

    assert_equal 300, spine.entries.sum { |entry| entry[:moments].size } + spine.background.size
    refute_empty spine.background
  end

  test "light moments join the entry they happened around" do
    event(nil, "war_declared", 40, attacker_team: 1, attacker_civs: %w[Rome], defender_team: 2, defender_civs: %w[Greece])
    killed("Rome", "Greece", "UNIT_ARCHER", 40)
    event("Rome", "golden_age_started", 43)

    assert_equal [ :war, :golden_age ], spine.entries.sole[:moments].map { |moment| moment[:type] }
  end

  test "years carrying nothing but light moments earn no entry at all" do
    event("Rome", "golden_age_started", 100)

    assert_empty spine.entries
    assert_equal [ :golden_age ], spine.background.map { |moment| moment[:type] }
  end

  test "a captured city's census dropout the following turn is not narrated a second time" do
    event(nil, "city_captured", 40, city: "Corinth", old_owner: "Greece", new_owner: "Rome")
    event("Greece", "city_destroyed", 41, city: "Corinth")

    moments = spine.entries.flat_map { |entry| entry[:moments] }

    assert_equal [ :city_captured ], moments.map { |moment| moment[:type] }
  end

  test "a city destroyed with no matching capture is still a razing" do
    event("Rome", "city_destroyed", 40, city: "Corinth")

    assert_equal [ :city_destroyed ], spine.entries.sole[:moments].map { |moment| moment[:type] }
  end

  test "quiet spans cover the stretches between distant entries" do
    event(nil, "war_declared", 20, attacker_team: 1, attacker_civs: %w[Rome], defender_team: 2, defender_civs: %w[Greece])
    killed("Rome", "Greece", "UNIT_ARCHER", 20)
    event(nil, "peace_made", 22, team_a: 1, team_a_civs: %w[Rome], team_b: 2, team_b_civs: %w[Greece])
    event(nil, "war_declared", 150, attacker_team: 1, attacker_civs: %w[Rome], defender_team: 2, defender_civs: %w[Greece])
    killed("Rome", "Greece", "UNIT_ARCHER", 150)

    assert_equal [ { from_turn: 20, to_turn: 150 } ], spine.quiet_spans
  end

  test "neighbouring entries leave no quiet span between them" do
    event(nil, "war_declared", 40, attacker_team: 1, attacker_civs: %w[Rome], defender_team: 2, defender_civs: %w[Greece])
    killed("Rome", "Greece", "UNIT_ARCHER", 40)
    event(nil, "city_captured", 46, city: "Athens", old_owner: "Greece", new_owner: "Rome")

    assert_equal 2, spine.entries.size
    assert_empty spine.quiet_spans
  end

  test "a war names what each side had standing when it opened" do
    event("Rome", "unit_created", 5, unit: "UNIT_ARCHER")
    declare_war
    killed("Rome", "Greece", "UNIT_SPEARMAN", 12)

    assert_equal({ "UNIT_ARCHER" => 1 }, war_moment[:armies]["Rome"][:opening])
  end

  # Per-type production is ledger material. The chronicle is told how much
  # of an army was built against how much was re-armed under fire - the
  # difference between a war paid for with production and one paid for
  # with gold - and left to write rather than to recite.
  test "a war counts what each side built and re-armed without listing it" do
    declare_war
    killed("Rome", "Greece", "UNIT_SPEARMAN", 12)
    event("Rome", "unit_created", 13, unit: "UNIT_ARCHER")
    event("Rome", "unit_created", 14, unit: "UNIT_SPEARMAN")
    event("Rome", "unit_upgraded", 14, from: "UNIT_ARCHER", to: "UNIT_SPEARMAN")
    event("Rome", "unit_lost", 14, unit: "UNIT_ARCHER")

    assert_equal 1, war_moment[:armies]["Rome"][:built]
    assert_equal 1, war_moment[:armies]["Rome"][:re_armed]
  end

  test "a war carries no order of battle beyond the part the chronicle is given" do
    declare_war
    killed("Rome", "Greece", "UNIT_SPEARMAN", 12)

    assert_nil war_moment[:forces]
  end

  private

  def spine = ChronicleSpine.for(@game)

  def war_moment = war_moments.first

  def war_moments
    (spine.entries.flat_map { |entry| entry[:moments] } + spine.background).select { |m| m[:type] == :war }
  end

  def war_weight_at(turn) = war_moments.find { |moment| moment[:turn] == turn }[:weight]

  def declare_war
    event(nil, "war_declared", 10, attacker_team: 1, attacker_civs: %w[Rome], defender_team: 2, defender_civs: %w[Greece])
    event(nil, "peace_made", 20, team_a: 1, team_a_civs: %w[Rome], team_b: 2, team_b_civs: %w[Greece])
  end

  def killed(killer, victim, unit, turn)
    event(nil, "unit_killed", turn, killer: killer, victim: victim, unit: unit)
    event(victim, "unit_lost", turn, unit: unit)
  end

  def crowd_the_game
    300.times { |i| event(nil, "city_captured", i * 2 + 1, city: "City #{i}", old_owner: "Greece", new_owner: "Rome") }
  end

  def event(civ, event_type, turn, game: @game, **extra)
    @seq += 1
    payload = extra.stringify_keys.merge("event" => event_type, "turn" => turn)
    payload["civ"] = civ if civ
    game.game_events.create!(
      seq: @seq, session_index: 0, turn: turn, event_type: event_type, civ: civ, payload: payload
    )
  end
end
