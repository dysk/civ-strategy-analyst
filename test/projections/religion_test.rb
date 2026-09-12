require "test_helper"

class ReligionTest < ActiveSupport::TestCase
  setup do
    @game = Game.create!(name: "Religion Test Game")
    @seq = 0
  end

  test "applicable? is false when the log carries no city_converted" do
    assert_not Religion.new(@game).applicable?
  end

  test "applicable? is true once a conversion is logged" do
    converted(50, "India", "Delhi", "RELIGION_HINDUISM")

    assert Religion.new(@game).applicable?
  end

  test "a single conversion is a hold running from that turn to itself" do
    converted(50, "India", "Delhi", "RELIGION_HINDUISM")

    hold = Religion.new(@game).holds("India").first
    assert_equal({ civ: "India", city: "Delhi", religion: "RELIGION_HINDUISM",
                   from_turn: 50, to_turn: 50, settled: false },
                 hold)
  end

  test "repeated rows for the same religion are one hold, not one per row" do
    converted(50, "India", "Delhi", "RELIGION_HINDUISM")
    converted(55, "India", "Delhi", "RELIGION_HINDUISM")
    converted(60, "India", "Delhi", "RELIGION_HINDUISM")

    holds = Religion.new(@game).holds("India")
    assert_equal 1, holds.size
    assert_equal [ 50, 60 ], holds.first.values_at(:from_turn, :to_turn)
  end

  test "a different religion starts a new hold and closes the one before it" do
    converted(50, "India", "Delhi", "RELIGION_HINDUISM")
    converted(55, "India", "Delhi", "RELIGION_HINDUISM")
    converted(60, "India", "Delhi", "RELIGION_CATHOLICISM")

    holds = Religion.new(@game).holds("India")
    assert_equal %w[RELIGION_HINDUISM RELIGION_CATHOLICISM], holds.map { |h| h[:religion] }
    assert_equal [ 50, 55 ], holds.first.values_at(:from_turn, :to_turn)
    assert_equal [ 60, 60 ], holds.last.values_at(:from_turn, :to_turn)
  end

  # Vijayanagara, turns 105-110 (docs/religion.md): a three-way contested city
  # can flip its majority twice in a single turn.
  test "two different religions logged on the same turn are two zero-span holds" do
    converted(105, "India", "Vijayanagara", "RELIGION_CATHOLICISM")
    converted(105, "India", "Vijayanagara", "RELIGION_PROTESTANTISM")

    holds = Religion.new(@game).holds("India")
    assert_equal [ [ "RELIGION_CATHOLICISM", 105, 105 ], [ "RELIGION_PROTESTANTISM", 105, 105 ] ],
                 holds.map { |h| h.values_at(:religion, :from_turn, :to_turn) }
  end

  test "a hold with no later transition runs open-ended to the last row seen" do
    converted(50, "India", "Delhi", "RELIGION_HINDUISM")
    converted(80, "India", "Delhi", "RELIGION_HINDUISM")

    hold = Religion.new(@game).holds("India").first
    assert_equal 80, hold[:to_turn]
  end

  # Vijayanagara again (docs/religion.md): city_converted has nothing between
  # turn 137 and turn 168 because losing a religion to atheism is never
  # logged, but a silent atheism round-trip through that gap still shows up
  # in city_snapshot as the religion field going absent - so two rows naming
  # the same religion either side of that absence are two holds, not one.
  test "a snapshot's absent religion field mid-run splits it into two holds" do
    converted(110, "India", "Vijayanagara", "RELIGION_HINDUISM")
    snapshot(150, "India", "Vijayanagara")
    converted(168, "India", "Vijayanagara", "RELIGION_HINDUISM")

    holds = Religion.new(@game).holds("India")
    assert_equal [ [ "RELIGION_HINDUISM", 110, 110 ], [ "RELIGION_HINDUISM", 168, 168 ] ],
                 holds.map { |h| h.values_at(:religion, :from_turn, :to_turn) }
  end

  test "a snapshot confirming the same religion mid-run does not split it" do
    converted(50, "India", "Delhi", "RELIGION_HINDUISM")
    snapshot(52, "India", "Delhi", religion: "RELIGION_HINDUISM")
    converted(55, "India", "Delhi", "RELIGION_HINDUISM")

    holds = Religion.new(@game).holds("India")
    assert_equal 1, holds.size
    assert_equal [ 50, 55 ], holds.first.values_at(:from_turn, :to_turn)
  end

  test "two separate silent gaps split a run into three holds" do
    converted(50, "India", "Delhi", "RELIGION_HINDUISM")
    snapshot(55, "India", "Delhi")
    converted(60, "India", "Delhi", "RELIGION_HINDUISM")
    snapshot(65, "India", "Delhi")
    converted(70, "India", "Delhi", "RELIGION_HINDUISM")

    holds = Religion.new(@game).holds("India")
    assert_equal [ [ 50, 50 ], [ 60, 60 ], [ 70, 70 ] ], holds.map { |h| h.values_at(:from_turn, :to_turn) }
  end

  test "an absent-religion snapshot outside the gap between two rows does not split them" do
    snapshot(40, "India", "Delhi")
    converted(50, "India", "Delhi", "RELIGION_HINDUISM")
    converted(60, "India", "Delhi", "RELIGION_HINDUISM")
    snapshot(70, "India", "Delhi")

    holds = Religion.new(@game).holds("India")
    assert_equal 1, holds.size
    assert_equal [ 50, 60 ], holds.first.values_at(:from_turn, :to_turn)
  end

  test "a split hold's settled check runs against its own new boundary, not the original run's" do
    converted(110, "India", "Vijayanagara", "RELIGION_HINDUISM")
    snapshot(150, "India", "Vijayanagara")
    converted(168, "India", "Vijayanagara", "RELIGION_HINDUISM")

    first_hold = Religion.new(@game).holds("India").first
    assert_not first_hold[:settled]
  end

  test "each city's holds are reconstructed independently" do
    converted(50, "India", "Delhi", "RELIGION_HINDUISM")
    converted(52, "India", "Vijayanagara", "RELIGION_CATHOLICISM")
    converted(60, "India", "Delhi", "RELIGION_CATHOLICISM")

    holds = Religion.new(@game).holds("India")
    assert_equal %w[Delhi Vijayanagara Delhi], holds.map { |h| h[:city] }
  end

  test "holds are ordered by from_turn across cities" do
    converted(60, "India", "Delhi", "RELIGION_HINDUISM")
    converted(50, "India", "Vijayanagara", "RELIGION_CATHOLICISM")

    holds = Religion.new(@game).holds("India")
    assert_equal [ 50, 60 ], holds.map { |h| h[:from_turn] }
  end

  test "holds(civ) filters to that civ; holds() with no argument returns every civ's" do
    converted(50, "India", "Delhi", "RELIGION_HINDUISM")
    converted(52, "Tibet", "Lhasa", "RELIGION_BUDDHISM")

    religion = Religion.new(@game)
    assert_equal %w[India], religion.holds("India").map { |h| h[:civ] }
    assert_equal %w[India Tibet], religion.holds.map { |h| h[:civ] }.sort
  end

  # No city_snapshot anywhere in this game, so settled falls back to a plain
  # span - the user's own calibration, same footing as WONDER_RACE_MIN_INVESTED.
  test "settled falls back to a span once it crosses the threshold, with no snapshot to check against" do
    converted(50, "India", "Delhi", "RELIGION_HINDUISM")
    converted(54, "India", "Delhi", "RELIGION_HINDUISM")

    assert Religion.new(@game).holds("India").first[:settled]
  end

  test "a flicker shorter than the threshold is not settled with nothing to confirm it" do
    converted(50, "India", "Delhi", "RELIGION_HINDUISM")
    converted(52, "India", "Delhi", "RELIGION_HINDUISM")

    assert_not Religion.new(@game).holds("India").first[:settled]
  end

  # The event stream alone cannot tell a same-turn flicker from a lasting
  # conversion; a snapshot naming the same religion afterward can.
  test "a later city_snapshot naming the same religion settles a hold too short to prove itself" do
    converted(105, "India", "Vijayanagara", "RELIGION_HINDUISM")
    snapshot(107, "India", "Vijayanagara", religion: "RELIGION_HINDUISM")

    assert Religion.new(@game).holds("India").first[:settled]
  end

  test "a later city_snapshot naming a different religion means the hold never settled" do
    converted(105, "India", "Vijayanagara", "RELIGION_HINDUISM")
    snapshot(107, "India", "Vijayanagara", religion: "RELIGION_PROTESTANTISM")

    assert_not Religion.new(@game).holds("India").first[:settled]
  end

  # The omit rule: no majority religion is an absent field, not a null one.
  test "a later city_snapshot with no religion field at all means the hold never settled" do
    converted(105, "India", "Vijayanagara", "RELIGION_HINDUISM")
    snapshot(107, "India", "Vijayanagara")

    assert_not Religion.new(@game).holds("India").first[:settled]
  end

  # The snapshot channel outranks the span even when the span alone would
  # have been enough - it is the more trustworthy of the two per docs/religion.md.
  test "a contradicting snapshot overrules a span that would otherwise settle the hold" do
    converted(50, "India", "Delhi", "RELIGION_HINDUISM")
    converted(56, "India", "Delhi", "RELIGION_HINDUISM")
    snapshot(58, "India", "Delhi", religion: "RELIGION_CATHOLICISM")

    assert_not Religion.new(@game).holds("India").first[:settled]
  end

  test "a snapshot only before the hold started does not count as confirmation" do
    snapshot(40, "India", "Delhi", religion: "RELIGION_PANTHEON")
    converted(50, "India", "Delhi", "RELIGION_HINDUISM")
    converted(52, "India", "Delhi", "RELIGION_HINDUISM")

    assert_not Religion.new(@game).holds("India").first[:settled]
  end

  private

  def converted(turn, civ, city, religion)
    @seq += 1
    payload = { "event" => "city_converted", "turn" => turn, "civ" => civ, "city" => city, "religion" => religion }
    @game.game_events.create!(seq: @seq, session_index: 0, turn: turn,
                              event_type: "city_converted", civ: civ, payload: payload)
  end

  def snapshot(turn, civ, city, religion: nil)
    @seq += 1
    payload = { "event" => "city_snapshot", "turn" => turn, "civ" => civ, "city" => city }
    payload["religion"] = religion if religion
    @game.game_events.create!(seq: @seq, session_index: 0, turn: turn,
                              event_type: "city_snapshot", civ: civ, payload: payload)
  end
end
