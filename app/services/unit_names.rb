require "yaml"

# The log names a unit by its id, and the id is not what the thing is
# called: UNIT_WWI_TANK is a Landship in the rules and in every reader's
# head. The names come from the mod's own XML (see db/lekmod/README.md).
# An id no snapshot names reads well enough as plain English, which is
# what most of them are.
class UnitNames
  FILENAME = "units.yml".freeze

  def self.for(version, root: Rails.root.join("db/lekmod"))
    new(version, root: root)
  end

  def initialize(version, root:)
    @version = version
    @root = root
  end

  def call(unit) = names[unit] || plain(unit)

  def glossary(units) = units.uniq.sort.index_with { |unit| call(unit) }

  private

  # A unit keeps its name across versions far longer than a policy keeps
  # its effect, so a snapshot taken before names were extracted is better
  # served by another snapshot's names than by none.
  def names = @names ||= read(@version) || read(newest_named) || {}

  def read(version)
    path = File.join(@root, version.to_s, FILENAME)
    YAML.safe_load_file(path) if version && File.exist?(path)
  end

  def newest_named
    Dir.children(@root)
       .select { |entry| entry.match?(LekmodReference::VERSION_DIR_PATTERN) && named?(entry) }
       .max_by { |version| Gem::Version.new(version) }
  end

  def named?(version) = File.exist?(File.join(@root, version, FILENAME))

  def plain(unit) = unit.delete_prefix("UNIT_").downcase.titleize
end
