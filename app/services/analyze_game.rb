class AnalyzeGame
  PROMPT_PATH = Rails.root.join("app/prompts/analyze_game.md")

  attr_reader :lekmod_version

  def initialize(game, winner_civ: nil, victory_type: nil, model: nil, lekmod_version: nil,
                 llm_client: LlmClient.new, reports_dir: Rails.root.join("reports"),
                 lekmod_root: Rails.root.join("db/lekmod"))
    @game = game
    @winner_civ = winner_civ
    @victory_type = victory_type
    @model = model || RubyLLM.config.default_model
    @lekmod_version = lekmod_version || game.lekmod_version
    @llm_client = llm_client
    @reports_dir = reports_dir
    @lekmod_root = lekmod_root
  end

  def call
    digest = DigestBuilder.new(
      @game, winner_civ: @winner_civ, victory_type: @victory_type,
      lekmod_version: @lekmod_version, lekmod_root: @lekmod_root
    ).call

    response = @llm_client.call(model: @model, system_prompt: prompt, input: digest.to_json)

    analysis = @game.analyses.create!(
      model: @model, report: response.content, digest: digest, prompt: prompt,
      lekmod_version: @lekmod_version,
      input_tokens: response.input_tokens, output_tokens: response.output_tokens, cost_usd: response.cost_usd
    )
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
end
