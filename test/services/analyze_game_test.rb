require "test_helper"
require "tmpdir"

class AnalyzeGameTest < ActiveSupport::TestCase
  LEKMOD_FIXTURES_ROOT = Rails.root.join("test/support/lekmod")

  setup do
    @game = Game.create!(name: "Analyze Test Game", max_turns: 100)
    @game.game_events.create!(
      seq: 1, session_index: 0, turn: 10, event_type: "snapshot", civ: "Rome",
      payload: { "event" => "snapshot", "turn" => 10, "civ" => "Rome", "score" => 100 }
    )
    @reports_dir = Dir.mktmpdir
  end

  teardown do
    FileUtils.remove_entry(@reports_dir)
  end

  test "sends the digest and prompt to the injected llm client, and saves the report" do
    stub = StubLlmClient.new(content: "## Final Standings\n\nRome is winning.")

    analysis = AnalyzeGame.new(
      @game, winner_civ: "Rome", victory_type: "domination",
      model: "test-model", llm_client: stub, reports_dir: @reports_dir
    ).call

    expected_digest = DigestBuilder.new(@game, winner_civ: "Rome", victory_type: "domination").call
    assert_equal "test-model", stub.received[:model]
    assert_equal File.read(Rails.root.join("app/prompts/analyze_game.md")), stub.received[:system_prompt]
    assert_equal JSON.parse(expected_digest.to_json), JSON.parse(stub.received[:input])
  end

  test "persists the analysis with model, report, digest, tokens and cost" do
    stub = StubLlmClient.new(
      content: "## Final Standings\n\nRome is winning.",
      input_tokens: 1200, output_tokens: 340, cost_usd: 0.0321
    )

    analysis = AnalyzeGame.new(
      @game, winner_civ: "Rome", model: "test-model", llm_client: stub, reports_dir: @reports_dir
    ).call

    assert analysis.persisted?
    assert_equal @game, analysis.game
    assert_equal "test-model", analysis.model
    assert_equal "## Final Standings\n\nRome is winning.", analysis.report
    assert_equal "Rome", analysis.digest["outcome"]["winner_civ"]
    assert_equal 1200, analysis.input_tokens
    assert_equal 340, analysis.output_tokens
    assert_in_delta 0.0321, analysis.cost_usd, 0.0001
  end

  test "persists a snapshot of the prompt used to generate the report" do
    stub = StubLlmClient.new(content: "report")

    analysis = AnalyzeGame.new(@game, model: "test-model", llm_client: stub, reports_dir: @reports_dir).call

    assert_equal File.read(Rails.root.join("app/prompts/analyze_game.md")), analysis.prompt
  end

  test "persists nil tokens and cost when the llm client doesn't report them" do
    stub = StubLlmClient.new(content: "report")

    analysis = AnalyzeGame.new(@game, llm_client: stub, reports_dir: @reports_dir).call

    assert_nil analysis.input_tokens
    assert_nil analysis.output_tokens
    assert_nil analysis.cost_usd
  end

  test "defaults the model to RubyLLM's configured default when none is given" do
    stub = StubLlmClient.new(content: "report")

    analysis = AnalyzeGame.new(@game, llm_client: stub, reports_dir: @reports_dir).call

    assert_equal RubyLLM.config.default_model, analysis.model
    assert_equal RubyLLM.config.default_model, stub.received[:model]
  end

  test "persists nil lekmod_version when neither the game nor an override provides one" do
    stub = StubLlmClient.new(content: "report")

    analysis = AnalyzeGame.new(@game, llm_client: stub, reports_dir: @reports_dir).call

    assert_nil analysis.lekmod_version
  end

  test "resolves lekmod_version from the game when no override is given" do
    @game.update!(lekmod_version: "34.15")
    stub = StubLlmClient.new(content: "report")

    analysis = AnalyzeGame.new(@game, llm_client: stub, reports_dir: @reports_dir).call

    assert_equal "34.15", analysis.lekmod_version
  end

  test "overrides the game's stored lekmod_version when given explicitly" do
    @game.update!(lekmod_version: "34.10")
    stub = StubLlmClient.new(content: "report")

    analysis = AnalyzeGame.new(
      @game, lekmod_version: "34.15", llm_client: stub, reports_dir: @reports_dir
    ).call

    assert_equal "34.15", analysis.lekmod_version
  end

  test "resolves lekmod reference data into the digest using the game's stored version" do
    @game.update!(lekmod_version: "1.5")
    @game.players.create!(civ: "Chile", leader_name: "Test", human: true, handicap: "PRINCE")
    stub = StubLlmClient.new(content: "report")

    analysis = AnalyzeGame.new(
      @game, llm_client: stub, reports_dir: @reports_dir, lekmod_root: LEKMOD_FIXTURES_ROOT
    ).call

    assert_equal "1.5", analysis.digest["lekmod"]["version"]
    assert_equal [ "Chile" ], analysis.digest["lekmod"]["civilizations"].keys
    assert_match(/v1\.5 text for Chile/, analysis.digest["lekmod"]["civilizations"]["Chile"])
  end

  test "resolves lekmod reference data using an explicit override instead of the game's stored version" do
    @game.update!(lekmod_version: "1.0")
    stub = StubLlmClient.new(content: "report")

    analysis = AnalyzeGame.new(
      @game, lekmod_version: "1.5", llm_client: stub, reports_dir: @reports_dir, lekmod_root: LEKMOD_FIXTURES_ROOT
    ).call

    assert_equal "1.5", analysis.digest["lekmod"]["version"]
  end

  test "writes the report to reports_dir as <game>-<timestamp>.md" do
    stub = StubLlmClient.new(content: "## Final Standings\n\nRome is winning.")

    travel_to Time.utc(2026, 1, 2, 3, 4, 5) do
      AnalyzeGame.new(@game, model: "test-model", llm_client: stub, reports_dir: @reports_dir).call
    end

    expected_path = File.join(@reports_dir, "analyze-test-game-20260102030405.md")
    assert File.exist?(expected_path)
    assert_equal "## Final Standings\n\nRome is winning.", File.read(expected_path)
  end

  class StubLlmClient
    attr_reader :received

    def initialize(content:, input_tokens: nil, output_tokens: nil, cost_usd: nil)
      @response = AnalyzeGame::LlmResponse.new(
        content: content, input_tokens: input_tokens, output_tokens: output_tokens, cost_usd: cost_usd
      )
    end

    def call(model:, system_prompt:, input:)
      @received = { model: model, system_prompt: system_prompt, input: input }
      @response
    end
  end
end
