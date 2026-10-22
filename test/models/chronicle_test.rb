require "test_helper"

class ChronicleTest < ActiveSupport::TestCase
  test "valid with a model, content and a game" do
    chronicle = Chronicle.new(game: games(:one), model: "gpt-4o-mini", content: "In the first years...")
    assert chronicle.valid?
  end

  test "invalid without a model" do
    chronicle = Chronicle.new(game: games(:one), model: nil, content: "In the first years...")
    assert_not chronicle.valid?
    assert_includes chronicle.errors[:model], "can't be blank"
  end

  test "invalid without content" do
    chronicle = Chronicle.new(game: games(:one), model: "gpt-4o-mini", content: nil)
    assert_not chronicle.valid?
    assert_includes chronicle.errors[:content], "can't be blank"
  end

  test "defaults digest to an empty hash" do
    chronicle = Chronicle.create!(game: games(:one), model: "gpt-4o-mini", content: "chronicle")
    assert_equal({}, chronicle.digest)
  end

  test "belongs to a game" do
    chronicle = Chronicle.create!(game: games(:one), model: "gpt-4o-mini", content: "chronicle")
    assert_equal games(:one), chronicle.game
  end
end
