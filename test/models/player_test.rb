require "test_helper"

class PlayerTest < ActiveSupport::TestCase
  test "valid with a civ and a game" do
    player = Player.new(game: games(:one), civ: "Egypt")
    assert player.valid?
  end

  test "invalid without a civ" do
    player = Player.new(game: games(:one), civ: nil)
    assert_not player.valid?
    assert_includes player.errors[:civ], "can't be blank"
  end

  test "invalid without a game" do
    player = Player.new(civ: "Egypt", game: nil)
    assert_not player.valid?
    assert_includes player.errors[:game], "must exist"
  end

  test "invalid with duplicate civ in the same game" do
    duplicate = Player.new(game: games(:one), civ: players(:one).civ)
    assert_not duplicate.valid?
    assert_includes duplicate.errors[:civ], "has already been taken"
  end

  test "valid with the same civ in a different game" do
    player = Player.new(game: games(:two), civ: players(:one).civ)
    assert player.valid?
  end

  test "defaults human to false" do
    player = Player.create!(game: games(:one), civ: "Egypt")
    assert_equal false, player.human
  end

  test "belongs to a game" do
    assert_equal games(:one), players(:one).game
  end
end
