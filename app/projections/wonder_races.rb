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
    @game = game
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
      .map { |builder| contender(builder, winner, completion.turn) }
    return if contenders.empty?

    { wonder: wonder, wonder_name: @wonders.name(wonder), completed_turn: completion.turn,
      contended_from_turn: contended_from(builders), winner: winner,
      winner_finish: winner_finish(builders, winner), contenders: contenders,
      rival_observed: rival_observed(contenders) }
  end

  # The turn a second builder joined a wonder already under way. With only
  # one builder ever seen - the winner completed it unobserved - it is that
  # builder's own start, from when they were racing whoever finished it.
  def contended_from(builders)
    starts = builders.map { |builder| builder[:snapshots].first.turn }.sort

    starts[1] || starts[0]
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

  def contender(builder, winner, completed_turn)
    row = built(builder, completed_turn)

    row.merge(observation(row, builder[:snapshots], winner[:city], completed_turn))
  end

  # A wonder that leaves `producing` on the completion turn or the one after
  # was lost; one dropped earlier was a change of plans.
  def built(builder, completed_turn)
    snapshots = builder[:snapshots]
    turns = snapshots.map(&:turn).uniq

    { civ: builder[:civ], city: builder[:city],
      first_seen_turn: turns.first, last_seen_turn: turns.last, turns_building: turns.size,
      production_invested: snapshots.last.payload["production_stored"].to_i,
      turns_left_when_last_seen: snapshots.last.payload["production_turns_left"],
      outcome: (completed_turn - turns.last <= LOST_WINDOW ? :lost : :abandoned) }
  end

  # What the contender could see of the winner's city while a decision was
  # still available - its own first snapshot to its last, which for a civ that
  # walked away is the turn it walked. "Held a spy during the race" is the
  # wrong question: it answers yes for a spy whose surveillance went live on
  # the completion turn.
  def observation(row, snapshots, watched, completed_turn)
    window = decidable(row, completed_turn)
    watchers = window ? observers_of(watched, window.first, window.last) : []
    from = observed_from(watchers, row)
    accelerated = accelerated_on(snapshots, from)

    { observed_from_turn: from, observed_turns: observed_turns(watchers, row, window, from),
      observed_by: watchers.map { |tenure| tenure[:civ] }.uniq,
      contender_human: human?(row[:civ]), accelerated_on_turn: accelerated,
      response: response(row, from, accelerated) }.merge(rates(snapshots, from))
  end

  # The turns the contender was still building and the wonder was not yet
  # finished. The completion turn is not one of them, whatever the contender
  # was still doing on it.
  def decidable(row, completed_turn)
    last = [ row[:last_seen_turn], completed_turn - 1 ].min

    row[:first_seen_turn]..last if last >= row[:first_seen_turn]
  end

  # A third party watching the winner's city is a different fact from the
  # contender watching it, so `observed_by` lists civs and the contender's own
  # vision is its `observed_from_turn`.
  def own_watch(watchers, row) = watchers.find { |tenure| tenure[:civ] == row[:civ] }

  def observed_from(watchers, row)
    own = own_watch(watchers, row)

    own && [ own[:visible_from_turn], row[:first_seen_turn] ].max
  end

  def observed_turns(watchers, row, window, from)
    return 0 unless from

    [ own_watch(watchers, row)[:until_turn], window.last ].min - from + 1
  end

  # Hammers a turn from the `production_stored` deltas, split at the turn the
  # contender first had vision. Described, never classified on - the estimate
  # is what decides whether anything changed.
  def rates(snapshots, from)
    return { rate_before: nil, rate_after: nil } unless from

    before, after = snapshots.partition { |snapshot| snapshot.turn <= from }
    { rate_before: mean_rate(before), rate_after: mean_rate([ before.last, *after ].compact) }
  end

  def mean_rate(snapshots)
    return if snapshots.size < 2

    gained = stored(snapshots.last) - stored(snapshots.first)
    (gained.to_f / (snapshots.last.turn - snapshots.first.turn)).round(2)
  end

  def stored(snapshot) = snapshot.payload["production_stored"].to_i

  # `production_turns_left` falls by exactly one a turn while a city builds at
  # a steady rate, because the stored production climbs by exactly the rate the
  # estimate divides by. A steeper fall is a lump the log has no other name for
  # - a Great Engineer, a chopped forest, a city re-arranged for hammers - and
  # needs no threshold to recognise.
  def accelerated_on(snapshots, from)
    return unless from

    pair = snapshots.each_cons(2).find do |earlier, later|
      later.turn > from && estimate_drop(earlier, later) > later.turn - earlier.turn
    end
    pair&.last&.turn
  end

  def estimate_drop(earlier, later)
    earlier.payload["production_turns_left"].to_i - later.payload["production_turns_left"].to_i
  end

  # Only a human made a decision worth naming. No AI code reads surveillance,
  # the engine reports no rival's build to anyone, and AI_chooseProduction is
  # passed bInterruptWonders = false at all four call sites, so an AI that
  # started a losing wonder was never going to reconsider it.
  def response(row, from, accelerated)
    return unless human?(row[:civ])
    return :unobserved unless from
    return :cut_losses if row[:outcome] == :abandoned

    accelerated ? :accelerated : :pressed_on
  end

  # Nil rather than false where the log carries no spy record at all: not
  # knowing is not the same as knowing nobody watched.
  def rival_observed(contenders)
    return unless espionage.applicable?

    contenders.any? { |contender| contender[:observed_from_turn] }
  end

  def observers_of(city, from_turn, to_turn)
    return [] unless espionage.applicable?

    espionage.observers_of(city, from_turn, to_turn)
  end

  def espionage = @espionage ||= Espionage.for(@game)

  def human?(civ) = humans.include?(civ)

  def humans = @humans ||= @game.players.where(human: true).pluck(:civ).to_set

  def completions
    @completions ||= @log.of_type("building_constructed").select { |e| e.payload["wonder"] == "world" }
  end

  def snapshots_by_producing
    @snapshots_by_producing ||= city_snapshots.group_by { |e| e.payload["producing"] }
  end

  def city_snapshots = @log.of_type("city_snapshot")
end
