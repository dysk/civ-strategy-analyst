require "test_helper"

class AnalysesControllerTest < ActionDispatch::IntegrationTest
  test "index lists analyses newest first with the model used" do
    game = Game.create!(name: "History Game")
    older = travel_to(2.days.ago) { game.analyses.create!(model: "claude-haiku-4-5", report: "older", digest: {}) }
    newer = travel_to(1.day.ago) { game.analyses.create!(model: "claude-sonnet-4-6", report: "newer", digest: {}) }

    get game_analyses_url(game)

    assert_response :success
    assert_match "claude-haiku-4-5", response.body
    assert_match "claude-sonnet-4-6", response.body
    assert_operator response.body.index("claude-sonnet-4-6"), :<, response.body.index("claude-haiku-4-5")
  end

  test "index links each analysis to its own page" do
    game = Game.create!(name: "History Game")
    analysis = game.analyses.create!(model: "m", report: "report", digest: {})

    get game_analyses_url(game)

    assert_select "a[href=?]", game_analysis_path(game, analysis)
  end

  test "show renders a specific analysis's report as markdown" do
    game = Game.create!(name: "History Game")
    old_analysis = game.analyses.create!(model: "old-model", report: "# Old Verdict", digest: {})
    game.analyses.create!(model: "new-model", report: "# New Verdict", digest: {})

    get game_analysis_url(game, old_analysis)

    assert_response :success
    assert_select "h1", "Old Verdict"
    assert_match "old-model", response.body
  end

  test "show 404s for an analysis id that doesn't belong to the game" do
    game = Game.create!(name: "History Game")
    other_game = Game.create!(name: "Other Game")
    other_analysis = other_game.analyses.create!(model: "m", report: "report", digest: {})

    get game_analysis_url(game, other_analysis)

    assert_response :not_found
  end
end
