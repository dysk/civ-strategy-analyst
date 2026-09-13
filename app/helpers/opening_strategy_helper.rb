# Formats OpeningStrategy's per-civ checklist (docs/ideal-opening.md) for
# the projections page. Each method reads the same row shape
# GameProjectionsController#opening_strategy_rows builds - a plain fact or
# "&mdash;" where the checklist item never applied, never a verdict.
module OpeningStrategyHelper
  SCOUT_LABELS = {
    opened_with_two_scouts: "2 scouts",
    two_scouts_interrupted: "2 scouts (interrupted)",
    one_scout: "1 scout",
    no_scouts: "no scouts"
  }.freeze

  def opening_strategy_branch(row)
    return "&mdash;".html_safe unless row[:branch]

    strip_prefix_and_titleize(row[:branch], "POLICY_BRANCH_")
  end

  def opening_strategy_closed(row)
    closed = row[:closed_opening]
    return "&mdash;".html_safe unless closed&.dig(:turns_to_close)

    "#{closed[:turns_to_close]} (t. #{closed[:finished_turn]})"
  end

  def opening_strategy_first_tech(row)
    tech = row[:first_tech]
    return "&mdash;".html_safe unless tech

    strip_prefix_and_titleize(tech, "TECH_")
  end

  def opening_strategy_scouts(row)
    SCOUT_LABELS.fetch(row[:opening_scouts][:category])
  end

  def opening_strategy_items(row)
    items = row[:opening_scouts][:items]
    return "&mdash;".html_safe if items.empty?

    items.map { |item| "t#{item[:turn]} #{opening_strategy_item_name(item)}" }.join(", ")
  end

  def opening_strategy_item_name(item)
    prefix = item[:kind] == :unit ? "UNIT_" : "BUILDING_"
    strip_prefix_and_titleize(item[:id], prefix)
  end

  def opening_strategy_style(row)
    style = row[:playstyle][:style]
    style ? style.to_s.titleize : "&mdash;".html_safe
  end

  def opening_strategy_worker_theft(row)
    row[:worker_theft].zero? ? "&mdash;".html_safe : row[:worker_theft].to_s
  end

  def opening_strategy_national_college(row)
    college = row[:national_college]
    return "&mdash;".html_safe unless college[:built_turn]
    return "t. #{college[:built_turn]} (#{college[:turns_after_finisher]} after finisher)" if college[:turns_after_finisher]
    return "t. #{college[:built_turn]} (#{national_college_early_label(college[:turns_early])})" if college[:turns_early]

    "t. #{college[:built_turn]}"
  end

  def national_college_early_label(turns_early)
    turns_early.negative? ? "#{-turns_early} late" : "#{turns_early} early"
  end

  def opening_strategy_wonders(row)
    wonders = row[:good_wonders]
    "#{wonders[:built].size}/#{wonders[:targets].size}"
  end

  def opening_strategy_workers_per_city(row)
    ratio = row[:workers_per_city][:ratio]
    ratio ? number_with_precision(ratio, precision: 2) : "&mdash;".html_safe
  end

  def opening_strategy_universities(row)
    universities = row[:universities]
    return "&mdash;".html_safe if universities.empty?

    "#{universities.count { |u| u[:on_target] }}/#{universities.size}"
  end

  def opening_strategy_caravans(row)
    turn = row[:caravans_to_capital][:first_turn]
    turn ? turn.to_s : "&mdash;".html_safe
  end
end
