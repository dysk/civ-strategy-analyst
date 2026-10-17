require "test_helper"
require "tmpdir"

class ChronicleGameTest < ActiveSupport::TestCase
  setup do
    @game = Game.create!(name: "Chronicle Test Game", game_speed: "GAMESPEED_QUICK")
    @game.game_events.create!(
      seq: 1, session_index: 0, turn: 10, event_type: "snapshot", civ: "Rome",
      payload: { "event" => "snapshot", "turn" => 10, "civ" => "Rome", "score" => 100 }
    )
    @reports_dir = Dir.mktmpdir
  end

  teardown { FileUtils.remove_entry(@reports_dir) }

  test "sends the chronicle prompt and the dated digest to the llm client" do
    stub = StubLlmClient.new(content: "In the first years of the world...")

    ChronicleGame.new(@game, model: "test-model", llm_client: stub, reports_dir: @reports_dir).call

    assert_equal "test-model", stub.received[:model]
    assert_includes stub.received[:system_prompt], File.read(Rails.root.join("app/prompts/chronicle_game.md"))
    assert JSON.parse(stub.received[:input]).key?("calendar")
  end

  test "writes the chronicle to a file and returns where it landed" do
    stub = StubLlmClient.new(content: "In the first years of the world...")

    result = ChronicleGame.new(@game, llm_client: stub, reports_dir: @reports_dir).call

    assert_equal "In the first years of the world...", File.read(result.path)
    assert_match(/chronicle-chronicle-test-game-\d{14}\.md\z/, result.path)
  end

  test "reports which model wrote the chronicle and what it cost" do
    stub = StubLlmClient.new(content: "chronicle", input_tokens: 900, output_tokens: 300, cost_usd: 0.0421)

    result = ChronicleGame.new(@game, model: "test-model", llm_client: stub, reports_dir: @reports_dir).call

    assert_equal "test-model", result.model
    assert_equal 900, result.input_tokens
    assert_equal 300, result.output_tokens
    assert_equal 0.0421, result.cost_usd
  end

  test "leaves no record of the chronicle in the database" do
    stub = StubLlmClient.new(content: "chronicle")

    assert_no_difference -> { Analysis.count } do
      ChronicleGame.new(@game, llm_client: stub, reports_dir: @reports_dir).call
    end
  end

  test "asks for the chronicle in the chosen language" do
    stub = StubLlmClient.new(content: "chronicle")

    ChronicleGame.new(@game, lang: "pl", llm_client: stub, reports_dir: @reports_dir).call

    assert_includes stub.received[:system_prompt], "Polish"
  end

  test "writes in English unless another language is chosen" do
    stub = StubLlmClient.new(content: "chronicle")

    ChronicleGame.new(@game, llm_client: stub, reports_dir: @reports_dir).call

    assert_includes stub.received[:system_prompt], "English"
  end

  test "refuses a language it has no chronicle voice for" do
    stub = StubLlmClient.new(content: "chronicle")

    assert_raises(ArgumentError) do
      ChronicleGame.new(@game, lang: "kl", llm_client: stub, reports_dir: @reports_dir).call
    end
  end

  class StubLlmClient
    attr_reader :received

    def initialize(content:, input_tokens: nil, output_tokens: nil, cost_usd: nil)
      @response = LlmClient::Response.new(
        content: content, input_tokens: input_tokens, output_tokens: output_tokens, cost_usd: cost_usd
      )
    end

    def call(model:, system_prompt:, input:)
      @received = { model: model, system_prompt: system_prompt, input: input }
      @response
    end
  end
end
