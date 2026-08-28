require "optparse"

class CivCli
  def initialize(out: $stdout, err: $stderr, llm_client: nil)
    @out = out
    @err = err
    @llm_client = llm_client
  end

  def run(argv)
    command, *rest = argv

    case command
    when "import" then import(rest)
    when "analyze" then analyze(rest)
    when "chronicle" then chronicle(rest)
    when "list" then list(rest)
    else
      @err.puts "Unknown command: #{command.inspect}. Usage: civ import|analyze|chronicle|list"
      1
    end
  end

  private

  def import(args)
    options = {}
    parser = OptionParser.new do |o|
      o.banner = "Usage: civ import PATH [--name NAME] [--lekmod-version VERSION]"
      o.on("--name NAME", "Game name (default: file basename)") { |v| options[:name] = v }
      o.on("--lekmod-version VERSION", "LEKMOD version this game was played on") { |v| options[:lekmod_version] = v }
    end

    path = parser.parse!(args).first
    return usage_error(parser) if path.nil?

    result = ImportGame.call(path, name: options[:name], lekmod_version: options[:lekmod_version])
    @out.puts "Imported game ##{result.game.id} \"#{result.game.name}\": " \
              "#{result.imported_count} events (#{result.skipped_count} deduped)"
    @out.puts "Roster: #{result.game.players.pluck(:civ).join(", ")}"
    report_logger_errors(result.logger_error_count)
    0
  end

  # The logger records its own failures; an import that swallowed some
  # should say so, because the game log is then missing events.
  def report_logger_errors(count)
    return if count.zero?

    @out.puts "#{count} logger error#{"s" if count != 1} in the log, not imported"
  end

  def analyze(args)
    options = {}
    parser = OptionParser.new do |o|
      o.banner = "Usage: civ analyze GAME_ID [--winner CIV] [--victory-type TYPE] [--model MODEL] " \
                 "[--lekmod-version VERSION] [--reports-dir DIR]"
      o.on("--winner CIV") { |v| options[:winner_civ] = v }
      o.on("--victory-type TYPE") { |v| options[:victory_type] = v }
      o.on("--model MODEL") { |v| options[:model] = v }
      o.on("--lekmod-version VERSION", "Override the game's stored LEKMOD version") { |v| options[:lekmod_version] = v }
      o.on("--reports-dir DIR") { |v| options[:reports_dir] = v }
    end

    game = find_game(parser, args) or return 1

    options[:llm_client] = @llm_client if @llm_client
    analysis = AnalyzeGame.new(game, **options).call
    @out.puts "Analysis ##{analysis.id} saved for game ##{game.id} (model: #{analysis.model})#{usage_summary(analysis)}"
    0
  end

  def chronicle(args)
    options = {}
    parser = OptionParser.new do |o|
      o.banner = "Usage: civ chronicle GAME_ID [--lang #{ChronicleGame::LANGUAGES.keys.join("|")}] " \
                 "[--model MODEL] [--lekmod-version VERSION] [--reports-dir DIR]"
      o.on("--lang LANG", "Language to write the chronicle in (default: en)") { |v| options[:lang] = v }
      o.on("--model MODEL") { |v| options[:model] = v }
      o.on("--lekmod-version VERSION", "Override the game's stored LEKMOD version") { |v| options[:lekmod_version] = v }
      o.on("--reports-dir DIR") { |v| options[:reports_dir] = v }
    end

    game = find_game(parser, args) or return 1

    options[:llm_client] = @llm_client if @llm_client
    @out.puts "Chronicle saved to #{ChronicleGame.new(game, **options).call}"
    0
  end

  # Both reporting commands take a game id and fail the same two ways.
  def find_game(parser, args)
    game_id = parser.parse!(args).first
    return usage_error(parser) && nil if game_id.nil?

    game = Game.find_by(id: game_id)
    @err.puts "Game ##{game_id} not found." if game.nil?
    game
  end

  def usage_summary(analysis)
    return "" unless analysis.input_tokens && analysis.output_tokens

    summary = " — #{analysis.input_tokens} in + #{analysis.output_tokens} out tokens"
    summary += " (~$#{format("%.4f", analysis.cost_usd)})" if analysis.cost_usd
    summary
  end

  def list(_args)
    games = Game.order(:id).all
    if games.empty?
      @out.puts "No games imported yet."
      return 0
    end

    games.each do |game|
      status = game.analyses.exists? ? "analyzed" : "not analyzed"
      status += ", completed" if game.completed?
      @out.puts "##{game.id}  #{game.name}  (#{status})"
    end
    0
  end

  def usage_error(parser)
    @err.puts parser.to_s
    1
  end
end
