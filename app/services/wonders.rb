require "yaml"

# Whether a BUILDING_* id is a world wonder, and what to call it.
#
# The log names a wonder by a bare building id, and only ever for wonders
# somebody finished - a race for one that nobody completed leaves no
# `building_constructed` record to read the id off. `buildings.yml` carries
# the ruleset's cap for every building (see db/lekmod/README.md and
# LekmodIdsExtractor), so an unfinished race is still recognisable. When no
# snapshot carries that file, the wonders this game was seen to complete are
# all that can be known, and those come in as `observed`.
class Wonders
  FILENAME = "buildings.yml".freeze

  def self.for(version, observed: [], root: Rails.root.join("db/lekmod"))
    new(version, observed: observed, root: root)
  end

  def initialize(version, observed:, root:)
    @version = version
    @observed = observed.to_set
    @root = root
  end

  def name(building) = catalogue.dig(building, "name") || plain(building)

  def world?(building)
    return catalogue.dig(building, "wonder") == "world" if catalogue.any?

    @observed.include?(building)
  end

  private

  # A building keeps its name and its cap across versions far longer than a
  # policy keeps its effect, so a snapshot predating the catalogue is better
  # served by a later snapshot's than by none.
  def catalogue = @catalogue ||= read(@version) || read(newest_catalogued) || {}

  def read(version)
    path = File.join(@root, version.to_s, FILENAME)
    YAML.safe_load_file(path) if version && File.exist?(path)
  end

  def newest_catalogued
    Dir.children(@root)
       .select { |entry| entry.match?(LekmodReference::VERSION_DIR_PATTERN) && catalogued?(entry) }
       .max_by { |version| Gem::Version.new(version) }
  end

  def catalogued?(version) = File.exist?(File.join(@root, version, FILENAME))

  def plain(building) = building.delete_prefix("BUILDING_").downcase.titleize
end
