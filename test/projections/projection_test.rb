require "test_helper"

class ProjectionTest < ActiveSupport::TestCase
  class Reader
    extend Projection

    attr_reader :game

    def initialize(game) = @game = game
  end

  class OtherReader < Reader
  end

  test "reads the game it was built for" do
    game = games(:one)

    assert_same game, Reader.for(game).game
  end

  test "builds one instance per game" do
    game = games(:one)

    assert_same Reader.for(game), Reader.for(game)
  end

  test "builds a separate instance per projection" do
    game = games(:one)

    assert_not_same Reader.for(game), OtherReader.for(game)
  end

  test "builds a separate instance per game" do
    assert_not_same Reader.for(games(:one)), Reader.for(games(:two))
  end
end
