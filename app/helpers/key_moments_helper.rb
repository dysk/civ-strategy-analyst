# One sentence per detected moment. Sections mix several kinds of moment
# in a single chronological list, so the phrasing lives here rather than in
# a branch of the template.
module KeyMomentsHelper
  def self.humanize_influence_level(level)
    level.to_s.sub("INFLUENCE_LEVEL_", "").capitalize
  end

  DESCRIPTIONS = {
    war: ->(m) { KeyMomentsHelper.war_sentence(m) },
    buffer_city_lost: ->(m) { "#{m[:civ]} lost #{m[:city]} to #{m[:captured_by]}, " \
                             "the city between its capital and #{m[:against]}'s" },
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
    city_state_ally_takeover: ->(m) { "#{m[:to]} took #{m[:city_state]}'s alliance from #{m[:from]}" },
    influence_level_reached: ->(m) { "#{m[:civ]} became #{KeyMomentsHelper.humanize_influence_level(m[:level])} on #{m[:opponent]}" },
    cultural_victory_imminent: ->(m) {
      "#{m[:civ]} is culturally influential on #{m[:civs_influential_on]} of #{m[:living_majors]} living majors"
    },
    congress_host_change: ->(m) { "World Congress host passed from #{m[:from] || "no host"} to #{m[:to]}" },
    united_nations_formed: ->(_m) { "The United Nations formed" },
    diplomatic_victory_imminent: ->(m) {
      "#{m[:civ]} reached #{m[:votes]} delegate votes, meeting the #{m[:votes_needed]} needed for a diplomatic victory"
    },
    resolution_passed: ->(m) {
      subject = m[:repeal] ? "The repeal of #{m[:resolution]}" : m[:resolution]
      "#{subject} passed, proposed by #{m[:proposer]}"
    },
    capital_gained: ->(m) { "#{m[:civ]} gained control of #{m[:original_owner]}'s original capital" },
    capital_lost: ->(m) { "#{m[:civ]} lost control of #{m[:original_owner]}'s original capital" },
    apollo_completed: ->(m) { "#{m[:civ]} completed the Apollo Program" },
    spaceship_part_assembled: ->(m) { "#{m[:civ]} assembled a #{m[:part]} (#{m[:count]} total)" },
    science_victory_imminent: ->(m) { "#{m[:civ]} assembled #{m[:parts_assembled]} of 6 spaceship parts" }
  }.freeze

  TRENDS = {
    army_power_surge: :up, army_power_collapse: :down,
    happiness_surge: :up, happiness_collapse: :down,
    capital_gained: :up, capital_lost: :down,
    buffer_city_lost: :down
  }.freeze

  ARROWS = { up: "▲", down: "▼" }.freeze

  # A swing's direction should be visible before the sentence is read. The
  # sentence still says it, so the arrow is decorative.
  def key_moment_trend(moment)
    direction = TRENDS[moment[:type]]
    return unless direction

    tag.span(ARROWS[direction], class: "trend trend--#{direction}", aria: { hidden: true })
  end

  # A war's declaration says who and when; what it cost says which kind of
  # war it was, and that is what tells a raid for a worker from a
  # conquest. Both sides are named whenever either bled - a war one side
  # came through untouched reads as an even fight without the other figure.
  def self.war_sentence(moment)
    [ declaration(moment), opening(moment), *tolls(moment) ].compact.join
  end

  def self.declaration(moment)
    "#{moment[:attacker_civs].join(", ")} declared war on #{moment[:defender_civs].join(", ")} " \
      "(#{moment[:turn_peace] ? "peace at turn #{moment[:turn_peace]}" : "ongoing"})"
  end

  def self.opening(moment)
    blood = moment[:first_blood]
    return unless blood

    ", opening on #{possessive(blood[:civ])} #{unit_name(blood[:unit])} " \
      "#{blood[:fate] == :captured ? "taken" : "killed"}"
  end

  def self.possessive(civ) = civ.end_with?("s") ? "#{civ}'" : "#{civ}'s"

  def self.tolls(moment)
    toll = moment[:toll] || {}

    [ counted("dead", toll, :losses, every_side: true), counted("taken", toll, :captured) ]
  end

  def self.counted(label, toll, field, every_side: false)
    return if toll.values.sum { |side| side[field] }.zero?

    sides = toll.select { |_civ, side| every_side || side[field].positive? }

    "; #{label}: #{sides.map { |civ, side| "#{civ} #{side[field]}" }.join(", ")}"
  end

  def self.unit_name(unit) = unit.delete_prefix("UNIT_").downcase.titleize

  def key_moment_sentence(moment)
    "#{key_moment_turns(moment)}: #{DESCRIPTIONS.fetch(moment[:type]).call(moment)}"
  end

  def key_moment_turns(moment)
    return "Turn #{moment[:turn]}" if moment[:turn_end].nil? || moment[:turn_end] == moment[:turn]

    "Turns #{moment[:turn]}–#{moment[:turn_end]}"
  end
end
