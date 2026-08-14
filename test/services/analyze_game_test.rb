require "test_helper"
require "tmpdir"

class AnalyzeGameTest < ActiveSupport::TestCase
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

  test "sends the digest and versioned prompt to the injected llm client, and saves the report" do
    stub = StubLlmClient.new("## Final Standings\n\nRome is winning.")

    analysis = AnalyzeGame.new(
      @game, winner_civ: "Rome", victory_type: "domination",
      model: "test-model", llm_client: stub, reports_dir: @reports_dir
    ).call

    expected_digest = DigestBuilder.new(@game, winner_civ: "Rome", victory_type: "domination").call
    assert_equal "test-model", stub.received[:model]
    assert_equal File.read(Rails.root.join("app/prompts/analyze_game_v1.md")), stub.received[:system_prompt]
    assert_equal JSON.parse(expected_digest.to_json), JSON.parse(stub.received[:input])
  end

  test "persists the analysis with model, report and digest" do
    stub = StubLlmClient.new("## Final Standings\n\nRome is winning.")

    analysis = AnalyzeGame.new(
      @game, winner_civ: "Rome", model: "test-model", llm_client: stub, reports_dir: @reports_dir
    ).call

    assert analysis.persisted?
    assert_equal @game, analysis.game
    assert_equal "test-model", analysis.model
    assert_equal "## Final Standings\n\nRome is winning.", analysis.report
    assert_equal "Rome", analysis.digest["outcome"]["winner_civ"]
  end

  test "defaults the model to RubyLLM's configured default when none is given" do
    stub = StubLlmClient.new("report")

    analysis = AnalyzeGame.new(@game, llm_client: stub, reports_dir: @reports_dir).call

    assert_equal RubyLLM.config.default_model, analysis.model
    assert_equal RubyLLM.config.default_model, stub.received[:model]
  end

  test "writes the report to reports_dir as <game>-<timestamp>.md" do
    stub = StubLlmClient.new("## Final Standings\n\nRome is winning.")

    travel_to Time.utc(2026, 1, 2, 3, 4, 5) do
      AnalyzeGame.new(@game, model: "test-model", llm_client: stub, reports_dir: @reports_dir).call
    end

    expected_path = File.join(@reports_dir, "analyze-test-game-20260102030405.md")
    assert File.exist?(expected_path)
    assert_equal "## Final Standings\n\nRome is winning.", File.read(expected_path)
  end

  class StubLlmClient
    attr_reader :received

    def initialize(report)
      @report = report
    end

    def call(model:, system_prompt:, input:)
      @received = { model: model, system_prompt: system_prompt, input: input }
      @report
    end
  end
end
