require "test_helper"

class ChroniclesControllerTest < ActionDispatch::IntegrationTest
  test "show renders a specific chronicle's content as markdown" do
    game = Game.create!(name: "History Game")
    chronicle = game.chronicles.create!(model: "m", content: "# A Chronicle", digest: {})

    get game_chronicle_url(game, chronicle)

    assert_response :success
    assert_select "h1", "A Chronicle"
    assert_match "m", response.body
  end

  test "show 404s for a chronicle id that doesn't belong to the game" do
    game = Game.create!(name: "History Game")
    other_game = Game.create!(name: "Other Game")
    other_chronicle = other_game.chronicles.create!(model: "m", content: "chronicle", digest: {})

    get game_chronicle_url(game, other_chronicle)

    assert_response :not_found
  end

  test "show links to the prompt snapshot" do
    game = Game.create!(name: "History Game")
    chronicle = game.chronicles.create!(model: "m", content: "chronicle", digest: {}, prompt: "system prompt text")

    get game_chronicle_url(game, chronicle)

    assert_response :success
    assert_select "a[href=?]", prompt_game_chronicle_path(game, chronicle)
  end

  test "prompt displays the snapshot of the prompt used to generate the chronicle" do
    game = Game.create!(name: "History Game")
    chronicle = game.chronicles.create!(model: "m", content: "chronicle", digest: {}, prompt: "You are a chronicler.")

    get prompt_game_chronicle_url(game, chronicle)

    assert_response :success
    assert_match "You are a chronicler.", response.body
  end

  test "prompt 404s for a chronicle id that doesn't belong to the game" do
    game = Game.create!(name: "History Game")
    other_game = Game.create!(name: "Other Game")
    other_chronicle = other_game.chronicles.create!(model: "m", content: "chronicle", digest: {})

    get prompt_game_chronicle_url(game, other_chronicle)

    assert_response :not_found
  end

  test "show links to the digest snapshot" do
    game = Game.create!(name: "History Game")
    chronicle = game.chronicles.create!(model: "m", content: "chronicle", digest: {})

    get game_chronicle_url(game, chronicle)

    assert_response :success
    assert_select "a[href=?]", digest_game_chronicle_path(game, chronicle)
  end

  test "digest renders every top-level projection as its own collapsible section" do
    game = Game.create!(name: "History Game")
    chronicle = game.chronicles.create!(
      model: "m", content: "chronicle",
      digest: { "roster" => [ { "civ" => "ROME" } ], "espionage" => { "applicable" => false } }
    )

    get digest_game_chronicle_url(game, chronicle)

    assert_response :success
    assert_select "details summary", text: /roster/
    assert_select "details summary", text: /espionage/
    assert_match "ROME", response.body
  end

  test "digest 404s for a chronicle id that doesn't belong to the game" do
    game = Game.create!(name: "History Game")
    other_game = Game.create!(name: "Other Game")
    other_chronicle = other_game.chronicles.create!(model: "m", content: "chronicle", digest: {})

    get digest_game_chronicle_url(game, other_chronicle)

    assert_response :not_found
  end

  test "show does not render the prompt or the raw digest inline" do
    game = Game.create!(name: "History Game")
    chronicle = game.chronicles.create!(
      model: "m", content: "chronicle", digest: { "roster" => [ { "civ" => "ROME" } ] },
      prompt: "a very distinctive system prompt sentence"
    )

    get game_chronicle_url(game, chronicle)

    assert_response :success
    assert_no_match "a very distinctive system prompt sentence", response.body
    assert_no_match "ROME", response.body
  end
end
