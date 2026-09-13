# Which policy branch a civ opened into, and how long it took to close it.
# docs/ideal-opening.md's classification join: PlayerTimeline#policies'
# first :branch_adopted entry is the opening, before any tall/wide or
# Tradition/Liberty/Honor/Piety label gets attached to it.
class OpeningStrategy
  extend Projection

  def initialize(game)
    @game = game
    @timeline = PlayerTimeline.for(game)
  end

  def branch(civ)
    opened(civ)&.fetch(:name)
  end

  # docs/ideal-opening.md "General, any opening": first researched tech
  # should be Mining. A hut tech ahead of any deliberate research is a
  # windfall, not a choice, so it's skipped - unless it's Mining itself,
  # which satisfies the goal (revealing Iron early) regardless of how it
  # arrived.
  def first_tech(civ)
    @timeline.techs(civ).find { |entry| entry[:source] == :research || entry[:tech] == "TECH_MINING" }&.fetch(:tech)
  end

  def closed_opening(civ)
    opening = opened(civ)
    return unless opening

    finisher_policy = finisher_policy_for(opening[:name])
    finished = finished_at(civ, finisher_policy)

    { branch: opening[:name], opened_turn: opening[:turn], finisher_policy: finisher_policy,
      finished_turn: finished&.fetch(:turn), turns_to_close: finished && finished[:turn] - opening[:turn] }
  end

  # docs/ideal-opening.md "Worker theft — two independent paths", Path A: a
  # war the civ declared on a city-state, opened by taking its worker alive
  # rather than trading blows with it - a raid, not a real war. WarCasualties
  # already tells the two apart via first_blood; it takes the {turn,
  # turn_peace, attacker_civs, defender_civs} shape PlayerTimeline#wars
  # doesn't hand out directly, so it's rebuilt here from the one-sided
  # {civ, opponents} a war period carries for its own side.
  def worker_raids(civ)
    @timeline.wars(civ).select { |war| war[:role] == :attacker }.filter_map do |war|
      city_state = war[:opponents].first
      next unless @game.city_state_civs.include?(city_state)

      casualties_war = { turn: war[:turn_declared], turn_peace: war[:turn_peace],
                          attacker_civs: [ civ ], defender_civs: war[:opponents] }
      first_blood = war_casualties.first_blood(casualties_war)
      next unless first_blood && first_blood[:unit] == "UNIT_WORKER" && first_blood[:fate] == :captured

      { city_state: city_state, declared_turn: war[:turn_declared],
        captured_turn: first_blood[:turn], peace_turn: war[:turn_peace] }
    end
  end

  # docs/ideal-opening.md "Worker theft — two independent paths", Path B:
  # no war needed, just a city-state bullied for a unit. The mod's bully
  # penalties are fixed constants (-15 influence for gold, -50 for a
  # unit), so a friendship delta near -50 is checked against that exact
  # number rather than calibrated from the game's own data. Corroborated
  # against a worker actually appearing for the civ around that turn,
  # since a friendship swing near -50 could in principle come from
  # something else entirely.
  BULLY_WORKER_PENALTY = -50
  TOLERANCE = 3
  CORROBORATION_WINDOW = 1

  def bullied_workers(civ)
    @timeline.city_states(civ).select { |entry| entry[:type] == :friendship_changed }.filter_map do |entry|
      delta = entry[:new_friendship] - entry[:old_friendship]
      next unless (delta - BULLY_WORKER_PENALTY).abs <= TOLERANCE
      next unless worker_appeared?(civ, entry[:turn])

      { turn: entry[:turn], city_state: entry[:city_state], delta: delta }
    end
  end

  # docs/ideal-opening.md "National College timing": turn 100 on standard
  # speed (67 on quick, via the same GameSpeed factor EarlyGame's deadline
  # uses), measured from game start - except for a Liberty opening, where
  # the checklist expects it only after the tree closes, so the meaningful
  # figure there is turns after the finisher instead.
  NATIONAL_COLLEGE_TARGET_STANDARD_TURNS = 100
  NATIONAL_COLLEGE_BUILDINGS = %w[BUILDING_NATIONAL_COLLEGE BUILDING_ISRAEL_NATIONAL_COLLEGE].freeze

  def national_college(civ)
    built = @timeline.buildings(civ).find { |b| NATIONAL_COLLEGE_BUILDINGS.include?(b[:building]) }

    if branch(civ) == "POLICY_BRANCH_LIBERTY"
      finisher_turn = closed_opening(civ)[:finished_turn]
      turns_after_finisher = built && finisher_turn && built[:turn] - finisher_turn
      return { built_turn: built&.fetch(:turn), target_turn: nil, turns_early: nil,
               turns_after_finisher: turns_after_finisher }
    end

    target = national_college_target_turn
    { built_turn: built&.fetch(:turn), target_turn: target,
      turns_early: built && target - built[:turn], turns_after_finisher: nil }
  end

  private

  def national_college_target_turn
    GameSpeed.for(@game).turns(NATIONAL_COLLEGE_TARGET_STANDARD_TURNS)
  end

  def worker_appeared?(civ, turn)
    @game.event_log.of_type("unit_created").any? do |event|
      event.civ == civ && event.payload["unit"] == "UNIT_WORKER" && (event.turn - turn).abs <= CORROBORATION_WINDOW
    end
  end

  def war_casualties = @war_casualties ||= WarCasualties.for(@game)

  def opened(civ)
    @timeline.policies(civ).find { |entry| entry[:type] == :branch_adopted }
  end

  def finisher_policy_for(branch)
    branch.sub("POLICY_BRANCH_", "POLICY_") + "_FINISHER"
  end

  def finished_at(civ, finisher_policy)
    @timeline.policies(civ).find { |entry| entry[:type] == :policy_adopted && entry[:name] == finisher_policy }
  end
end
