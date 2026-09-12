require "test_helper"

# CvDeal is unreachable from Lua, so no event ever names a deal directly.
# `snapshot.resources[]` gives each civ's own import/export per resource
# per turn, and the only signal available is co-occurrence: one civ
# exporting a resource the same turn another civ imports it.
# docs/reading-the-new-log.md §11.
class DealsTest < ActiveSupport::TestCase
  setup do
    @game = Game.create!(name: "Deals Test Game")
    @seq = 0
  end

  # -- applicable? --

  test "applicable? is false when no snapshot carries a resources list" do
    snapshot("Netherlands", 10, resources: [])

    assert_not Deals.new(@game).applicable?
  end

  test "applicable? is true once a snapshot carries a resources list" do
    snapshot("Netherlands", 10, resources: [ { "resource" => "RESOURCE_WINE", "total" => 1, "used" => 0, "import" => 1, "export" => 0 } ])

    assert Deals.new(@game).applicable?
  end

  # -- matches --

  test "matches one civ's export against another's import of the same resource on the same turn" do
    resource_flow("Tibet", 19, "RESOURCE_WINE", import: 0, export: 1)
    resource_flow("Netherlands", 19, "RESOURCE_WINE", import: 1, export: 0)

    assert_equal(
      [ { resource: "RESOURCE_WINE", exporter: "Tibet", importer: "Netherlands", from_turn: 19, to_turn: 19 } ],
      Deals.new(@game).matches
    )
  end

  test "matches a strategic resource exactly like a luxury - CvDeal trades both" do
    resource_flow("Netherlands", 19, "RESOURCE_HORSE", import: 0, export: 4)
    resource_flow("Tibet", 19, "RESOURCE_HORSE", import: 4, export: 0)

    assert_equal(
      [ { resource: "RESOURCE_HORSE", exporter: "Netherlands", importer: "Tibet", from_turn: 19, to_turn: 19 } ],
      Deals.new(@game).matches
    )
  end

  test "collapses consecutive turns of the same pairing into one span" do
    (19..25).each do |turn|
      resource_flow("Tibet", turn, "RESOURCE_WINE", import: 0, export: 1)
      resource_flow("Netherlands", turn, "RESOURCE_WINE", import: 1, export: 0)
    end

    assert_equal(
      [ { resource: "RESOURCE_WINE", exporter: "Tibet", importer: "Netherlands", from_turn: 19, to_turn: 25 } ],
      Deals.new(@game).matches
    )
  end

  test "splits into two spans when the pairing drops out for a turn" do
    resource_flow("Tibet", 19, "RESOURCE_WINE", import: 0, export: 1)
    resource_flow("Netherlands", 19, "RESOURCE_WINE", import: 1, export: 0)
    # turn 20: no flow at all - the deal lapses for a turn
    resource_flow("Tibet", 21, "RESOURCE_WINE", import: 0, export: 1)
    resource_flow("Netherlands", 21, "RESOURCE_WINE", import: 1, export: 0)

    assert_equal(
      [
        { resource: "RESOURCE_WINE", exporter: "Tibet", importer: "Netherlands", from_turn: 19, to_turn: 19 },
        { resource: "RESOURCE_WINE", exporter: "Tibet", importer: "Netherlands", from_turn: 21, to_turn: 21 }
      ],
      Deals.new(@game).matches
    )
  end

  test "does not match when one exporter's resource is split across two importers on the same turn" do
    # The real trigger: Netherlands exported RESOURCE_HORSE 7/turn to both
    # Zimbabwe and Tibet at once in india-diplo - the two shares can't be
    # told apart, so neither is reported as a match.
    resource_flow("Netherlands", 34, "RESOURCE_HORSE", import: 0, export: 7)
    resource_flow("Zimbabwe", 34, "RESOURCE_HORSE", import: 3, export: 0)
    resource_flow("Tibet", 34, "RESOURCE_HORSE", import: 4, export: 0)

    assert_empty Deals.new(@game).matches
  end

  test "does not match when two civs export the same resource to one importer on the same turn" do
    resource_flow("England", 57, "RESOURCE_IRON", import: 0, export: 5)
    resource_flow("Zimbabwe", 57, "RESOURCE_IRON", import: 0, export: 5)
    resource_flow("Iroquois", 57, "RESOURCE_IRON", import: 5, export: 0)

    assert_empty Deals.new(@game).matches
  end

  test "matches two different resources traded the same turn independently" do
    resource_flow("Tibet", 19, "RESOURCE_WINE", import: 0, export: 1)
    resource_flow("Netherlands", 19, "RESOURCE_WINE", import: 1, export: 0)
    resource_flow("Netherlands", 19, "RESOURCE_HORSE", import: 0, export: 4)
    resource_flow("Tibet", 19, "RESOURCE_HORSE", import: 4, export: 0)

    assert_equal(
      [
        { resource: "RESOURCE_WINE", exporter: "Tibet", importer: "Netherlands", from_turn: 19, to_turn: 19 },
        { resource: "RESOURCE_HORSE", exporter: "Netherlands", importer: "Tibet", from_turn: 19, to_turn: 19 }
      ],
      Deals.new(@game).matches
    )
  end

  test "ignores a resource row carrying neither an import nor an export" do
    resource_flow("Netherlands", 19, "RESOURCE_WINE", import: 0, export: 0)
    resource_flow("Tibet", 19, "RESOURCE_WINE", import: 0, export: 0)

    assert_empty Deals.new(@game).matches
  end

  # -- unattributed_imports --

  test "reports an import with no exporter the same turn as unattributed" do
    resource_flow("Netherlands", 61, "RESOURCE_SILVER", import: 1, export: 0)

    assert_equal(
      [ { civ: "Netherlands", resource: "RESOURCE_SILVER", turn: 61, amount: 1 } ],
      Deals.new(@game).unattributed_imports
    )
  end

  test "does not report an import as unattributed once a major exports it the same turn" do
    resource_flow("Netherlands", 19, "RESOURCE_WINE", import: 1, export: 0)
    resource_flow("Tibet", 19, "RESOURCE_WINE", import: 0, export: 1)

    assert_empty Deals.new(@game).unattributed_imports
  end

  test "does not report a civ's own export as unattributed" do
    resource_flow("Tibet", 61, "RESOURCE_SILVER", import: 0, export: 1)

    assert_empty Deals.new(@game).unattributed_imports
  end

  private

  def snapshot(civ, turn, resources:)
    event(civ, turn, resources: resources)
  end

  # A real snapshot carries every resource row in one payload - accumulate
  # calls for the same (civ, turn) into the same event rather than one
  # snapshot per resource, which would just overwrite the row before.
  def resource_flow(civ, turn, resource, import:, export:)
    existing = @snapshots ||= {}
    row = { "resource" => resource, "total" => 0, "used" => 0, "import" => import, "export" => export }
    event = existing[[ civ, turn ]]

    if event
      event.payload["resources"] << row
      event.save!
    else
      existing[[ civ, turn ]] = event(civ, turn, resources: [ row ])
    end
  end

  def event(civ, turn, extra)
    @seq += 1
    payload = extra.stringify_keys.merge("event" => "snapshot", "turn" => turn, "civ" => civ)
    @game.game_events.create!(
      seq: @seq, session_index: 0, turn: turn, event_type: "snapshot", civ: civ, payload: payload
    )
  end
end
