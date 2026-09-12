require "test_helper"

# Fixture data lives in test/support/lekmod/1.5: RESOURCE_HORSE is strategic,
# RESOURCE_COCONUT is a luxury, and UNIT_HORSEMAN is the only unit that
# requires RESOURCE_HORSE - see ResourceRequirementsTest.
class ResourceShortagesTest < ActiveSupport::TestCase
  REQUIREMENTS_ROOT = Rails.root.join("test/support/lekmod")

  setup do
    @game = Game.create!(name: "Resource Shortages Test Game")
    @seq = 0
  end

  test "reports a strategic resource running below what is used as a deficit" do
    snapshot("Netherlands", 81, resources: [ { "resource" => "RESOURCE_HORSE", "total" => 0, "used" => 1 } ])

    deficit = shortages.deficits("Netherlands").first

    assert_equal "RESOURCE_HORSE", deficit[:resource]
    assert_equal 81, deficit[:turn]
  end

  test "does not report a resource whose total covers what is used" do
    snapshot("Netherlands", 81, resources: [ { "resource" => "RESOURCE_HORSE", "total" => 4, "used" => 1 } ])

    assert_empty shortages.deficits("Netherlands")
  end

  # The real trigger for this: Iroquois RESOURCE_COCONUT at total: -1, used: 0
  # in india-diplo - a negative total on a luxury nobody's unit needs, which
  # GetStrategicResourceCombatPenalty never reaches.
  test "does not report a luxury resource even when its total runs negative" do
    snapshot("Iroquois", 153, resources: [ { "resource" => "RESOURCE_COCONUT", "total" => -1, "used" => 0 } ])

    assert_empty shortages.deficits("Iroquois")
  end

  test "computes the deficit fraction as missing over used" do
    snapshot("Netherlands", 81, resources: [ { "resource" => "RESOURCE_HORSE", "total" => 0, "used" => 2 } ])

    assert_equal 1.0, shortages.deficits("Netherlands").first[:deficit_fraction]
  end

  test "derives the combat penalty by scaling the deficit fraction against the -50 floor" do
    snapshot("Netherlands", 81, resources: [ { "resource" => "RESOURCE_HORSE", "total" => 1, "used" => 2 } ])

    assert_equal(-25, shortages.deficits("Netherlands").first[:penalty])
  end

  test "a full deficit floors the penalty at -50" do
    snapshot("Netherlands", 81, resources: [ { "resource" => "RESOURCE_HORSE", "total" => 0, "used" => 1 } ])

    assert_equal(-50, shortages.deficits("Netherlands").first[:penalty])
  end

  test "names the civ's own unit that requires the deficit resource" do
    created("Netherlands", "UNIT_HORSEMAN", 50)
    snapshot("Netherlands", 81, resources: [ { "resource" => "RESOURCE_HORSE", "total" => 0, "used" => 1 } ])

    assert_equal [ "UNIT_HORSEMAN" ], shortages.deficits("Netherlands").first[:exposed_units]
  end

  test "does not expose a unit that does not require the deficit resource" do
    created("Netherlands", "UNIT_WORKER", 50)
    snapshot("Netherlands", 81, resources: [ { "resource" => "RESOURCE_HORSE", "total" => 0, "used" => 1 } ])

    assert_empty shortages.deficits("Netherlands").first[:exposed_units]
  end

  test "does not expose a horse-requiring unit lost before the deficit turn" do
    created("Netherlands", "UNIT_HORSEMAN", 50)
    lost("Netherlands", "UNIT_HORSEMAN", 60)
    snapshot("Netherlands", 81, resources: [ { "resource" => "RESOURCE_HORSE", "total" => 0, "used" => 1 } ])

    assert_empty shortages.deficits("Netherlands").first[:exposed_units]
  end

  test "ignores another civ's resource stock" do
    snapshot("Netherlands", 81, resources: [ { "resource" => "RESOURCE_HORSE", "total" => 0, "used" => 1 } ])

    assert_empty shortages.deficits("England")
  end

  # A reload can log a turn twice; the later payload is the state the turn
  # actually ended in - the same rule WonderRaces applies to city snapshots.
  test "the later snapshot wins when a turn is logged twice" do
    snapshot("Netherlands", 81, resources: [ { "resource" => "RESOURCE_HORSE", "total" => 4, "used" => 1 } ])
    snapshot("Netherlands", 81, resources: [ { "resource" => "RESOURCE_HORSE", "total" => 0, "used" => 1 } ])

    assert_equal 1, shortages.deficits("Netherlands").size
  end

  test "is applicable when the log carries a resources list on any snapshot" do
    snapshot("Netherlands", 81, resources: [ { "resource" => "RESOURCE_HORSE", "total" => 4, "used" => 1 } ])

    assert shortages.applicable?
  end

  test "is not applicable when no snapshot carries a resources list" do
    event("Netherlands", "snapshot", 81, score: 100)

    assert_not shortages.applicable?
  end

  test "reports deficits across turns in turn order" do
    snapshot("Netherlands", 90, resources: [ { "resource" => "RESOURCE_HORSE", "total" => 0, "used" => 1 } ])
    snapshot("Netherlands", 81, resources: [ { "resource" => "RESOURCE_HORSE", "total" => 0, "used" => 1 } ])

    assert_equal [ 81, 90 ], shortages.deficits("Netherlands").map { |d| d[:turn] }
  end

  private

  def shortages
    ResourceShortages.new(@game, requirements: ResourceRequirements.for("1.5", root: REQUIREMENTS_ROOT))
  end

  def snapshot(civ, turn, resources:)
    event(civ, "snapshot", turn, resources: resources)
  end

  def created(civ, unit, turn)
    event(civ, "unit_created", turn, unit: unit)
  end

  def lost(civ, unit, turn)
    event(civ, "unit_lost", turn, unit: unit)
  end

  def event(civ, event_type, turn, extra = {})
    @seq += 1
    payload = extra.stringify_keys.merge("event" => event_type, "turn" => turn, "civ" => civ)
    @game.game_events.create!(
      seq: @seq, session_index: 0, turn: turn, event_type: event_type, civ: civ, payload: payload
    )
  end
end
