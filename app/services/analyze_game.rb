class AnalyzeGame
  PROMPT_PATH = Rails.root.join("app/prompts/analyze_game_v1.md")

  def initialize(game, winner_civ: nil, victory_type: nil, model: nil,
                 llm_client: RubyLlmClient.new, reports_dir: Rails.root.join("reports"))
    @game = game
    @winner_civ = winner_civ
    @victory_type = victory_type
    @model = model || RubyLLM.config.default_model
    @llm_client = llm_client
    @reports_dir = reports_dir
  end

  def call
    digest = DigestBuilder.new(@game, winner_civ: @winner_civ, victory_type: @victory_type).call

    report = @llm_client.call(model: @model, system_prompt: prompt, input: digest.to_json)

    analysis = @game.analyses.create!(model: @model, report: report, digest: digest)
    write_report_file(analysis)
    analysis
  end

  private

  def prompt
    @prompt ||= File.read(PROMPT_PATH)
  end

  def write_report_file(analysis)
    FileUtils.mkdir_p(@reports_dir)
    timestamp = Time.current.strftime("%Y%m%d%H%M%S")
    path = File.join(@reports_dir, "#{@game.name.parameterize}-#{timestamp}.md")
    File.write(path, analysis.report)
  end

  # Thin adapter over RubyLLM so AnalyzeGame depends on a small, injectable
  # interface instead of RubyLLM::Chat's full API.
  class RubyLlmClient
    def call(model:, system_prompt:, input:)
      RubyLLM.chat(model: model).with_instructions(system_prompt).ask(input).content
    end
  end
end
