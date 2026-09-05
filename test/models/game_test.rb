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

  test "knows a Pangaea map by the script that drew it" do
    game = Game.new(name: "Test Game", map_script: 'Assets\\Maps\\Lekmap v5.2\\LekmapPangaeaFractalv5.2.lua')

    assert_predicate game, :pangaea?
  end

  test "any other map script is not Pangaea" do
    refute_predicate Game.new(name: "Test Game", map_script: "Continents"), :pangaea?
  end

  test "a game with no map script recorded is not Pangaea" do
    refute_predicate Game.new(name: "Test Game"), :pangaea?
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

  test "event_log covers the game's events" do
    game = games(:one)

    assert_equal game.game_events.map(&:id).sort, game.event_log.all.map(&:id).sort
  end

  # Every projection reading one game reads one log, so the events are
  # loaded and indexed once no matter how many of them ask.
  test "event_log loads once per game" do
    game = games(:one)

    assert_same game.event_log, game.event_log
  end

  test "projection holds what was built for it" do
    game = games(:one)

    assert_equal :held, game.projection(:reader) { :held }
  end

  # Building a projection indexes the whole log, so the digest asking for
  # the same one thirteen times must not index it thirteen times.
  test "projection builds once per key" do
    game = games(:one)
    game.projection(:reader) { :first }

    assert_equal :first, game.projection(:reader) { :second }
  end

  test "projection keeps its keys apart" do
    game = games(:one)
    game.projection(:reader) { :first }

    assert_equal :second, game.projection(:other_reader) { :second }
  end

  test "has many analyses destroyed with the game" do
    game = games(:one)
    assert_includes game.analyses, analyses(:one)

    assert_difference("Analysis.count", -1) do
      game.destroy
    end
  end
end
