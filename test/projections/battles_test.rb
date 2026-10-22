require "test_helper"

class BattlesTest < ActiveSupport::TestCase
  setup do
    @game = Game.create!(name: "Battles Test Game")
    @seq = 0
  end

  test "three soldiers dying close together near a city is a battle" do
    founded("Rome", "Roma", 1, 10, 10)
    lost("Rome", 40, 10, 10)
    lost("Greece", 41, 10, 10)
    lost("Rome", 42, 10, 10)

    assert_equal [ "Roma" ], battles.map { |battle| battle[:city] }
  end

  # Two deaths is still an incident, not a fight - a scout and its escort
  # cut down together reads the same as two unlucky accidents.
  test "two soldiers' deaths near a city are not yet a battle" do
    founded("Rome", "Roma", 1, 10, 10)
    lost("Rome", 40, 10, 10)
    lost("Greece", 41, 10, 10)

    assert_empty battles
  end

  test "deaths spread far apart in time are separate incidents, each too thin to be a battle" do
    founded("Rome", "Roma", 1, 10, 10)
    lost("Rome", 40, 10, 10)
    lost("Rome", 80, 10, 10)
    lost("Rome", 120, 10, 10)

    assert_empty battles
  end

  # unit_lost fires for a caravan finishing its route and a worker stolen
  # just as readily as for a death in combat - neither is a fight.
  test "civilians lost near a city are not combat, so they join no battle" do
    founded("Rome", "Roma", 1, 10, 10)
    lost("Rome", 40, 10, 10, unit: "UNIT_WORKER")
    lost("Rome", 41, 10, 10, unit: "UNIT_CARAVAN")

    assert_empty battles
  end

  # A barbarian raid is routine background noise, not the kind of fight
  # this projection is meant to surface - chasing off a horde is not a
  # battle in the sense a chronicle means it.
  test "barbarians dying near a city are not combat worth a battle of their own" do
    founded("Rome", "Roma", 1, 10, 10)
    lost("Barbarians", 40, 10, 10)
    lost("Barbarians", 41, 10, 10)
    lost("Barbarians", 42, 10, 10)

    assert_empty battles
  end

  test "a civ's own losses still count even when barbarians died in the same window" do
    founded("Rome", "Roma", 1, 10, 10)
    lost("Rome", 40, 10, 10)
    lost("Rome", 41, 10, 10)
    lost("Rome", 42, 10, 10)
    lost("Barbarians", 42, 10, 10)

    assert_equal({ "Rome" => 3 }, battles.sole[:casualties])
  end

  test "a battle names how many each side lost" do
    founded("Rome", "Roma", 1, 10, 10)
    lost("Rome", 40, 10, 10)
    lost("Rome", 41, 10, 10)
    lost("Greece", 42, 10, 10)
    lost("Greece", 43, 10, 10)
    lost("Greece", 44, 10, 10)

    assert_equal({ "Rome" => 2, "Greece" => 3 }, battles.sole[:casualties])
  end

  # The small, one-sided clash that breaks a siege is as real a battle as
  # a bloodbath - how the chronicle weighs it is a question for later,
  # not a reason to leave it undetected.
  test "a battle still counts when only one side bled" do
    founded("Greece", "Athens", 1, 10, 10)
    lost("Rome", 42, 10, 10)
    lost("Rome", 43, 10, 10)
    lost("Rome", 43, 10, 10)

    assert_equal({ "Rome" => 3 }, battles.sole[:casualties])
  end

  test "a battle spans from its first death to its last" do
    founded("Rome", "Roma", 1, 10, 10)
    lost("Rome", 40, 10, 10)
    lost("Rome", 41, 10, 10)
    lost("Greece", 44, 10, 10)

    assert_equal [ 40, 44 ], battles.sole.values_at(:from_turn, :to_turn)
  end

  # A border hex names both its neighbours as candidates rather than
  # neither - the same generosity TileOwnership#candidates already
  # extends to a war's theatre - so deaths there can anchor a battle at
  # either city.
  test "a border hex names both neighbouring cities, so deaths there can anchor a battle at either" do
    founded("Rome", "Roma", 1, 10, 10)
    founded("Greece", "Athens", 2, 13, 10)
    lost("Rome", 40, 11, 9)
    lost("Greece", 41, 11, 9)
    lost("Rome", 42, 11, 9)

    assert_equal [ "Athens", "Roma" ], battles.map { |battle| battle[:city] }.sort
  end

  test "a death with no coordinates joins no battle" do
    founded("Rome", "Roma", 1, 10, 10)
    event("Rome", "unit_lost", 40, unit: "UNIT_WARRIOR")
    event("Rome", "unit_lost", 41, unit: "UNIT_WARRIOR")
    event("Rome", "unit_lost", 42, unit: "UNIT_WARRIOR")

    assert_empty battles
  end

  test "a death too far from any city joins no battle" do
    founded("Rome", "Roma", 1, 10, 10)
    lost("Rome", 40, 30, 30)
    lost("Rome", 41, 30, 30)
    lost("Rome", 42, 30, 30)

    assert_empty battles
  end

  # A long siege keeps bleeding at intervals rather than all at once - six
  # turns between deaths (quiet while a wall is retaken or a relief force
  # marches up) still reads as the same fight at standard speed. An
  # uncalibrated judgment call; examples/ only goes so far, and the real
  # number wants checking against a human-played game.
  test "deaths up to six turns apart still cluster into one battle at standard speed" do
    founded("Rome", "Roma", 1, 10, 10)
    lost("Rome", 40, 10, 10)
    lost("Rome", 41, 10, 10)
    lost("Rome", 46, 10, 10)

    assert_equal [ "Roma" ], battles.map { |battle| battle[:city] }
  end

  # GAMESPEED_QUICK scales every standard-speed turn count by two thirds,
  # the way EARLY_GAME_GRACE_PERIOD_STANDARD_TURNS already does for
  # KeyMomentDetector - the same six-turn lull a standard game reads as
  # one fight is too long a silence at quick speed, and the deaths split
  # into two incidents too thin on their own to be a battle.
  test "the same six-turn gap is too long to be one battle at quick speed" do
    @game.update!(game_speed: "GAMESPEED_QUICK")
    founded("Rome", "Roma", 1, 10, 10)
    lost("Rome", 40, 10, 10)
    lost("Rome", 41, 10, 10)
    lost("Rome", 46, 10, 10)

    assert_empty battles
  end

  test "battles are returned in turn order" do
    founded("Rome", "Roma", 1, 10, 10)
    founded("Tibet", "Lhasa", 1, 30, 30)
    lost("Rome", 60, 30, 30)
    lost("Rome", 61, 30, 30)
    lost("Rome", 62, 30, 30)
    lost("Greece", 10, 10, 10)
    lost("Greece", 11, 10, 10)
    lost("Greece", 12, 10, 10)

    assert_equal [ "Roma", "Lhasa" ], battles.map { |battle| battle[:city] }
  end

  private

  def battles = Battles.for(@game).all

  def founded(civ, city, turn, x, y)
    event(civ, "city_founded", turn, city: city, x: x, y: y)
  end

  def lost(civ, turn, x, y, unit: "UNIT_WARRIOR")
    event(civ, "unit_lost", turn, unit: unit, x: x, y: y)
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
