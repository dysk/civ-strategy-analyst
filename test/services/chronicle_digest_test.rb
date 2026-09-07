require "test_helper"

class ChronicleDigestTest < ActiveSupport::TestCase
  setup do
    @game = Game.create!(name: "Chronicle Digest Game", game_speed: "GAMESPEED_QUICK")
    @seq = 0
    event("Rome", "snapshot", 10, score: 100, population: 12, cities: 1)
    event(nil, "war_declared", 40, attacker_team: 1, attacker_civs: %w[Rome], defender_team: 2, defender_civs: %w[Greece])
    event(nil, "unit_killed", 41, killer: "Rome", victim: "Greece", unit: "UNIT_ARCHER")
    event("Greece", "unit_lost", 41, unit: "UNIT_ARCHER")
    event(nil, "city_captured", 42, city: "Athens", old_owner: "Greece", new_owner: "Rome")
    event(nil, "city_captured", 150, city: "Ostia", old_owner: "Rome", new_owner: "Greece")
  end

  test "carries everything the analysis digest carries" do
    assert_empty DigestBuilder.new(@game).call.keys - digest.keys
  end

  test "dates every turn of the game in years" do
    assert_equal "3940 BC", digest[:calendar][1]
    assert_equal "1600 AD", digest[:calendar][150]
  end

  test "dates each chronicle entry from its first year to its last" do
    entry = digest[:chronicle][:entries].find { |e| e[:turn] == 40 }

    assert_equal [ "1600 BC", "1480 BC" ], [ entry[:from_year], entry[:to_year] ]
  end

  test "falls back to the averaged souls when the log carries no city snapshots" do
    assert_equal 1_051_000, digest[:metrics]["Rome"][10]["souls"]
    assert_equal "average", digest[:metrics]["Rome"][10]["souls_source"]
  end

  test "counts souls city by city when the log carries city snapshots" do
    event("Carthage", "snapshot", 10, score: 100, population: 42, cities: 3)
    city_snapshot("Carthage", 10, "Carthage", 40)
    city_snapshot("Carthage", 10, "Utica", 1)
    city_snapshot("Carthage", 10, "Hippo", 1)

    checkpoint = digest[:metrics]["Carthage"][10]

    assert_equal Demographics.new(city_sizes: [ 40, 1, 1 ]).souls, checkpoint["souls"]
    assert_equal "cities", checkpoint["souls_source"]
  end

  test "breaks the souls out city by city when they come from the census" do
    event("Carthage", "snapshot", 10, score: 100, population: 42, cities: 3)
    city_snapshot("Carthage", 10, "Carthage", 40)
    city_snapshot("Carthage", 10, "Utica", 1)
    city_snapshot("Carthage", 10, "Hippo", 1)

    city_souls = digest[:metrics]["Carthage"][10]["city_souls"]

    assert_equal [ Demographics.new(city_sizes: [ 40 ]).souls, 1_000, 1_000 ], city_souls
  end

  test "omits the per-city breakdown when the souls are an empire-wide average" do
    assert_nil digest[:metrics]["Rome"][10]["city_souls"]
  end

  test "dates the quiet spans the chronicle jumps over" do
    span = digest[:chronicle][:quiet_spans].sole

    assert_equal [ "1480 BC", "1600 AD" ], [ span[:from_year], span[:to_year] ]
  end

  private

  def digest = ChronicleDigest.new(@game).call

  def city_snapshot(civ, turn, city, population)
    event(civ, "city_snapshot", turn, city: city, population: population)
  end

  def event(civ, event_type, turn, **extra)
    @seq += 1
    payload = extra.stringify_keys.merge("event" => event_type, "turn" => turn)
    payload["civ"] = civ if civ
    @game.game_events.create!(
      seq: @seq, session_index: 0, turn: turn, event_type: event_type, civ: civ, payload: payload
    )
  end
end
