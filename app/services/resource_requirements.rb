require "yaml"

# Which UNIT_* needs which RESOURCE_*, and which RESOURCE_* is strategic
# rather than a luxury or a bonus. Both come from `unit_resource_requirements.yml`
# and `resource_usages.yml` (see db/lekmod/README.md and LekmodIdsExtractor),
# extracted from the mod's own XML source the same way buildings.yml is.
class ResourceRequirements
  REQUIREMENTS_FILENAME = "unit_resource_requirements.yml".freeze
  USAGES_FILENAME = "resource_usages.yml".freeze

  def self.for(version, root: Rails.root.join("db/lekmod"))
    new(version, root: root)
  end

  def initialize(version, root:)
    @version = version
    @root = root
  end

  def requires?(unit, resource) = requirements.fetch(unit, []).any? { |req| req["resource"] == resource }

  def strategic?(resource) = usages[resource] == "strategic"

  private

  def requirements = @requirements ||= read(@version, REQUIREMENTS_FILENAME) ||
                                        read(newest(REQUIREMENTS_FILENAME), REQUIREMENTS_FILENAME) || {}

  def usages = @usages ||= read(@version, USAGES_FILENAME) || read(newest(USAGES_FILENAME), USAGES_FILENAME) || {}

  def read(version, filename)
    path = File.join(@root, version.to_s, filename)
    YAML.safe_load_file(path) if version && File.exist?(path)
  end

  def newest(filename)
    Dir.children(@root)
       .select { |entry| entry.match?(LekmodReference::VERSION_DIR_PATTERN) && File.exist?(File.join(@root, entry, filename)) }
       .max_by { |version| Gem::Version.new(version) }
  end
end
