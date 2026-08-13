require "test_helper"

class GameTest < ActiveSupport::TestCase
  test "valid with a name" do
    game = Game.new(name: "Test Game")
    assert game.valid?
  end

  test "invalid without a name" do
    game = Game.new(name: nil)
    assert_not game.valid?
    assert_includes game.errors[:name], "can't be blank"
  end

  test "defaults completed to false" do
    game = Game.create!(name: "New Game")
    assert_equal false, game.completed
  end

  test "has many players destroyed with the game" do
    game = games(:one)
    assert_includes game.players, players(:one)

    assert_difference("Player.count", -1) do
      game.destroy
    end
  end

  test "has many game_events destroyed with the game" do
    game = games(:one)
    assert_includes game.game_events, game_events(:one)

    assert_difference("GameEvent.count", -1) do
      game.destroy
    end
  end

  test "has many analyses destroyed with the game" do
    game = games(:one)
    assert_includes game.analyses, analyses(:one)

    assert_difference("Analysis.count", -1) do
      game.destroy
    end
  end
end
