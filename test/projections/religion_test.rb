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
    assert_equal({ civ: "India", city: "Delhi", religion: "RELIGION_HINDUISM", from_turn: 50, to_turn: 50 },
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

  private

  def converted(turn, civ, city, religion)
    @seq += 1
    payload = { "event" => "city_converted", "turn" => turn, "civ" => civ, "city" => city, "religion" => religion }
    @game.game_events.create!(seq: @seq, session_index: 0, turn: turn,
                              event_type: "city_converted", civ: civ, payload: payload)
  end
end
