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

  private

  WONDER_SCOPE_FIELDS = { "MaxGlobalInstances" => "world", "MaxTeamInstances" => "team",
                          "MaxPlayerInstances" => "national" }.freeze

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
