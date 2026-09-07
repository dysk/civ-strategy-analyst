# The race for a world wonder: who was building it, how much they sank into
# it, and whether they lost it or walked away.
#
# There is no "wonder started" event and no wonder flag on a city snapshot,
# so a race is reconstructed by scanning `producing` across every city's
# snapshots up to the turn the wonder was completed. A completion with only
# its own builder in that scan was a race against nobody and is not
# reported. The gold a losing city is refunded is a rule of the game, not a
# fact in the log, so only the production sunk is carried here - never a
# gold figure.
#
# Two of the three example logs carry no `city_snapshot`, so a reader must
# check `applicable?` before trusting `races`.
class WonderRaces
  extend Projection

  LOST_WINDOW = 1

  def initialize(game)
    @log = game.event_log
    @wonders = Wonders.for(game.lekmod_version, observed: completions.map { |e| e.payload["building"] })
  end

  def applicable? = city_snapshots.any?

  # One record per contested world wonder, earliest completion first.
  def races
    @races ||= completions.filter_map { |completion| race_for(completion) }
                          .sort_by { |race| race[:completed_turn] }
  end

  private

  def race_for(completion)
    wonder = completion.payload["building"]
    winner = { civ: completion.civ, city: completion.payload["city"] }

    builders = builders_of(wonder, completion.turn)
    contenders = builders
      .reject { |builder| builder[:civ] == winner[:civ] && builder[:city] == winner[:city] }
      .map { |builder| contender(builder, completion.turn) }
    return if contenders.empty?

    { wonder: wonder, wonder_name: @wonders.name(wonder), completed_turn: completion.turn,
      winner: winner, winner_finish: winner_finish(builders, winner),
      contenders: contenders, rival_observed: nil }
  end

  # Whether the wonder outran a hard build. A Great Engineer, a production
  # overflow, a chopped forest or a granted building all read the same way -
  # the last snapshot before completion still estimating turns to go - and
  # the log cannot tell them apart. Nil of india-diplo's 42 wonders fired
  # this, so the :ahead_of_estimate branch is unverified.
  def winner_finish(builders, winner)
    own = builders.find { |b| b[:civ] == winner[:civ] && b[:city] == winner[:city] }
    return :unobserved unless own

    own[:snapshots].last.payload["production_turns_left"].to_i <= LOST_WINDOW ? :hard_built : :ahead_of_estimate
  end

  # Every city seen building `wonder` on or before its completion, one entry
  # per city with its snapshots in turn order. A reload can log a turn
  # twice; the later payload wins, as CityCensus resolves the same case.
  def builders_of(wonder, completed_turn)
    rows = snapshots_by_producing.fetch(wonder, []).select { |e| e.turn <= completed_turn }

    rows.group_by { |e| [ e.turn, e.civ, e.payload["city"] ] }
        .map { |_key, dupes| dupes.last }
        .group_by { |e| [ e.civ, e.payload["city"] ] }
        .map { |(civ, city), snapshots| { civ: civ, city: city, snapshots: snapshots.sort_by(&:turn) } }
  end

  # A wonder that leaves `producing` on the completion turn or the one after
  # was lost; one dropped earlier was a change of plans.
  def contender(builder, completed_turn)
    snapshots = builder[:snapshots]
    turns = snapshots.map(&:turn).uniq

    { civ: builder[:civ], city: builder[:city],
      first_seen_turn: turns.first, last_seen_turn: turns.last, turns_building: turns.size,
      production_invested: snapshots.last.payload["production_stored"].to_i,
      turns_left_when_last_seen: snapshots.last.payload["production_turns_left"],
      outcome: (completed_turn - turns.last <= LOST_WINDOW ? :lost : :abandoned) }
  end

  def completions
    @completions ||= @log.of_type("building_constructed").select { |e| e.payload["wonder"] == "world" }
  end

  def snapshots_by_producing
    @snapshots_by_producing ||= city_snapshots.group_by { |e| e.payload["producing"] }
  end

  def city_snapshots = @log.of_type("city_snapshot")
end
