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

  test "show links to the prompt snapshot" do
    game = Game.create!(name: "History Game")
    analysis = game.analyses.create!(model: "m", report: "report", digest: {}, prompt: "system prompt text")

    get game_analysis_url(game, analysis)

    assert_response :success
    assert_select "a[href=?]", prompt_game_analysis_path(game, analysis)
  end

  test "prompt displays the snapshot of the prompt used to generate the analysis" do
    game = Game.create!(name: "History Game")
    analysis = game.analyses.create!(model: "m", report: "report", digest: {}, prompt: "You are a strategy analyst.")

    get prompt_game_analysis_url(game, analysis)

    assert_response :success
    assert_match "You are a strategy analyst.", response.body
  end

  test "prompt 404s for an analysis id that doesn't belong to the game" do
    game = Game.create!(name: "History Game")
    other_game = Game.create!(name: "Other Game")
    other_analysis = other_game.analyses.create!(model: "m", report: "report", digest: {})

    get prompt_game_analysis_url(game, other_analysis)

    assert_response :not_found
  end

  test "show links to the digest snapshot" do
    game = Game.create!(name: "History Game")
    analysis = game.analyses.create!(model: "m", report: "report", digest: {})

    get game_analysis_url(game, analysis)

    assert_response :success
    assert_select "a[href=?]", digest_game_analysis_path(game, analysis)
  end

  test "digest renders every top-level projection as its own collapsible section" do
    game = Game.create!(name: "History Game")
    analysis = game.analyses.create!(
      model: "m", report: "report",
      digest: { "roster" => [ { "civ" => "ROME" } ], "espionage" => { "applicable" => false } }
    )

    get digest_game_analysis_url(game, analysis)

    assert_response :success
    assert_select "details summary", text: /roster/
    assert_select "details summary", text: /espionage/
    assert_match "ROME", response.body
    assert_match "applicable", response.body
  end

  test "digest flags an empty section" do
    game = Game.create!(name: "History Game")
    analysis = game.analyses.create!(model: "m", report: "report", digest: { "buffer_cities" => {} })

    get digest_game_analysis_url(game, analysis)

    assert_select "details.digest-section--empty summary", text: /buffer_cities/
  end

  test "digest flags a section marked not applicable" do
    game = Game.create!(name: "History Game")
    analysis = game.analyses.create!(model: "m", report: "report", digest: { "religion" => { "applicable" => false, "reason" => "no_conversions" } })

    get digest_game_analysis_url(game, analysis)

    assert_select "details.digest-section--empty summary", text: /religion/
  end

  test "digest does not flag a section that has data" do
    game = Game.create!(name: "History Game")
    analysis = game.analyses.create!(model: "m", report: "report", digest: { "roster" => [ { "civ" => "ROME" } ] })

    get digest_game_analysis_url(game, analysis)

    assert_select "details.digest-section--empty", false
  end

  test "digest links out to the dedicated page for sections that already have one" do
    game = Game.create!(name: "History Game")
    analysis = game.analyses.create!(
      model: "m", report: "report",
      digest: {
        "espionage" => { "applicable" => true }, "cultural" => {}, "congress" => {},
        "victory_progress" => {}, "roster" => []
      }
    )

    get digest_game_analysis_url(game, analysis)

    assert_select "details summary a[href=?]", game_espionage_path(game)
    assert_select "details summary a[href=?]", game_cultural_path(game)
    assert_select "details summary a[href=?]", game_congress_path(game)
    assert_select "details summary a[href=?]", game_victory_progress_path(game)
  end

  test "digest 404s for an analysis id that doesn't belong to the game" do
    game = Game.create!(name: "History Game")
    other_game = Game.create!(name: "Other Game")
    other_analysis = other_game.analyses.create!(model: "m", report: "report", digest: {})

    get digest_game_analysis_url(game, other_analysis)

    assert_response :not_found
  end
end
