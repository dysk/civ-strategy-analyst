module GamesHelper
  # A stroked link glyph that inherits the current text colour, so it reads
  # in both themes without a second asset.
  ANCHOR_ICON = <<~SVG.freeze
    <svg viewBox="0 0 24 24" width="15" height="15" fill="none" stroke="currentColor" stroke-width="2" stroke-linecap="round" stroke-linejoin="round" aria-hidden="true">
      <path d="M9 15 15 9"/>
      <path d="M11 6l1-1a4 4 0 0 1 6 6l-1 1"/>
      <path d="M13 18l-1 1a4 4 0 0 1-6-6l1-1"/>
    </svg>
  SVG

  # A section heading that is its own anchor, with a link back to itself
  # beside it.
  def section_heading(title, id)
    content_tag(:h2, id: id) do
      safe_join([ title, " ",
                  link_to(ANCHOR_ICON.html_safe, "##{id}", class: "heading-anchor",
                          aria: { label: "Link to #{title}" }) ])
    end
  end

  # Where the outcome came from: inferred from the score curve, handed in by
  # hand, or read from the logger's own game_ended record.
  OUTCOME_SOURCES = {
    inferred: "inferred leader", declared: "declared winner", logged: "from game log"
  }.freeze

  def outcome_source_label(source) = OUTCOME_SOURCES.fetch(source, source.to_s)

  # A game log names things - resources, city-state traits and
  # personalities - by their internal id, which happens to decode to their
  # display name word for word. A value already free of the prefix (a
  # player-typed name, for instance) is not this game's to touch, so it
  # passes through unchanged.
  def strip_prefix_and_titleize(value, prefix)
    return value unless value.to_s.start_with?(prefix)

    value.delete_prefix(prefix).tr("_", " ").downcase.titleize
  end

  def resource_name(id) = strip_prefix_and_titleize(id, "RESOURCE_")
  def minor_civ_trait_name(id) = strip_prefix_and_titleize(id, "MINOR_TRAIT_")
  def minor_civ_personality_name(id) = strip_prefix_and_titleize(id, "MINOR_CIV_PERSONALITY_")

  # A team victory keeps every member; winner_civ is only its first name.
  def outcome_winner_names(game, outcome)
    game.winner_civs.presence&.join(", ") || outcome[:winner_civ]
  end
end
