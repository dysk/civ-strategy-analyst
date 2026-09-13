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

  private

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
