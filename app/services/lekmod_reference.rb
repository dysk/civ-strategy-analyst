require "yaml"

class LekmodReference
  VERSION_DIR_PATTERN = /\A\d+(\.\d+)*\z/
  NAMED_ID_BULLET = /^- \*\*(?<name>[^*]+?)\*\*\s*\(`(?<id>[A-Z_]+)`\):/
  BOLD_NAME_BULLET = /^- \*\*(?<name>[^*]+?):\*\*/
  NAME_QUALIFIER = /\s*\([^)]*\)\s*\z/

  def initialize(version, civs: [], policy_ids: [], belief_ids: [], resolution_ids: [],
                 root: Rails.root.join("db/lekmod"))
    @requested_version = version
    @civs = civs
    @policy_ids = policy_ids
    @belief_ids = belief_ids
    @resolution_ids = resolution_ids
    @root = root
  end

  def call
    version, note = resolve_version
    @unmatched_ids = []

    {
      version: version,
      resolution_note: note,
      civilizations: version ? extract_civilizations(version) : {},
      policies: version ? extract_ids(version, %w[policies.md ideologies.md], @policy_ids) : {},
      beliefs: version ? extract_ids(version, %w[religion.md], @belief_ids) : {},
      resolutions: version ? extract_resolution_names(version, @resolution_ids) : {},
      general_rules: version ? read_file(version, "general.md") : nil,
      unmatched_ids: @unmatched_ids
    }
  end

  private

  def resolve_version
    return [ nil, "No LEKMOD version specified for this game; ruleset details omitted." ] if @requested_version.nil?
    return [ @requested_version, nil ] if available_versions.include?(@requested_version)

    if (sibling = nearest_in_line)
      [ sibling, "Requested LEKMOD #{@requested_version}; no exact snapshot available, using #{sibling} " \
                 "from the same #{major(@requested_version)}.x line instead. Minor versions carry hotfixes " \
                 "and small tweaks, not new civilizations or mechanics." ]
    elsif (older = nearest_older)
      [ older, "Requested LEKMOD #{@requested_version}; no snapshot from the #{major(@requested_version)}.x " \
               "line available, using older version #{older} instead. Civilizations and mechanics added " \
               "since then are missing from the ruleset below." ]
    else
      [ nil, "No LEKMOD reference data available for version #{@requested_version} or earlier; " \
             "ruleset details omitted." ]
    end
  end

  # Within a major line the snapshots differ only by hotfixes, so the
  # closest one wins whichever side of the game it falls on; only a tie
  # goes to the older, which at least cannot describe what did not exist yet.
  def nearest_in_line
    available_versions
      .select { |v| major(v) == major(@requested_version) }
      .min_by { |v| [ distance_from_requested(v), newer_than_requested?(v) ? 1 : 0 ] }
  end

  def nearest_older
    available_versions
      .select { |v| Gem::Version.new(v) < Gem::Version.new(@requested_version) }
      .max_by { |v| Gem::Version.new(v) }
  end

  def distance_from_requested(version)
    width = [ segments(version).size, segments(@requested_version).size ].max

    padded(version, width).zip(padded(@requested_version, width)).map { |a, b| (a - b).abs }
  end

  def newer_than_requested?(version)
    Gem::Version.new(version) > Gem::Version.new(@requested_version)
  end

  def major(version)
    segments(version).first
  end

  def segments(version)
    Gem::Version.new(version).segments
  end

  def padded(version, width)
    parts = segments(version)
    parts + [ 0 ] * (width - parts.size)
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
    ids_yml = load_ids_yml(version)

    ids.each_with_object({}) do |id, result|
      entry = id_index[id] || ids_yml_match(name_index, ids_yml, id) || name_index[derived_name(id)]

      if entry
        result[id] = entry
      else
        @unmatched_ids << id
      end
    end
  end

  # World Congress resolutions have no markdown entry to extract - LEKMOD
  # leaves the base game's resolutions untouched (see general.md's World
  # Congress section for the handful of exceptions), so ids.yml's display
  # name is all there is to offer, not a description of the effect.
  def extract_resolution_names(version, ids)
    return {} if ids.empty?

    ids_yml = load_ids_yml(version)

    ids.each_with_object({}) do |id, result|
      name = ids_yml[id]

      if name
        result[id] = name
      else
        @unmatched_ids << id
      end
    end
  end

  def ids_yml_match(name_index, ids_yml, id)
    name = ids_yml[id]
    name_index[normalize(name)] if name
  end

  def load_ids_yml(version)
    @ids_yml_cache ||= {}
    @ids_yml_cache[version] ||= begin
      path = File.join(@root, version, "ids.yml")
      File.exist?(path) ? YAML.safe_load_file(path) : {}
    end
  end

  def index_bullets(version, filenames)
    id_index = {}
    name_index = {}

    lines(version, filenames).each do |line|
      if (m = line.match(NAMED_ID_BULLET))
        id_index[m[:id]] = line.strip
        index_name(name_index, m[:name], line.strip)
      elsif (m = line.match(BOLD_NAME_BULLET))
        index_name(name_index, m[:name], line.strip)
      end
    end

    [ id_index, name_index ]
  end

  # A bullet named "Synagogues (Building)" is also reachable as
  # "Synagogues", the display name ids.yml knows it by - but the bare
  # form never displaces a bullet that carries that name exactly.
  def index_name(name_index, name, entry)
    name_index[normalize(name)] = entry
    bare_name = name.sub(NAME_QUALIFIER, "")
    name_index[normalize(bare_name)] ||= entry unless bare_name == name
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
