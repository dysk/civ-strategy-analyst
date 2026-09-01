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

  test "writes the chronicle to a file and returns its path" do
    stub = StubLlmClient.new(content: "In the first years of the world...")

    path = ChronicleGame.new(@game, llm_client: stub, reports_dir: @reports_dir).call

    assert_equal "In the first years of the world...", File.read(path)
    assert_match(/chronicle-chronicle-test-game-\d{14}\.md\z/, path)
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

    def initialize(content:)
      @response = LlmClient::Response.new(content: content)
    end

    def call(model:, system_prompt:, input:)
      @received = { model: model, system_prompt: system_prompt, input: input }
      @response
    end
  end
end
