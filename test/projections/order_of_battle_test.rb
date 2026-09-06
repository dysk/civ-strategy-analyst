require "test_helper"

class OrderOfBattleTest < ActiveSupport::TestCase
  setup do
    @game = Game.create!(name: "Order Of Battle Test Game")
    @seq = 0
  end

  test "an army is empty before it has raised anything" do
    created("Babylon", "UNIT_WARRIOR", turn: 10)

    assert_empty roster(9, "Babylon")
  end

  test "counts a unit into the army that raised it" do
    created("Babylon", "UNIT_WARRIOR", turn: 10)

    assert_equal({ "UNIT_WARRIOR" => 1 }, roster(10, "Babylon"))
  end

  test "takes a lost unit back out of the army" do
    created("Babylon", "UNIT_WARRIOR", turn: 10)
    created("Babylon", "UNIT_WARRIOR", turn: 11)
    lost("Babylon", "UNIT_WARRIOR", turn: 12)

    assert_equal({ "UNIT_WARRIOR" => 1 }, roster(12, "Babylon"))
  end

  test "keeps one civilization's units out of another's army" do
    created("Babylon", "UNIT_WARRIOR", turn: 10)
    created("Arabia", "UNIT_SPEARMAN", turn: 10)

    assert_equal({ "UNIT_WARRIOR" => 1 }, roster(10, "Babylon"))
  end

  # An upgrade is logged as the new unit appearing and the old one leaving
  # on the same turn, so the ledger needs no rule of its own for it: the
  # army changes shape without changing size.
  test "an upgrade moves a unit between types and leaves the army the same size" do
    created("Babylon", "UNIT_WARRIOR", turn: 10)
    upgraded("Babylon", "UNIT_WARRIOR", "UNIT_SPEARMAN", turn: 20)

    assert_equal({ "UNIT_SPEARMAN" => 1 }, roster(20, "Babylon"))
  end

  test "drops a type from the army once its last unit is gone" do
    created("Babylon", "UNIT_WARRIOR", turn: 10)
    lost("Babylon", "UNIT_WARRIOR", turn: 11)

    assert_equal({}, roster(11, "Babylon"))
  end

  # The units a civilization starts the game with are placed before the
  # logger attaches, so they are lost without ever having been created.
  # That costs the count one unit; it must not cost it a negative army.
  test "never counts an army below nothing" do
    lost("Babylon", "UNIT_WARRIOR", turn: 5)
    created("Babylon", "UNIT_WARRIOR", turn: 10)

    assert_equal({ "UNIT_WARRIOR" => 1 }, roster(10, "Babylon"))
  end

  test "reads the army as it stood at the end of the turn asked for" do
    created("Babylon", "UNIT_WARRIOR", turn: 10)
    created("Babylon", "UNIT_ARCHER", turn: 11)

    assert_equal({ "UNIT_WARRIOR" => 1 }, roster(10, "Babylon"))
  end

  # A chronicle names what an army was mostly made of, so the heaviest
  # type comes first rather than whichever happened to be raised first.
  test "orders types by how many stand" do
    created("Babylon", "UNIT_ARCHER", turn: 10)
    created("Babylon", "UNIT_WARRIOR", turn: 11)
    created("Babylon", "UNIT_WARRIOR", turn: 12)

    assert_equal [ "UNIT_WARRIOR", "UNIT_ARCHER" ], roster(12, "Babylon").keys
  end

  test "reports the army each side fielded when war was declared" do
    created("Babylon", "UNIT_BOMBER", turn: 200)
    created("Philippines", "UNIT_RIFLEMAN", turn: 200)

    fought = during(war(turn: 201, turn_peace: 210))

    assert_equal({ "UNIT_BOMBER" => 1 }, fought["Babylon"][:opening])
    assert_equal({ "UNIT_RIFLEMAN" => 1 }, fought["Philippines"][:opening])
  end

  test "reports the army each side was left with when peace was made" do
    created("Philippines", "UNIT_RIFLEMAN", turn: 200)
    created("Philippines", "UNIT_LANCER", turn: 200)
    lost("Philippines", "UNIT_LANCER", turn: 205)

    assert_equal({ "UNIT_RIFLEMAN" => 1 },
                 during(war(turn: 201, turn_peace: 210))["Philippines"][:closing])
  end

  # A war still burning when the log ends has no turn of peace to read,
  # and the last turn recorded is the last thing that can be said about it.
  test "an unfinished war closes on the last turn in the log" do
    created("Philippines", "UNIT_RIFLEMAN", turn: 200)
    created("Philippines", "UNIT_LANCER", turn: 205)

    assert_equal({ "UNIT_RIFLEMAN" => 1, "UNIT_LANCER" => 1 },
                 during(war(turn: 201))["Philippines"][:closing])
  end

  # A city-state's units are its own business and the log carries few of
  # them, so its side of a war is empty rather than absent.
  test "leaves a city-state's side of the war empty rather than missing" do
    created("Babylon", "UNIT_BOMBER", turn: 200)

    fought = during(war(turn: 201, defender_civs: [ "Kathmandu" ]))

    assert_equal({}, fought["Kathmandu"][:opening])
  end

  test "counts what a side raised while the war lasted" do
    created("Babylon", "UNIT_CANNON", turn: 202)
    created("Babylon", "UNIT_CANNON", turn: 203)

    assert_equal({ "UNIT_CANNON" => 2 },
                 during(war(turn: 201, turn_peace: 210))["Babylon"][:raised])
  end

  test "leaves out what a side raised before the war and after the peace" do
    created("Babylon", "UNIT_CANNON", turn: 200)
    created("Babylon", "UNIT_CANNON", turn: 211)

    assert_equal({}, during(war(turn: 201, turn_peace: 210))["Babylon"][:raised])
  end

  # An upgrade puts no new unit in the field, it re-arms one already
  # standing. Counted among the raised it counts the same hardware twice:
  # five cannon built and four of them upgraded to artillery read as nine
  # guns where eight men stand.
  test "leaves a unit that arrived by upgrading out of what a side raised" do
    created("Babylon", "UNIT_CANNON", turn: 202)
    upgraded("Babylon", "UNIT_CANNON", "UNIT_ARTILLERY", turn: 204)

    assert_equal({ "UNIT_CANNON" => 1 },
                 during(war(turn: 201, turn_peace: 210))["Babylon"][:raised])
  end

  # An army re-armed under fire is spending gold where another spends
  # production, and that is worth counting rather than merely implying.
  test "counts what a side upgraded while the war lasted" do
    created("Babylon", "UNIT_CANNON", turn: 202)
    upgraded("Babylon", "UNIT_CANNON", "UNIT_ARTILLERY", turn: 204)

    assert_equal({ "UNIT_ARTILLERY" => 1 },
                 during(war(turn: 201, turn_peace: 210))["Babylon"][:upgraded])
  end

  # Four cannon upgraded and a fifth gun built on one turn is five
  # arrivals against four upgrades, and only the one left over was raised.
  test "tells a built unit from an upgraded one when both arrive on the same turn" do
    created("Babylon", "UNIT_MUSKETMAN", turn: 200)
    created("Babylon", "UNIT_RIFLEMAN", turn: 204)
    upgraded("Babylon", "UNIT_MUSKETMAN", "UNIT_RIFLEMAN", turn: 204)

    assert_equal({ "UNIT_RIFLEMAN" => 1 },
                 during(war(turn: 201, turn_peace: 210))["Babylon"][:raised])
  end

  # Twenty caravans raised under fire say something about how a war was
  # paid for, but counted among the soldiers they drown them out.
  test "keeps civilians out of what a side raised and reports them apart" do
    created("Babylon", "UNIT_CANNON", turn: 202)
    created("Babylon", "UNIT_CARAVAN", turn: 202)
    created("Babylon", "UNIT_CARAVAN", turn: 203)

    side = during(war(turn: 201, turn_peace: 210))["Babylon"]

    assert_equal({ "UNIT_CANNON" => 1 }, side[:raised])
    assert_equal({ "UNIT_CARAVAN" => 2 }, side[:raised_civilian])
  end

  # The arrival of a weapon the army did not have when the war opened is
  # the shape of a long war: what a side started with says little about
  # what it finished with eighty turns later.
  test "names the turn a type first reached an army during the war" do
    created("Babylon", "UNIT_CANNON", turn: 203)

    assert_equal [ { turn: 203, unit: "UNIT_CANNON", via: :built } ],
                 during(war(turn: 201, turn_peace: 210))["Babylon"][:debuts]
  end

  # A great person born mid-war is not a weapon reaching the front, and a
  # side whose only debuts are civilian fought the whole war with what it
  # already had - which is the thing worth being able to see.
  test "leaves civilians out of the debuts" do
    created("Babylon", "UNIT_PROPHET", turn: 202)
    created("Babylon", "UNIT_CANNON", turn: 203)

    assert_equal [ "UNIT_CANNON" ],
                 during(war(turn: 201, turn_peace: 210))["Babylon"][:debuts].map { |d| d[:unit] }
  end

  test "leaves out a type the side already fielded when war was declared" do
    created("Babylon", "UNIT_CANNON", turn: 200)
    created("Babylon", "UNIT_CANNON", turn: 203)

    assert_empty during(war(turn: 201, turn_peace: 210))["Babylon"][:debuts]
  end

  test "counts a type as a debut again once the last of it was lost before the war" do
    created("Babylon", "UNIT_CANNON", turn: 195)
    lost("Babylon", "UNIT_CANNON", turn: 196)
    created("Babylon", "UNIT_CANNON", turn: 203)

    assert_equal [ "UNIT_CANNON" ],
                 during(war(turn: 201, turn_peace: 210))["Babylon"][:debuts].map { |d| d[:unit] }
  end

  # An army that modernises by upgrading what it has is spending gold, not
  # production, and that is a different war from one fought with new builds.
  test "marks a debut that arrived by upgrading a unit already in the field" do
    created("Babylon", "UNIT_MUSKETMAN", turn: 200)
    upgraded("Babylon", "UNIT_MUSKETMAN", "UNIT_RIFLEMAN", turn: 204)

    assert_equal [ { turn: 204, unit: "UNIT_RIFLEMAN", via: :upgraded } ],
                 during(war(turn: 201, turn_peace: 210))["Babylon"][:debuts]
  end

  test "orders debuts by the turn they arrived" do
    created("Babylon", "UNIT_ARTILLERY", turn: 207)
    created("Babylon", "UNIT_CANNON", turn: 203)

    assert_equal [ "UNIT_CANNON", "UNIT_ARTILLERY" ],
                 during(war(turn: 201, turn_peace: 210))["Babylon"][:debuts].map { |d| d[:unit] }
  end

  # Eighty turns of war hide their middle between the two ends: a side can
  # build up, be broken, and rebuild without either end showing it.
  test "reports the army at its largest during the war" do
    created("Babylon", "UNIT_CANNON", turn: 202)
    created("Babylon", "UNIT_CANNON", turn: 203)
    lost("Babylon", "UNIT_CANNON", turn: 208)

    assert_equal({ turn: 203, units: { "UNIT_CANNON" => 2 } },
                 during(war(turn: 201, turn_peace: 210))["Babylon"][:peak])
  end

  test "reports the army at its smallest during the war" do
    created("Babylon", "UNIT_CANNON", turn: 200)
    created("Babylon", "UNIT_CANNON", turn: 200)
    lost("Babylon", "UNIT_CANNON", turn: 204)
    lost("Babylon", "UNIT_CANNON", turn: 205)
    created("Babylon", "UNIT_ARTILLERY", turn: 208)

    assert_equal({ turn: 205, units: {} },
                 during(war(turn: 201, turn_peace: 210))["Babylon"][:nadir])
  end

  # More than one turn can stand below both ends of the war. The one worth
  # reporting is the deepest, not the first one down.
  test "reports the deepest low rather than the first one" do
    3.times { created("Babylon", "UNIT_CANNON", turn: 200) }
    lost("Babylon", "UNIT_CANNON", turn: 202)
    lost("Babylon", "UNIT_CANNON", turn: 203)
    created("Babylon", "UNIT_CANNON", turn: 208)
    2.times { created("Babylon", "UNIT_CANNON", turn: 209) }

    assert_equal 203, during(war(turn: 201, turn_peace: 210))["Babylon"][:nadir][:turn]
  end

  # A strength reached, held, lost and reached again belongs to the turn
  # the army first stood that tall.
  test "reports the turn a peak was first reached rather than the last it was held" do
    created("Babylon", "UNIT_CANNON", turn: 202)
    created("Babylon", "UNIT_CANNON", turn: 203)
    lost("Babylon", "UNIT_CANNON", turn: 205)
    created("Babylon", "UNIT_CANNON", turn: 207)
    lost("Babylon", "UNIT_CANNON", turn: 209)

    assert_equal 203, during(war(turn: 201, turn_peace: 210))["Babylon"][:peak][:turn]
  end

  # An army that only grew peaked at the peace and was smallest at the
  # declaration, and saying so twice tells the reader nothing new.
  test "leaves out a peak and a nadir that fall on the ends of the war" do
    created("Babylon", "UNIT_CANNON", turn: 202)
    created("Babylon", "UNIT_CANNON", turn: 208)

    side = during(war(turn: 201, turn_peace: 210))["Babylon"]

    assert_nil side[:peak]
    assert_nil side[:nadir]
  end

  private

  def roster(turn, civ) = OrderOfBattle.new(@game).at(turn, civ)

  def during(war) = OrderOfBattle.new(@game).during(war)

  def war(turn: 201, turn_peace: nil, attacker_civs: [ "Babylon" ], defender_civs: [ "Philippines" ])
    { type: :war, turn: turn, turn_peace: turn_peace,
      attacker_civs: attacker_civs, defender_civs: defender_civs }
  end

  # An upgrade shows up three times: the new unit is created, the old one
  # is lost, and the game says which became which.
  def upgraded(civ, from, to, turn:)
    created(civ, to, turn: turn)
    event("unit_upgraded", turn, "civ" => civ, "from" => from, "to" => to)
    lost(civ, from, turn: turn)
  end

  def created(civ, unit, turn:)
    event("unit_created", turn, "civ" => civ, "unit" => unit)
  end

  def lost(civ, unit, turn:)
    event("unit_lost", turn, "civ" => civ, "unit" => unit)
  end

  def event(type, turn, payload)
    @game.game_events.create!(
      seq: @seq += 1, session_index: 0, turn: turn, event_type: type, civ: payload["civ"],
      payload: payload.merge("event" => type, "turn" => turn)
    )
  end
end
