require "test_helper"

class WarCasualtiesTest < ActiveSupport::TestCase
  setup do
    @game = Game.create!(name: "War Casualties Test Game")
    @seq = 0
  end

  test "counts what a side lost in combat" do
    killed("Babylon", "Philippines", "UNIT_RIFLEMAN", turn: 205)
    killed("Babylon", "Philippines", "UNIT_LANCER", turn: 206)

    assert_equal 2, casualties_in(war)["Philippines"][:losses]
  end

  test "counts what a side destroyed" do
    killed("Babylon", "Philippines", "UNIT_RIFLEMAN", turn: 205)
    killed("Babylon", "Philippines", "UNIT_LANCER", turn: 206)

    assert_equal 2, casualties_in(war)["Babylon"][:kills]
  end

  # unit_lost is "left the map", not "died": a caravan founding a trade
  # route, a settler founding a city and a spent missionary all raise it.
  # Only a loss the game reports as a combat death is a casualty.
  test "leaves out a unit that left the map without dying in combat" do
    lost("Philippines", "UNIT_CARAVAN", turn: 205)

    assert_equal 0, casualties_in(war)["Philippines"][:losses]
  end

  test "breaks losses down by unit type" do
    killed("Babylon", "Philippines", "UNIT_RIFLEMAN", turn: 205)
    killed("Babylon", "Philippines", "UNIT_RIFLEMAN", turn: 206)
    killed("Babylon", "Philippines", "UNIT_LANCER", turn: 206)

    assert_equal({ "UNIT_RIFLEMAN" => 2, "UNIT_LANCER" => 1 },
                 casualties_in(war)["Philippines"][:loss_types])
  end

  # What a civilization destroyed, named by what died - the log never
  # records which unit did the killing.
  test "breaks kills down by the type of unit destroyed" do
    killed("Babylon", "Philippines", "UNIT_LANCER", turn: 205)

    assert_equal({ "UNIT_LANCER" => 1 }, casualties_in(war)["Babylon"][:kill_types])
  end

  # A chronicle names the unit that dominated the war, so the heaviest
  # toll comes first rather than in the order the units happened to die.
  test "orders unit types by how many fell" do
    killed("Babylon", "Philippines", "UNIT_LANCER", turn: 205)
    killed("Babylon", "Philippines", "UNIT_RIFLEMAN", turn: 206)
    killed("Babylon", "Philippines", "UNIT_RIFLEMAN", turn: 207)

    assert_equal [ "UNIT_RIFLEMAN", "UNIT_LANCER" ],
                 casualties_in(war)["Philippines"][:loss_types].keys
  end

  test "leaves out losses from before the war was declared" do
    killed("Babylon", "Philippines", "UNIT_RIFLEMAN", turn: 200)

    assert_equal 0, casualties_in(war(turn: 201, turn_peace: 210))["Philippines"][:losses]
  end

  test "leaves out losses from after peace was made" do
    killed("Babylon", "Philippines", "UNIT_RIFLEMAN", turn: 211)

    assert_equal 0, casualties_in(war(turn: 201, turn_peace: 210))["Philippines"][:losses]
  end

  test "counts a war that never ended to the end of the log" do
    killed("Babylon", "Philippines", "UNIT_RIFLEMAN", turn: 260)

    assert_equal 1, casualties_in(war(turn: 201, turn_peace: nil))["Philippines"][:losses]
  end

  # Barbarians and neighbours' wars run through the same turns, and their
  # dead belong to neither side of this war.
  test "leaves out a kill that only one side of the war took part in" do
    killed("Babylon", "Barbarians", "UNIT_BARBARIAN_WARRIOR", turn: 205)

    assert_equal 0, casualties_in(war)["Babylon"][:kills]
  end

  test "reports a participant that came through the war untouched" do
    killed("Babylon", "Philippines", "UNIT_RIFLEMAN", turn: 205)

    assert_equal({ losses: 0, loss_types: {}, kills: 1, kill_types: { "UNIT_RIFLEMAN" => 1 },
                   captured: 0, captured_types: {}, seized: 0, seized_types: {} },
                 casualties_in(war)["Babylon"])
  end

  test "counts each civilization of a coalition on its own" do
    killed("Harappa", "Philippines", "UNIT_RIFLEMAN", turn: 205)

    coalition = war(attacker_civs: [ "Babylon", "Harappa" ])
    assert_equal 1, casualties_in(coalition)["Harappa"][:kills]
  end

  # A stolen worker is never killed - it changes hands, and the game names
  # the taker on the loss itself. A unit that can fight cannot be taken, so
  # the same record on a soldier is a death with a known killer.
  test "a civilian led away is taken, not killed" do
    captured("Harappa", "India", "UNIT_WORKER", turn: 205)

    assert_equal({ captured: 1, losses: 0 }, casualties_in(theft_war)["Harappa"].slice(:captured, :losses))
  end

  test "credits the side that led the civilian away" do
    captured("Harappa", "India", "UNIT_WORKER", turn: 205)

    assert_equal 1, casualties_in(theft_war)["India"][:seized]
  end

  test "breaks captures down by unit type" do
    captured("Harappa", "India", "UNIT_WORKER", turn: 205)
    captured("Harappa", "India", "UNIT_MISSIONARY", turn: 206)

    assert_equal({ "UNIT_WORKER" => 1, "UNIT_MISSIONARY" => 1 },
                 casualties_in(theft_war)["Harappa"][:captured_types])
  end

  # A settler taken by a nation comes back as its worker, so what the
  # taker raised says nothing about what its owner lost.
  test "a settler that came back as a worker is still a settler taken" do
    captured("Harappa", "India", "UNIT_SETTLER", turn: 205)
    created("India", "UNIT_WORKER", turn: 205, x: 3, y: 4)

    assert_equal({ "UNIT_SETTLER" => 1 }, casualties_in(theft_war)["Harappa"][:captured_types])
  end

  test "a loss the game named nobody for was taken by nobody" do
    lost("Harappa", "UNIT_WORKER", turn: 205)

    assert_equal 0, casualties_in(theft_war)["Harappa"][:captured]
  end

  test "a soldier lost to a named killer died rather than changed hands" do
    captured("Harappa", "India", "UNIT_PIKEMAN", turn: 205)

    assert_equal({ captured: 0, losses: 1 }, casualties_in(theft_war)["Harappa"].slice(:captured, :losses))
  end

  test "leaves out a capture from before the war was declared" do
    captured("Harappa", "India", "UNIT_WORKER", turn: 200)

    assert_equal 0, casualties_in(theft_war(turn: 201))["Harappa"][:captured]
  end

  # What a war opened with says what it may have been about: a worker
  # taken, a missionary caught on the road, a prophet ridden down. A scout
  # dying says nothing at all, so it is named apart from both.
  test "names the first thing the war cost" do
    killed("Babylon", "Philippines", "UNIT_RIFLEMAN", turn: 206)
    killed("Babylon", "Philippines", "UNIT_LANCER", turn: 205)

    assert_equal({ turn: 205, civ: "Philippines", unit: "UNIT_LANCER", by: "Babylon",
                   fate: :killed, kind: :soldier },
                 first_blood_of(war))
  end

  test "counts a stolen civilian as the first thing the war cost" do
    captured("Harappa", "India", "UNIT_WORKER", turn: 205)

    assert_equal({ turn: 205, civ: "Harappa", unit: "UNIT_WORKER", by: "India",
                   fate: :captured, kind: :civilian },
                 first_blood_of(theft_war))
  end

  test "marks a great person cut down as a civilian" do
    killed("Babylon", "Philippines", "UNIT_MUSICIAN", turn: 205)

    assert_equal :civilian, first_blood_of(war)[:kind]
  end

  test "marks a scout ridden down as neither civilian nor soldier" do
    killed("Babylon", "Philippines", "UNIT_SCOUT", turn: 205)

    assert_equal :scout, first_blood_of(war)[:kind]
  end

  test "has nothing to name for a war nobody bled in" do
    lost("Philippines", "UNIT_CARAVAN", turn: 205)

    assert_nil first_blood_of(war)
  end

  # A declaration nobody acted on, a raid for a worker and a war of
  # conquest all arrive as the same event. What they cost tells them apart.
  test "a war nobody acted on has no scale to speak of" do
    assert_equal :bloodless, scale_of(war)
  end

  test "a war that only cost a civilian is a raid" do
    captured("Harappa", "India", "UNIT_WORKER", turn: 205)

    assert_equal :raid, scale_of(theft_war)
  end

  # A scout carries a weapon but stands for no campaign: one ridden down
  # far from home leaves the war as empty as it started.
  test "a war that only cost a scout is a raid" do
    killed("Babylon", "Philippines", "UNIT_SCOUT", turn: 205)

    assert_equal :raid, scale_of(war)
  end

  test "a war that cost a soldier is a war" do
    killed("Babylon", "Philippines", "UNIT_LANCER", turn: 205)

    assert_equal :war, scale_of(war)
  end

  private

  def scale_of(war) = WarCasualties.new(@game).scale(war)

  def casualties_in(war) = WarCasualties.new(@game).during(war)

  def first_blood_of(war) = WarCasualties.new(@game).first_blood(war)

  def theft_war(turn: 201) = war(turn: turn, attacker_civs: [ "India" ], defender_civs: [ "Harappa" ])

  def war(turn: 201, turn_peace: nil, attacker_civs: [ "Babylon" ], defender_civs: [ "Philippines" ])
    { type: :war, turn: turn, turn_peace: turn_peace,
      attacker_civs: attacker_civs, defender_civs: defender_civs }
  end

  def killed(killer, victim, unit, turn:)
    event("unit_killed", turn, "killer" => killer, "victim" => victim, "unit" => unit)
    lost(victim, unit, turn: turn)
  end

  # No unit_killed: the game named the taker on the loss and recorded no
  # combat death, which is what a capture looks like in the log.
  def captured(from, to, unit, turn:)
    lost(from, unit, turn: turn, killed_by: to)
  end

  def lost(civ, unit, turn:, killed_by: nil)
    event("unit_lost", turn, { "civ" => civ, "unit" => unit, "killed_by" => killed_by }.compact)
  end

  def created(civ, unit, turn:, x:, y:)
    event("unit_created", turn, "civ" => civ, "unit" => unit, "x" => x, "y" => y)
  end

  def event(type, turn, payload)
    @game.game_events.create!(
      seq: @seq += 1, session_index: 0, turn: turn, event_type: type, civ: payload["civ"],
      payload: payload.merge("event" => type, "turn" => turn)
    )
  end
end
