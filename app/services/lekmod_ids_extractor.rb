require "nokogiri"

# Extracts an ID -> display name mapping from a checkout of the mod's XML
# source (scoped to LEKMOD/Override - see db/lekmod/README.md). Two-pass:
# first resolve each POLICY_*/BELIEF_* Type to its TXT_KEY in the Policies/
# Beliefs tables, then resolve that TXT_KEY to English text from the
# Language_en_US text tables. A <Replace Tag="..."> always wins over a
# <Row Tag="..."> for the same tag, regardless of which file defines it -
# that's the mod's own override mechanism, not just file processing order.
class LekmodIdsExtractor
  def initialize(source_dir)
    @source_dir = source_dir
  end

  def call = resolve(type_to_txt_key)

  def unit_names = resolve(unit_to_description)

  # A spy's id is already the Language_en_US text key - Civilization_SpyNames
  # in CIV5Units.xml only enumerates which keys exist per civilization, it
  # adds no Type indirection the way a policy or belief has - so no table
  # needs parsing here, only the prefix that marks a key as a spy's.
  def spy_names = texts.select { |tag, _| tag.start_with?(SPY_NAME_PREFIX) }

  # BUILDING_* -> { "name" => display name, "wonder" => scope } where scope
  # is "world" / "team" / "national" for a building whose class the ruleset
  # caps, and absent otherwise. The cap sits on the building's class, not
  # the building - the same three-scope rule the logger reads in adapter.lua.
  def buildings
    building_rows.each_with_object({}) do |(type, row), result|
      name = display_name(texts[row[:description]] || literal(row[:description]))
      next if name.blank?

      entry = { "name" => name }
      scope = class_scopes[row[:building_class]]
      entry["wonder"] = scope if scope
      result[type] = entry
    end
  end

  def technologies = resolve(tech_to_description)

  # RESOURCE_* -> "bonus" / "strategic" / "luxury", from the Resources
  # table's own ResourceUsage column. That column is an integer
  # (CIV5Units.xml:192705), not a string enum - RESOURCEUSAGE_BONUS,
  # _STRATEGIC and _LUXURY are 0, 1 and 2 in that order (CvEnums.h:1194).
  def resource_usages
    documents.each_with_object({}) do |doc, result|
      doc.css("Resources Row").each do |row|
        type = row.at_css("Type")&.text
        usage = row.at_css("ResourceUsage")&.text
        result[type] = RESOURCE_USAGES[usage.to_i] if type && usage
      end
    end
  end

  # UNIT_* -> every resource it needs and how much, from
  # Unit_ResourceQuantityRequirements (UnitType, ResourceType, Cost) - one
  # row per (unit, resource) pair, so a unit needing two resources at once
  # appears twice.
  def unit_resource_requirements
    requirement_rows.group_by { |row| row[:unit] }
      .transform_values { |rows| rows.map { |row| { "resource" => row[:resource], "cost" => row[:cost] } } }
  end

  private

  WONDER_SCOPE_FIELDS = { "MaxGlobalInstances" => "world", "MaxTeamInstances" => "team",
                          "MaxPlayerInstances" => "national" }.freeze

  RESOURCE_USAGES = %w[bonus strategic luxury].freeze

  SPY_NAME_PREFIX = "TXT_KEY_SPY_NAME_".freeze

  # The name text of a national wonder carries the game's [COLOR_...] markup
  # around a trailing "*" that marks it as one; strip both back to the name.
  def display_name(text)
    return unless text

    text.gsub(/\[[^\]]*\]/, "").sub(/\s*\*\s*\z/, "").squish
  end

  def building_rows
    documents.each_with_object({}) do |doc, result|
      doc.css("Buildings Row").each do |row|
        type = row.at_css("Type")&.text
        next unless type

        result[type] = { building_class: row.at_css("BuildingClass")&.text,
                         description: row.at_css("Description")&.text }
      end
    end
  end

  # First cap that is set wins, and the fields are checked widest scope
  # first: Oxford University is one per team, not one per world.
  def class_scopes
    documents.each_with_object({}) do |doc, result|
      doc.css("BuildingClasses Row").each do |row|
        type = row.at_css("Type")&.text
        next unless type

        result[type] = WONDER_SCOPE_FIELDS.filter_map do |field, scope|
          scope if row.at_css(field)&.text.to_i.positive?
        end.first
      end
    end
  end

  def requirement_rows
    documents.flat_map { |doc| doc.css("Unit_ResourceQuantityRequirements Row") }.filter_map do |row|
      unit = row.at_css("UnitType")&.text
      resource = row.at_css("ResourceType")&.text
      next unless unit && resource

      { unit: unit, resource: resource, cost: row.at_css("Cost")&.text.to_i }
    end
  end

  def resolve(descriptions)
    descriptions.each_with_object({}) do |(type, description), result|
      name = texts[description] || literal(description)
      result[type] = name if name
    end
  end

  # LEKMOD's own units skip the text tables and write their English name
  # straight into Description, where a vanilla unit carries a TXT_KEY.
  def literal(description)
    description unless description.start_with?("TXT_KEY")
  end

  def documents
    @documents ||= Dir.glob(File.join(@source_dir, "**", "*.{xml,XML}")).map do |path|
      Nokogiri::XML(File.read(path))
    end
  end

  def type_to_txt_key
    documents.each_with_object({}) do |doc, result|
      extract_type_mapping(doc, "Beliefs", "ShortDescription", result)
      extract_type_mapping(doc, "Policies", "Description", result)
      extract_type_mapping(doc, "Resolutions", "Description", result)
    end
  end

  def extract_type_mapping(doc, table, name_field, result)
    doc.css("#{table} Row").each do |row|
      type = row.at_css("Type")&.text
      txt_key = row.at_css(name_field)&.text
      result[type] = txt_key if type && txt_key
    end
  end

  def texts = @texts ||= txt_key_to_text

  def unit_to_description
    documents.each_with_object({}) { |doc, result| extract_type_mapping(doc, "Units", "Description", result) }
  end

  def tech_to_description
    documents.each_with_object({}) { |doc, result| extract_type_mapping(doc, "Technologies", "Description", result) }
  end

  def txt_key_to_text
    row_texts = {}
    replace_texts = {}

    documents.each do |doc|
      extract_text_mapping(doc, "Row", row_texts)
      extract_text_mapping(doc, "Replace", replace_texts)
    end

    row_texts.merge(replace_texts)
  end

  def extract_text_mapping(doc, element, result)
    doc.css("Language_en_US #{element}[Tag]").each do |node|
      tag = node["Tag"]
      text = node.at_css("Text")&.text&.strip
      result[tag] = text if tag && text.present?
    end
  end
end
