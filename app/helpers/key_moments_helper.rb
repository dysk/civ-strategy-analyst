# One sentence per detected moment. Sections mix several kinds of moment
# in a single chronological list, so the phrasing lives here rather than in
# a branch of the template.
module KeyMomentsHelper
  def humanize_influence_level(level)
    level.to_s.sub("INFLUENCE_LEVEL_", "").capitalize
  end

  # The log only names a religion by its internal key for the fixed set
  # LEKMOD ships - TXT_KEY_RELIGION_PROTESTANTISM is Protestantism. A player
  # who typed a custom name at founding has it stored as that literal text
  # instead, which already reads as a name and needs no decoding.
  def religion_name(key) = strip_prefix_and_titleize(key, "TXT_KEY_RELIGION_")

  DESCRIPTIONS = {
    war: ->(m) { declaration(m) },
    buffer_city_lost: ->(m) { "#{m[:civ]} lost #{m[:city]} to #{m[:captured_by]}, " \
                             "the city between its capital and #{m[:against]}'s" },
    leader_change: ->(m) { "#{m[:metric]} lead passed from #{m[:from]} to #{m[:to]}" },
    era_lead: ->(m) { "#{m[:civs].join(", ")} reached #{m[:era]} first" },
    pantheon_founded: ->(m) { "#{m[:civ]} founded a pantheon with #{m[:belief]}" },
    religion_founded: ->(m) { "#{m[:civ]} founded #{religion_name(m[:religion])} (##{m[:order]}) with #{Array(m[:beliefs]).join(", ")}" },
    player_declared_irrelevant: ->(m) {
      "#{m[:civ]} asked to be ruled out of contention, and the other players agreed " \
        "(#{m[:yes_votes]}–#{m[:no_votes]})"
    },
    religion_enhanced: ->(m) { "#{m[:civ]} enhanced #{religion_name(m[:religion])} with #{Array(m[:beliefs]).join(", ")}" },
    reformation_added: ->(m) { "#{m[:civ]} added the reformation belief #{m[:belief]} to #{religion_name(m[:religion])}" },
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
    influence_level_reached: ->(m) { "#{m[:civ]} became #{humanize_influence_level(m[:level])} on #{m[:opponent]}" },
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
    science_victory_imminent: ->(m) { "#{m[:civ]} assembled #{m[:parts_assembled]} of 6 spaceship parts" },
    wonder_race: ->(m) { "#{m[:wonder_name]} became a contested build: #{m[:winner]} against #{m[:contenders].join(", ")}" },
    wonder_race_lost: ->(m) {
      rushed = " — #{m[:winner]} finished it ahead of a hard build" if m[:winner_finish] == :ahead_of_estimate
      "#{m[:civ]} lost the race for #{m[:wonder_name]} to #{m[:winner]}, #{m[:production_invested]} production sunk in" \
        "#{rushed}#{full_view_clause(m)}"
    }
  }.freeze

  # This is where espionage reaches a reader who never opens the page, and it
  # must not overstate what the log shows: the turns of vision, never the
  # decision they invite. An AI contender made no decision to invite, so the
  # clause stays silent on it even when it was observed.
  def full_view_clause(moment)
    return unless moment[:contender_human] && moment[:observed_from_turn]

    " — #{moment[:civ]} had #{moment[:observed_turns]} turns of visibility on it, from turn #{moment[:observed_from_turn]}"
  end

  TRENDS = {
    army_power_surge: :up, army_power_collapse: :down,
    happiness_surge: :up, happiness_collapse: :down,
    capital_gained: :up, capital_lost: :down,
    buffer_city_lost: :down, player_declared_irrelevant: :down,
    wonder_race_lost: :down
  }.freeze

  ARROWS = { up: "▲", down: "▼" }.freeze

  # A swing's direction should be visible before the sentence is read. The
  # sentence still says it, so the arrow is decorative.
  def key_moment_trend(moment)
    direction = TRENDS[moment[:type]]
    return unless direction

    tag.span(ARROWS[direction], class: "trend trend--#{direction}", aria: { hidden: true })
  end

  # The declaration says who and when; each further line says what the war
  # cost, and that is what tells a raid for a worker from a conquest. One
  # line per kind of cost keeps a long war readable where a single run-on
  # sentence did not.
  #
  # A roster runs to a dozen types with a tail of one unit each. Its head
  # is what tells one army from another; the rest is inventory.
  ARMY_TYPES_NAMED = 3

  # Arrivals run longer, because a war of eighty turns turns on them and
  # the list is already down to soldiers the side did not start with. A
  # line is still not a table.
  ARRIVALS_NAMED = 6

  # Where each kind of arrival is counted: a type built is counted among
  # what the side raised, a type re-armed among what it upgraded. A type
  # that arrived both ways belongs in each list for its own share.
  ARRIVAL_COUNTS = { built: :raised, upgraded: :upgraded }.freeze

  # The view lists these under the moment's headline. Only a war has any.
  def key_moment_details(moment)
    return unless moment[:type] == :war

    [ opening(moment), *tolls(moment), *armies(moment) ].compact
  end

  def armies(moment)
    forces = moment[:forces] || {}

    [ sides_named(forces, "fielded") { |side| leading(side[:opening]) },
      sides_named(forces, "built") { |side| arrivals(side, :built) },
      sides_named(forces, "re-armed") { |side| arrivals(side, :upgraded) } ]
  end

  def sides_named(forces, label)
    named = forces.transform_values { |side| yield(side) }.reject { |_civ, text| text.blank? }
    return if named.empty?

    "#{label}: " + named.map { |civ, text| "#{civ} #{text}" }.join("; ")
  end

  # A roster counts workers and caravans, which is right for a ledger and
  # wrong for a sentence about a war.
  def leading(units)
    units.reject { |unit, _count| WarCasualties.kind_of(unit) == :civilian }
         .first(ARMY_TYPES_NAMED).map { |unit, count| "#{unit_name(unit)} #{count}" }.join(", ")
  end

  # The earliest arrivals in a long war are whatever the tech tree happened
  # to obsolete first. What a side put four of into the field is the one
  # worth the sentence.
  def arrivals(side, via)
    counted = side[:debuts].select { |debut| debut[:via] == via }
                           .map { |debut| debut.merge(count: side[ARRIVAL_COUNTS.fetch(via)].fetch(debut[:unit], 0)) }

    counted.sort_by { |debut| [ -debut[:count], debut[:turn] ] }.first(ARRIVALS_NAMED)
           .map { |debut| "#{unit_name(debut[:unit])} #{debut[:count]} (turn #{debut[:turn]})" }
           .join(", ")
  end

  def declaration(moment)
    "#{moment[:attacker_civs].join(", ")} declared war on #{moment[:defender_civs].join(", ")} " \
      "(#{moment[:turn_peace] ? "peace at turn #{moment[:turn_peace]}" : "ongoing"})"
  end

  def opening(moment)
    blood = moment[:first_blood]
    return unless blood

    "opening on #{possessive(blood[:civ])} #{unit_name(blood[:unit])} " \
      "#{blood[:fate] == :captured ? "taken" : "killed"}"
  end

  def possessive(civ) = civ.end_with?("s") ? "#{civ}'" : "#{civ}'s"

  def tolls(moment)
    toll = moment[:toll] || {}

    [ counted("dead", toll, :losses, every_side: true), counted("taken", toll, :captured) ]
  end

  def counted(label, toll, field, every_side: false)
    return if toll.values.sum { |side| side[field] }.zero?

    sides = toll.select { |_civ, side| every_side || side[field].positive? }

    "#{label}: #{sides.map { |civ, side| "#{civ} #{side[field]}" }.join(", ")}"
  end

  def unit_name(unit) = unit_names.call(unit)

  # The view knows the game, and the game knows which ruleset named its
  # units; a helper called outside one falls back to reading the id.
  def unit_names = @unit_names ||= UnitNames.for(@game&.lekmod_version)

  def key_moment_sentence(moment)
    "#{key_moment_turns(moment)}: #{instance_exec(moment, &DESCRIPTIONS.fetch(moment[:type]))}"
  end

  def key_moment_turns(moment)
    return "Turn #{moment[:turn]}" if moment[:turn_end].nil? || moment[:turn_end] == moment[:turn]

    "Turns #{moment[:turn]}–#{moment[:turn_end]}"
  end
end
