module AnalysesHelper
  # Projections that already have a dedicated, richer page elsewhere in the
  # app. The digest snapshot still shows the raw section - it's the exact
  # payload the prompt received, which the dedicated page doesn't
  # necessarily match turn-for-turn - but links across so the two can be
  # cross-checked.
  DEDICATED_PAGES = {
    "espionage" => :game_espionage_path,
    "cultural" => :game_cultural_path,
    "congress" => :game_congress_path,
    "victory_progress" => :game_victory_progress_path
  }.freeze

  def digest_section_empty?(value)
    value.blank? || (value.is_a?(Hash) && value["applicable"] == false)
  end

  def digest_dedicated_page_path(key, game)
    path_helper = DEDICATED_PAGES[key]
    public_send(path_helper, game) if path_helper
  end
end
