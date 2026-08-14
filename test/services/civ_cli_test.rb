require "test_helper"
require "stringio"

class CivCliTest < ActiveSupport::TestCase
  SAMPLE_PATH = Rails.root.join("test/fixtures/files/sample_game.jsonl")

  setup do
    @out = StringIO.new
    @err = StringIO.new
  end

  test "import creates a game and prints a summary" do
    status = cli.run([ "import", SAMPLE_PATH.to_s, "--name", "CLI Test Game" ])

    assert_equal 0, status
    game = Game.find_by(name: "CLI Test Game")
    assert game.present?
    assert_match(/Imported game ##{game.id} "CLI Test Game": 5 events \(0 deduped\)/, @out.string)
    assert_match(/Rome, Greece/, @out.string)
  end

  test "import without a path prints usage to stderr and fails" do
    status = cli.run([ "import" ])

    assert_equal 1, status
    assert_match(/Usage: civ import/, @err.string)
  end

  test "analyze runs AnalyzeGame with the given options and prints where it saved" do
    game = Game.create!(name: "Analyze CLI Game")
    game.game_events.create!(
      seq: 1, session_index: 0, turn: 1, event_type: "snapshot", civ: "Rome",
      payload: { "event" => "snapshot", "turn" => 1, "civ" => "Rome", "score" => 10 }
    )
    stub = StubLlmClient.new("## Final Standings\n\nRome wins.")

    Dir.mktmpdir do |reports_dir|
      status = cli(llm_client: stub).run(
        [ "analyze", game.id.to_s, "--winner", "Rome", "--victory-type", "domination", "--reports-dir", reports_dir ]
      )

      assert_equal 0, status
    end

    assert_equal "Rome", stub.received[:model_input_winner]
    analysis = game.analyses.last
    assert_equal "Rome", analysis.digest["outcome"]["winner_civ"]
    assert_match(/Analysis ##{analysis.id} saved for game ##{game.id}/, @out.string)
  end

  test "analyze without a game id prints usage to stderr and fails" do
    status = cli.run([ "analyze" ])

    assert_equal 1, status
    assert_match(/Usage: civ analyze/, @err.string)
  end

  test "analyze with an unknown game id reports not found" do
    status = cli.run([ "analyze", "999999" ])

    assert_equal 1, status
    assert_match(/Game #999999 not found/, @err.string)
  end

  test "list prints a message when there are no games" do
    Game.destroy_all

    status = cli.run([ "list" ])

    assert_equal 0, status
    assert_match(/No games imported yet/, @out.string)
  end

  test "list prints each game with its analysis status" do
    analyzed = Game.create!(name: "Analyzed Game", completed: true)
    analyzed.analyses.create!(model: "m", report: "r", digest: {})
    not_analyzed = Game.create!(name: "Fresh Game")

    status = cli.run([ "list" ])

    assert_equal 0, status
    assert_match(/##{analyzed.id}\s+Analyzed Game\s+\(analyzed, completed\)/, @out.string)
    assert_match(/##{not_analyzed.id}\s+Fresh Game\s+\(not analyzed\)/, @out.string)
  end

  private

  def cli(llm_client: nil)
    CivCli.new(out: @out, err: @err, llm_client: llm_client)
  end

  class StubLlmClient
    attr_reader :received

    def initialize(report)
      @report = report
    end

    def call(model:, system_prompt:, input:)
      @received = { model_input_winner: JSON.parse(input)["outcome"]["winner_civ"] }
      @report
    end
  end
end
