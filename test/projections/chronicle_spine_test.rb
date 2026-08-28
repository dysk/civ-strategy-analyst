require "test_helper"

class ChronicleSpineTest < ActiveSupport::TestCase
  setup do
    @game = Game.create!(name: "Chronicle Spine Game")
    @seq = 0
  end

  test "a war anchors an entry of its own" do
    event(nil, "war_declared", 40, attacker_team: 1, attacker_civs: %w[Rome], defender_team: 2, defender_civs: %w[Greece])
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
    event(nil, "war_declared", 10, attacker_team: 1, attacker_civs: %w[Rome], defender_team: 2, defender_civs: %w[Greece])
    5.times { |i| event("Greece", "unit_lost", 11 + i) }
    event("Rome", "unit_lost", 12)
    event(nil, "peace_made", 20, team_a: 1, team_a_civs: %w[Rome], team_b: 2, team_b_civs: %w[Greece])

    war = spine.entries.flat_map { |entry| entry[:moments] }.find { |moment| moment[:type] == :war }

    assert_equal({ "Greece" => 5.0, "Rome" => 1.0 }, war[:casualties])
  end

  test "an entry carries the most advanced era reached by its turn" do
    event(nil, "era_entered", 30, era: "ERA_CLASSICAL", civs: %w[Rome])
    event(nil, "era_entered", 60, era: "ERA_MEDIEVAL", civs: %w[Greece])
    event(nil, "war_declared", 70, attacker_team: 1, attacker_civs: %w[Rome], defender_team: 2, defender_civs: %w[Greece])

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

    assert_includes spine.entries.flat_map { |entry| entry[:moments] }.map { |moment| moment[:type] }, :war
  end

  test "every moment that fits no entry is left as background" do
    crowd_the_game

    assert_equal 300, spine.entries.sum { |entry| entry[:moments].size } + spine.background.size
    refute_empty spine.background
  end

  test "light moments join the entry they happened around" do
    event(nil, "war_declared", 40, attacker_team: 1, attacker_civs: %w[Rome], defender_team: 2, defender_civs: %w[Greece])
    event("Rome", "golden_age_started", 43)

    assert_equal [ :war, :golden_age ], spine.entries.sole[:moments].map { |moment| moment[:type] }
  end

  test "years carrying nothing but light moments earn no entry at all" do
    event("Rome", "golden_age_started", 100)

    assert_empty spine.entries
    assert_equal [ :golden_age ], spine.background.map { |moment| moment[:type] }
  end

  test "quiet spans cover the stretches between distant entries" do
    event(nil, "war_declared", 20, attacker_team: 1, attacker_civs: %w[Rome], defender_team: 2, defender_civs: %w[Greece])
    event(nil, "peace_made", 22, team_a: 1, team_a_civs: %w[Rome], team_b: 2, team_b_civs: %w[Greece])
    event(nil, "war_declared", 150, attacker_team: 1, attacker_civs: %w[Rome], defender_team: 2, defender_civs: %w[Greece])

    assert_equal [ { from_turn: 20, to_turn: 150 } ], spine.quiet_spans
  end

  test "neighbouring entries leave no quiet span between them" do
    event(nil, "war_declared", 40, attacker_team: 1, attacker_civs: %w[Rome], defender_team: 2, defender_civs: %w[Greece])
    event(nil, "city_captured", 46, city: "Athens", old_owner: "Greece", new_owner: "Rome")

    assert_equal 2, spine.entries.size
    assert_empty spine.quiet_spans
  end

  private

  def spine = ChronicleSpine.for(@game)

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
