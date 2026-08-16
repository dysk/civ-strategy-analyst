# One sentence per detected moment. Sections mix several kinds of moment
# in a single chronological list, so the phrasing lives here rather than in
# a branch of the template.
module KeyMomentsHelper
  DESCRIPTIONS = {
    war: ->(m) { "#{m[:attacker_civs].join(", ")} declared war on #{m[:defender_civs].join(", ")} " \
                 "(#{m[:turn_peace] ? "peace at turn #{m[:turn_peace]}" : "ongoing"})" },
    leader_change: ->(m) { "#{m[:metric]} lead passed from #{m[:from]} to #{m[:to]}" },
    era_lead: ->(m) { "#{m[:civs].join(", ")} reached #{m[:era]} first" },
    pantheon_founded: ->(m) { "#{m[:civ]} founded a pantheon with #{m[:belief]}" },
    religion_founded: ->(m) { "#{m[:civ]} founded #{m[:religion]} (##{m[:order]}) with #{Array(m[:beliefs]).join(", ")}" },
    religion_enhanced: ->(m) { "#{m[:civ]} enhanced #{m[:religion]} with #{Array(m[:beliefs]).join(", ")}" },
    reformation_added: ->(m) { "#{m[:civ]} added the reformation belief #{m[:belief]} to #{m[:religion]}" },
    ideology_unlocked: ->(m) { "#{m[:civ]} unlocked #{m[:ideology]}" },
    ideology_adopted: ->(m) { "#{m[:civ]} adopted #{m[:ideology]}" },
    tenet_adopted: ->(m) { "#{m[:civ]} adopted the #{m[:ideology]} tenet #{m[:tenet]}" },
    policy_branch_adopted: ->(m) { "#{m[:civ]} adopted #{m[:branch]}" },
    policy_branch_completed: ->(m) { "#{m[:civ]} completed #{m[:branch]}" },
    army_power_surge: ->(m) { "#{m[:civ]} army power jumped from #{m[:from]} to #{m[:to]}" },
    army_power_collapse: ->(m) { "#{m[:civ]} army power dropped from #{m[:from]} to #{m[:to]}" },
    happiness_surge: ->(m) { "#{m[:civ]} happiness jumped from #{m[:from]} to #{m[:to]}" },
    happiness_collapse: ->(m) { "#{m[:civ]} happiness dropped from #{m[:from]} to #{m[:to]}" },
    unhappiness_period: ->(m) { "#{m[:civ]} happiness stayed below zero" },
    snowball: ->(m) { "#{m[:civ]} pulled decisively ahead" },
    nuclear_detonation: ->(m) { "#{m[:civ]} detonated a nuclear weapon on #{m[:city]}" },
    city_state_ally_takeover: ->(m) { "#{m[:to]} took #{m[:city_state]}'s alliance from #{m[:from]}" }
  }.freeze

  TRENDS = {
    army_power_surge: :up, army_power_collapse: :down,
    happiness_surge: :up, happiness_collapse: :down
  }.freeze

  ARROWS = { up: "▲", down: "▼" }.freeze

  # A swing's direction should be visible before the sentence is read. The
  # sentence still says it, so the arrow is decorative.
  def key_moment_trend(moment)
    direction = TRENDS[moment[:type]]
    return unless direction

    tag.span(ARROWS[direction], class: "trend trend--#{direction}", aria: { hidden: true })
  end

  def key_moment_sentence(moment)
    "#{key_moment_turns(moment)}: #{DESCRIPTIONS.fetch(moment[:type]).call(moment)}"
  end

  def key_moment_turns(moment)
    return "Turn #{moment[:turn]}" if moment[:turn_end].nil? || moment[:turn_end] == moment[:turn]

    "Turns #{moment[:turn]}–#{moment[:turn_end]}"
  end
end
