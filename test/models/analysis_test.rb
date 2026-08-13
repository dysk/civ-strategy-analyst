require "test_helper"

class AnalysisTest < ActiveSupport::TestCase
  test "valid with a model, a report and a game" do
    analysis = Analysis.new(game: games(:one), model: "gpt-4o-mini", report: "Some report")
    assert analysis.valid?
  end

  test "invalid without a model" do
    analysis = Analysis.new(game: games(:one), model: nil, report: "Some report")
    assert_not analysis.valid?
    assert_includes analysis.errors[:model], "can't be blank"
  end

  test "invalid without a report" do
    analysis = Analysis.new(game: games(:one), model: "gpt-4o-mini", report: nil)
    assert_not analysis.valid?
    assert_includes analysis.errors[:report], "can't be blank"
  end

  test "defaults digest to an empty hash" do
    analysis = Analysis.create!(game: games(:one), model: "gpt-4o-mini", report: "Some report")
    assert_equal({}, analysis.digest)
  end

  test "belongs to a game" do
    assert_equal games(:one), analyses(:one).game
  end
end
