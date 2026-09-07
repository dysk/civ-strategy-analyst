require "test_helper"

class WonderRacesTest < ActiveSupport::TestCase
  setup do
    @game = Game.create!(name: "Wonder Races Test Game")
    @seq = 0
  end

  test "a contested wonder yields one race: the winner and each civ it beat" do
    # England pours ten turns into the Louvre in London and loses it to Amsterdam.
    (148..157).each { |t| building(t, "England", "London", "BUILDING_LOUVRE", stored: (t - 148) * 47) }
    (154..157).each { |t| building(t, "Netherlands", "Amsterdam", "BUILDING_LOUVRE", stored: (t - 154) * 120) }
    completed(158, "Netherlands", "Amsterdam", "BUILDING_LOUVRE")

    races = WonderRaces.new(@game).races
    assert_equal 1, races.size

    race = races.first
    assert_equal "BUILDING_LOUVRE", race[:wonder]
    assert_equal 158, race[:completed_turn]
    assert_equal({ civ: "Netherlands", city: "Amsterdam" }, race[:winner])

    assert_equal 1, race[:contenders].size
    england = race[:contenders].first
    assert_equal "England", england[:civ]
    assert_equal "London", england[:city]
    assert_equal 148, england[:first_seen_turn]
    assert_equal 157, england[:last_seen_turn]
    assert_equal 10, england[:turns_building]
    assert_equal 9 * 47, england[:production_invested]
    assert_equal :lost, england[:outcome]
  end

  test "an uncontested completion is not a race" do
    (40..50).each { |t| building(t, "India", "Delhi", "BUILDING_TAJ_MAHAL", stored: t) }
    completed(51, "India", "Delhi", "BUILDING_TAJ_MAHAL")

    assert_empty WonderRaces.new(@game).races
  end

  test "the winner's own city is never a contender against itself" do
    (40..50).each { |t| building(t, "India", "Delhi", "BUILDING_PYRAMID", stored: t) }
    (45..50).each { |t| building(t, "Tibet", "Lhasa", "BUILDING_PYRAMID", stored: t) }
    completed(51, "India", "Delhi", "BUILDING_PYRAMID")

    contenders = WonderRaces.new(@game).races.first[:contenders]
    assert_equal %w[Tibet], contenders.map { |c| c[:civ] }
  end

  test "more than one civ can lose the same race" do
    (40..50).each { |t| building(t, "England", "London", "BUILDING_GREAT_WALL", stored: t) }
    (40..49).each { |t| building(t, "Zimbabwe", "Harare", "BUILDING_GREAT_WALL", stored: t) }
    (40..50).each { |t| building(t, "Iroquois", "Onondaga", "BUILDING_GREAT_WALL", stored: t) }
    completed(51, "England", "London", "BUILDING_GREAT_WALL")

    losers = WonderRaces.new(@game).races.first[:contenders].map { |c| c[:civ] }
    assert_equal %w[Iroquois Zimbabwe], losers.sort
  end

  test "a civ that stopped building well before completion abandoned rather than lost" do
    (40..44).each { |t| building(t, "Zimbabwe", "Harare", "BUILDING_GREAT_WALL", stored: t) }
    (40..50).each { |t| building(t, "England", "London", "BUILDING_GREAT_WALL", stored: t * 2) }
    completed(51, "England", "London", "BUILDING_GREAT_WALL")

    zimbabwe = WonderRaces.new(@game).races.first[:contenders].find { |c| c[:civ] == "Zimbabwe" }
    assert_equal 44, zimbabwe[:last_seen_turn]
    assert_equal :abandoned, zimbabwe[:outcome]
  end

  test "a contender still building on the turn before completion lost it" do
    (48..50).each { |t| building(t, "Iroquois", "Onondaga", "BUILDING_RED_FORT", stored: t) }
    (45..50).each { |t| building(t, "India", "Delhi", "BUILDING_RED_FORT", stored: t) }
    completed(51, "India", "Delhi", "BUILDING_RED_FORT")

    iroquois = WonderRaces.new(@game).races.first[:contenders].find { |c| c[:civ] == "Iroquois" }
    assert_equal :lost, iroquois[:outcome]
  end

  test "production invested is the loser's last observed production_stored" do
    building(48, "England", "London", "BUILDING_LOUVRE", stored: 300)
    building(49, "England", "London", "BUILDING_LOUVRE", stored: 372)
    building(50, "England", "London", "BUILDING_LOUVRE", stored: 425)
    completed(51, "France", "Paris", "BUILDING_LOUVRE")

    england = WonderRaces.new(@game).races.first[:contenders].first
    assert_equal 425, england[:production_invested]
    assert_equal 50, england[:last_seen_turn]
  end

  test "a turn snapshotted twice by a reload counts once, the later payload winning" do
    building(48, "England", "London", "BUILDING_LOUVRE", stored: 100)
    building(48, "England", "London", "BUILDING_LOUVRE", stored: 140)
    building(49, "England", "London", "BUILDING_LOUVRE", stored: 180)
    completed(50, "France", "Paris", "BUILDING_LOUVRE")

    england = WonderRaces.new(@game).races.first[:contenders].first
    assert_equal 2, england[:turns_building]
    assert_equal 48, england[:first_seen_turn]
    assert_equal 180, england[:production_invested]
  end

  test "races are ordered by completion turn" do
    building(20, "A", "Ac", "BUILDING_STONEHENGE", stored: 1)
    building(20, "B", "Bc", "BUILDING_STONEHENGE", stored: 1)
    completed(21, "A", "Ac", "BUILDING_STONEHENGE")
    building(60, "A", "Ac", "BUILDING_GREAT_LIBRARY", stored: 1)
    building(60, "C", "Cc", "BUILDING_GREAT_LIBRARY", stored: 1)
    completed(61, "C", "Cc", "BUILDING_GREAT_LIBRARY")

    assert_equal [ 21, 61 ], WonderRaces.new(@game).races.map { |r| r[:completed_turn] }
  end

  test "a race carries the wonder's display name" do
    building(20, "A", "Ac", "BUILDING_HANGING_GARDENS", stored: 1)
    building(20, "B", "Bc", "BUILDING_HANGING_GARDENS", stored: 1)
    completed(21, "A", "Ac", "BUILDING_HANGING_GARDENS")

    assert_equal "Hanging Gardens", WonderRaces.new(@game).races.first[:wonder_name]
  end

  # The game's own turns-left estimate on the last snapshot is the sharpest
  # "how close were they": stored alone cannot tell England two turns off the
  # Louvre from a city that queued a wonder and never put a hammer in it.
  test "a contender carries the turns it still had left when last seen" do
    building(48, "England", "London", "BUILDING_LOUVRE", stored: 300, turns_left: 6)
    building(49, "England", "London", "BUILDING_LOUVRE", stored: 372, turns_left: 4)
    building(50, "England", "London", "BUILDING_LOUVRE", stored: 425, turns_left: 2)
    completed(51, "France", "Paris", "BUILDING_LOUVRE")

    england = WonderRaces.new(@game).races.first[:contenders].first
    assert_equal 2, england[:turns_left_when_last_seen]
  end

  test "a wonder finished no faster than its own estimate is a hard-built win" do
    building(48, "France", "Paris", "BUILDING_LOUVRE", stored: 400, turns_left: 2)
    building(49, "France", "Paris", "BUILDING_LOUVRE", stored: 460, turns_left: 1)
    building(49, "England", "London", "BUILDING_LOUVRE", stored: 300, turns_left: 5)
    completed(50, "France", "Paris", "BUILDING_LOUVRE")

    assert_equal :hard_built, WonderRaces.new(@game).races.first[:winner_finish]
  end

  # An engineer, a production overflow, a chopped forest or a granted
  # building - the log cannot say which, only that the wonder outran a hard
  # build.
  test "a wonder that beat its own estimate to completion outran a hard build" do
    building(48, "France", "Paris", "BUILDING_LOUVRE", stored: 120, turns_left: 9)
    building(49, "France", "Paris", "BUILDING_LOUVRE", stored: 150, turns_left: 8)
    building(49, "England", "London", "BUILDING_LOUVRE", stored: 300, turns_left: 3)
    completed(50, "France", "Paris", "BUILDING_LOUVRE")

    assert_equal :ahead_of_estimate, WonderRaces.new(@game).races.first[:winner_finish]
  end

  test "a winner never seen building the wonder leaves the finish unobserved" do
    building(48, "England", "London", "BUILDING_LOUVRE", stored: 400, turns_left: 3)
    building(49, "England", "London", "BUILDING_LOUVRE", stored: 450, turns_left: 2)
    completed(50, "France", "Paris", "BUILDING_LOUVRE")

    assert_equal :unobserved, WonderRaces.new(@game).races.first[:winner_finish]
  end

  # Whether the loser had a spy in the winner's city is what separates
  # losing a race you could see from losing one you could not; tranche 2
  # fills this in from spy_moved.
  test "the race record leaves room for a spy observation not yet filled in" do
    building(20, "A", "Ac", "BUILDING_STONEHENGE", stored: 1)
    building(20, "B", "Bc", "BUILDING_STONEHENGE", stored: 1)
    completed(21, "A", "Ac", "BUILDING_STONEHENGE")

    assert_nil WonderRaces.new(@game).races.first[:rival_observed]
  end

  test "applicable? is false when the log carries no city snapshot" do
    completed(21, "A", "Ac", "BUILDING_STONEHENGE")

    assert_not WonderRaces.new(@game).applicable?
  end

  test "applicable? is true once a city snapshot is present" do
    building(20, "B", "Bc", "BUILDING_STONEHENGE", stored: 1)

    assert WonderRaces.new(@game).applicable?
  end

  private

  def building(turn, civ, city, producing, stored:, turns_left: 1)
    city_snapshot(turn, civ, city, "producing" => producing, "producing_kind" => "wonder",
                  "production_stored" => stored, "production_turns_left" => turns_left)
  end

  def city_snapshot(turn, civ, city, extra)
    @seq += 1
    payload = extra.merge("event" => "city_snapshot", "turn" => turn, "civ" => civ, "city" => city)
    @game.game_events.create!(seq: @seq, session_index: 0, turn: turn,
                              event_type: "city_snapshot", civ: civ, payload: payload)
  end

  def completed(turn, civ, city, wonder)
    @seq += 1
    payload = { "event" => "building_constructed", "turn" => turn, "civ" => civ,
                "city" => city, "building" => wonder, "wonder" => "world" }
    @game.game_events.create!(seq: @seq, session_index: 0, turn: turn,
                              event_type: "building_constructed", civ: civ, payload: payload)
  end
end
