# Writes the history of a game as a chronicle, saved both to a file and as
# the newest Chronicle row for the game.
class ChronicleGame
  Result = Struct.new(:chronicle, :path, :model, :input_tokens, :output_tokens, :cost_usd, keyword_init: true)

  PROMPT_PATH = Rails.root.join("app/prompts/chronicle_game.md")
  LANGUAGES = { "en" => "English", "pl" => "Polish" }.freeze

  def initialize(game, lang: "en", model: nil, lekmod_version: nil, llm_client: LlmClient.new,
                 reports_dir: Rails.root.join("reports"), lekmod_root: Rails.root.join("db/lekmod"))
    @game = game
    @language = language_for(lang)
    @model = model || RubyLLM.config.default_model
    @lekmod_version = lekmod_version
    @llm_client = llm_client
    @reports_dir = reports_dir
    @lekmod_root = lekmod_root
  end

  def call
    response = @llm_client.call(model: @model, system_prompt: prompt, input: digest.to_json)
    Result.new(
      chronicle: persist(response), path: write(response.content), model: @model,
      input_tokens: response.input_tokens, output_tokens: response.output_tokens, cost_usd: response.cost_usd
    )
  end

  private

  def language_for(lang)
    LANGUAGES.fetch(lang.to_s) do
      raise ArgumentError, "No chronicle voice for language #{lang.inspect}; try #{LANGUAGES.keys.join(", ")}"
    end
  end

  def persist(response)
    @game.chronicles.create!(
      model: @model, content: response.content, digest: digest, prompt: prompt,
      lekmod_version: @lekmod_version,
      input_tokens: response.input_tokens, output_tokens: response.output_tokens, cost_usd: response.cost_usd
    )
  end

  def digest
    @digest ||= ChronicleDigest.new(@game, lekmod_version: @lekmod_version, lekmod_root: @lekmod_root).call
  end

  def prompt
    @prompt ||= "#{File.read(PROMPT_PATH)}\n\nWrite the chronicle in #{@language}.\n"
  end

  def write(chronicle)
    FileUtils.mkdir_p(@reports_dir)
    timestamp = Time.current.strftime("%Y%m%d%H%M%S")
    path = File.join(@reports_dir, "chronicle-#{@game.name.parameterize}-#{timestamp}.md")
    File.write(path, chronicle)
    path
  end
end
