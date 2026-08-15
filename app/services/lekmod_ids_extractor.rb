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

  def call
    keys_by_type = type_to_txt_key
    texts = txt_key_to_text

    keys_by_type.each_with_object({}) do |(type, txt_key), result|
      text = texts[txt_key]
      result[type] = text if text
    end
  end

  private

  def documents
    @documents ||= Dir.glob(File.join(@source_dir, "**", "*.{xml,XML}")).map do |path|
      Nokogiri::XML(File.read(path))
    end
  end

  def type_to_txt_key
    documents.each_with_object({}) do |doc, result|
      extract_type_mapping(doc, "Beliefs", "ShortDescription", result)
      extract_type_mapping(doc, "Policies", "Description", result)
    end
  end

  def extract_type_mapping(doc, table, name_field, result)
    doc.css("#{table} Row").each do |row|
      type = row.at_css("Type")&.text
      txt_key = row.at_css(name_field)&.text
      result[type] = txt_key if type && txt_key
    end
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
