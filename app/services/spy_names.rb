require "yaml"

# The log names a spy by its text key, not by the name LEKMOD gave it:
# TXT_KEY_SPY_NAME_INDIA_7 is Mukta. The names come from the mod's own XML
# (see db/lekmod/README.md).
class SpyNames
  FILENAME = "spy_names.yml".freeze
  PREFIX = "TXT_KEY_SPY_NAME_".freeze

  def self.for(version, root: Rails.root.join("db/lekmod"))
    new(version, root: root)
  end

  def initialize(version, root:)
    @version = version
    @root = root
  end

  def call(spy) = names[spy] || plain(spy)

  def glossary(spies) = spies.uniq.sort.index_with { |spy| call(spy) }

  private

  # A flavour name keeps naming a spy far longer than a policy keeps its
  # effect, so a snapshot taken before names were extracted is better served
  # by another snapshot's names than by none.
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

  # A spy's flavour name is never guessable from its id the way a unit's
  # usually is - the id is a civ code and an ordinal, not English with the
  # odd rename - so this only makes the id legible, never invents a name.
  def plain(spy) = spy.delete_prefix(PREFIX).tr("_", " ").downcase.titleize
end
