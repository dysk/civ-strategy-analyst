require "test_helper"

class DiplomaticTiesTest < ActiveSupport::TestCase
  setup do
    @game = Game.create!(name: "Diplomatic Ties Test Game")
    @seq = 0
  end

  test "applicable? is false when the log carries none of the five tie types" do
    event("war_declared", nil, 10, attacker_civs: %w[Rome], defender_civs: %w[Greece])

    assert_not DiplomaticTies.new(@game).applicable?
  end

  test "applicable? is true when the log carries at least one tie event" do
    embassy("Rome", "Greece", 6, :established)

    assert DiplomaticTies.new(@game).applicable?
  end

  test "spans pairs a directional open with its close into one span" do
    embassy("Rome", "Greece", 6, :established)
    embassy("Greece", "Rome", 6, :established)
    embassy("Rome", "Greece", 40, :ended)
    embassy("Greece", "Rome", 40, :ended)

    assert_equal(
      [ { type: "embassy", from_turn: 6, to_turn: 40 } ],
      DiplomaticTies.new(@game).spans("Rome", "Greece")
    )
  end

  test "spans reads the pair regardless of which side is queried first" do
    embassy("Rome", "Greece", 6, :established)
    embassy("Greece", "Rome", 6, :established)

    assert_equal(
      DiplomaticTies.new(@game).spans("Rome", "Greece"),
      DiplomaticTies.new(@game).spans("Greece", "Rome")
    )
  end

  test "spans leaves to_turn nil for a tie still standing" do
    embassy("Rome", "Greece", 6, :established)
    embassy("Greece", "Rome", 6, :established)

    assert_equal(
      [ { type: "embassy", from_turn: 6, to_turn: nil } ],
      DiplomaticTies.new(@game).spans("Rome", "Greece")
    )
  end

  test "spans reads a one-directional open-borders grant with no reciprocal event" do
    open_borders("Rome", "Greece", 40, :granted)

    assert_equal(
      [ { type: "open_borders", from_turn: 40, to_turn: nil } ],
      DiplomaticTies.new(@game).spans("Rome", "Greece")
    )
  end

  test "spans reads a friendship declared as a single civs-array record" do
    friendship("Rome", "Greece", 179, :declared)

    assert_equal(
      [ { type: "friendship", from_turn: 179, to_turn: nil } ],
      DiplomaticTies.new(@game).spans("Rome", "Greece")
    )
  end

  test "spans combines every tie type standing between the pair, oldest first" do
    friendship("Rome", "Greece", 179, :declared)
    embassy("Rome", "Greece", 6, :established)
    embassy("Greece", "Rome", 6, :established)
    open_borders("Rome", "Greece", 40, :granted)

    assert_equal(
      [
        { type: "embassy", from_turn: 6, to_turn: nil },
        { type: "open_borders", from_turn: 40, to_turn: nil },
        { type: "friendship", from_turn: 179, to_turn: nil }
      ],
      DiplomaticTies.new(@game).spans("Rome", "Greece")
    )
  end

  test "spans ignores ties between other civs" do
    embassy("Rome", "Carthage", 6, :established)

    assert_equal [], DiplomaticTies.new(@game).spans("Rome", "Greece")
  end

  test "spans is empty for a pair with no ties" do
    assert_equal [], DiplomaticTies.new(@game).spans("Rome", "Greece")
  end

  test "spans cuts a tie open when war is declared to the declaration turn, overriding its own later close event" do
    embassy("Rome", "Greece", 86, :established)
    embassy("Greece", "Rome", 86, :established)
    event("war_declared", nil, 144, attacker_civs: %w[Rome], defender_civs: %w[Greece])
    embassy("Rome", "Greece", 145, :ended)
    embassy("Greece", "Rome", 145, :ended)

    assert_equal(
      [ { type: "embassy", from_turn: 86, to_turn: 144 } ],
      DiplomaticTies.new(@game).spans("Rome", "Greece")
    )
  end

  test "spans cuts a tie with no close event of its own to the war declaration turn" do
    embassy("Rome", "Greece", 86, :established)
    embassy("Greece", "Rome", 86, :established)
    event("war_declared", nil, 144, attacker_civs: %w[Rome], defender_civs: %w[Greece])

    assert_equal(
      [ { type: "embassy", from_turn: 86, to_turn: 144 } ],
      DiplomaticTies.new(@game).spans("Rome", "Greece")
    )
  end

  test "spans leaves a tie opened after an earlier war between the same pair alone" do
    event("war_declared", nil, 100, attacker_civs: %w[Rome], defender_civs: %w[Greece])
    embassy("Rome", "Greece", 150, :established)
    embassy("Greece", "Rome", 150, :established)

    assert_equal(
      [ { type: "embassy", from_turn: 150, to_turn: nil } ],
      DiplomaticTies.new(@game).spans("Rome", "Greece")
    )
  end

  test "spans leaves a tie alone when war is declared between other civs" do
    embassy("Rome", "Greece", 10, :established)
    embassy("Greece", "Rome", 10, :established)
    event("war_declared", nil, 50, attacker_civs: %w[Rome], defender_civs: %w[Carthage])

    assert_equal(
      [ { type: "embassy", from_turn: 10, to_turn: nil } ],
      DiplomaticTies.new(@game).spans("Rome", "Greece")
    )
  end

  private

  def embassy(civ, other_civ, turn, action)
    type = action == :established ? "embassy_established" : "embassy_ended"
    event(type, civ, turn, other_civ: other_civ)
  end

  def open_borders(civ, other_civ, turn, action)
    type = action == :granted ? "open_borders_granted" : "open_borders_revoked"
    event(type, civ, turn, other_civ: other_civ)
  end

  def friendship(civ, other_civ, turn, action)
    type = action == :declared ? "friendship_declared" : "friendship_ended"
    event(type, nil, turn, civs: [ civ, other_civ ])
  end

  def event(type, civ, turn, extra = {})
    payload = extra.stringify_keys.merge("event" => type, "turn" => turn)
    payload["civ"] = civ if civ
    @game.game_events.create!(seq: @seq += 1, session_index: 0, turn: turn, event_type: type, civ: civ, payload: payload)
  end
end
