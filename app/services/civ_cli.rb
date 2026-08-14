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
    when "list" then list(rest)
    else
      @err.puts "Unknown command: #{command.inspect}. Usage: civ import|analyze|list"
      1
    end
  end

  private

  def import(args)
    options = {}
    parser = OptionParser.new do |o|
      o.banner = "Usage: civ import PATH [--name NAME]"
      o.on("--name NAME", "Game name (default: file basename)") { |v| options[:name] = v }
    end

    path = parser.parse!(args).first
    return usage_error(parser) if path.nil?

    result = ImportGame.call(path, name: options[:name])
    @out.puts "Imported game ##{result.game.id} \"#{result.game.name}\": " \
              "#{result.imported_count} events (#{result.skipped_count} deduped)"
    @out.puts "Roster: #{result.game.players.pluck(:civ).join(", ")}"
    0
  end

  def analyze(args)
    options = {}
    parser = OptionParser.new do |o|
      o.banner = "Usage: civ analyze GAME_ID [--winner CIV] [--victory-type TYPE] [--model MODEL] [--reports-dir DIR]"
      o.on("--winner CIV") { |v| options[:winner_civ] = v }
      o.on("--victory-type TYPE") { |v| options[:victory_type] = v }
      o.on("--model MODEL") { |v| options[:model] = v }
      o.on("--reports-dir DIR") { |v| options[:reports_dir] = v }
    end

    game_id = parser.parse!(args).first
    return usage_error(parser) if game_id.nil?

    game = Game.find_by(id: game_id)
    if game.nil?
      @err.puts "Game ##{game_id} not found."
      return 1
    end

    options[:llm_client] = @llm_client if @llm_client
    analysis = AnalyzeGame.new(game, **options).call
    @out.puts "Analysis ##{analysis.id} saved for game ##{game.id} (model: #{analysis.model})"
    0
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
