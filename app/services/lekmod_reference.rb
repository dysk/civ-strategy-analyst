class LekmodReference
  VERSION_DIR_PATTERN = /\A\d+(\.\d+)*\z/
  NAMED_ID_BULLET = /^- \*\*(?<name>[^*]+?)\*\*\s*\(`(?<id>[A-Z_]+)`\):/
  BOLD_NAME_BULLET = /^- \*\*(?<name>[^*]+?):\*\*/

  def initialize(version, civs: [], policy_ids: [], belief_ids: [], root: Rails.root.join("db/lekmod"))
    @requested_version = version
    @civs = civs
    @policy_ids = policy_ids
    @belief_ids = belief_ids
    @root = root
  end

  def call
    version, note = resolve_version

    {
      version: version,
      resolution_note: note,
      civilizations: version ? extract_civilizations(version) : {},
      policies: version ? extract_ids(version, %w[policies.md ideologies.md], @policy_ids) : {},
      beliefs: version ? extract_ids(version, %w[religion.md], @belief_ids) : {},
      general_rules: version ? read_file(version, "general.md") : nil
    }
  end

  private

  def resolve_version
    return [ nil, "No LEKMOD version specified for this game; ruleset details omitted." ] if @requested_version.nil?
    return [ @requested_version, nil ] if available_versions.include?(@requested_version)

    older = available_versions
      .select { |v| Gem::Version.new(v) < Gem::Version.new(@requested_version) }
      .max_by { |v| Gem::Version.new(v) }

    if older
      [ older, "Requested LEKMOD #{@requested_version}; no exact snapshot available, using nearest " \
               "older version #{older} instead. Ruleset details may have drifted since." ]
    else
      [ nil, "No LEKMOD reference data available for version #{@requested_version} or earlier; " \
             "ruleset details omitted." ]
    end
  end

  def available_versions
    @available_versions ||= Dir.children(@root).select do |entry|
      File.directory?(File.join(@root, entry)) && entry.match?(VERSION_DIR_PATTERN)
    end
  end

  def extract_civilizations(version)
    text = read_file(version, "civilizations.md")
    return {} unless text

    @civs.each_with_object({}) do |civ, result|
      section = text.split(/(?=^## )/).find { |s| s.start_with?("## #{civ} (") }
      result[civ] = section.strip if section
    end
  end

  def extract_ids(version, filenames, ids)
    return {} if ids.empty?

    id_index, name_index = index_bullets(version, filenames)

    ids.each_with_object({}) do |id, result|
      entry = id_index[id] || name_index[derived_name(id)]
      result[id] = entry if entry
    end
  end

  def index_bullets(version, filenames)
    id_index = {}
    name_index = {}

    lines(version, filenames).each do |line|
      if (m = line.match(NAMED_ID_BULLET))
        id_index[m[:id]] = line.strip
        name_index[normalize(m[:name])] = line.strip
      elsif (m = line.match(BOLD_NAME_BULLET))
        name_index[normalize(m[:name])] = line.strip
      end
    end

    [ id_index, name_index ]
  end

  def lines(version, filenames)
    filenames.flat_map { |filename| (read_file(version, filename) || "").each_line(chomp: true).to_a }
  end

  def derived_name(id)
    id.sub(/\A(POLICY|BELIEF)_/, "")
  end

  def normalize(name)
    name.upcase.gsub(/[^A-Z0-9]+/, "_").gsub(/\A_+|_+\z/, "")
  end

  def read_file(version, filename)
    path = File.join(@root, version, filename)
    File.exist?(path) ? File.read(path) : nil
  end
end
