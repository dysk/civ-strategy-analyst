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

  # A turn is an acceleration when its stored production stands this far clear
  # of the build's own typical turn. Calibrated on the 23 turns in the two
  # example logs where the game's estimate fell faster than the clock: three
  # sit at 2.09, 2.28 and 2.29 and the next highest is 1.50, so the factor
  # falls in a gap the data has rather than one chosen for it.
  ACCELERATION_FACTOR = 2.0

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
      winner_accelerated_on_turns: accelerated_on(own_build(builders, winner)),
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
    own = own_build(builders, winner)
    return :unobserved unless own

    own.last.payload["production_turns_left"].to_i <= LOST_WINDOW ? :hard_built : :ahead_of_estimate
  end

  def own_build(builders, winner)
    builders.find { |b| b[:civ] == winner[:civ] && b[:city] == winner[:city] }&.fetch(:snapshots)
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
    accelerated = accelerated_on(snapshots)

    { observed_from_turn: from, observed_turns: observed_turns(watchers, row, window, from),
      observed_by: watchers.map { |tenure| tenure[:civ] }.uniq,
      contender_human: human?(row[:civ]), accelerated_on_turns: accelerated,
      response: response(row, accelerated) }.merge(rates(snapshots, from))
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

  # A turn whose stored production stands clear of the build's own turns: a
  # Great Engineer, a chopped forest or the overflow from whatever the city
  # built before. What the log cannot do is name which, the same limit
  # `winner_finish` runs into.
  #
  # Recorded for every builder whether or not it held a spy, because a spy is
  # not the only way a rival build can be known about: a wonder under
  # construction stands on the map and its unfinished form is particular to the
  # wonder. That channel is an opportunity and nothing more - the log never
  # says the tile was ever revealed, never says anybody looked at it, and never
  # says the model was recognised. So this field is a fact about the build and
  # not about anyone's knowledge, and no reading may turn it into a response.
  #
  # The game's own `production_turns_left` is not the test. It falls faster
  # than the clock on any small rise in the city's current rate, because the
  # ceiling amplifies one at distance - 20 of the 23 such falls in the two logs
  # brought no extra production with them, and four of those came with less.
  #
  # A city gradually re-arranged onto hammers is not an event and is not found
  # here. It raises the typical turn along with the rest and shows in
  # `rate_before` against `rate_after`.
  def accelerated_on(snapshots)
    gains = turn_gains(Array(snapshots))
    typical = median(gains.map(&:last))
    return [] unless typical&.positive?

    gains.filter_map { |turn, gained| acceleration(turn, gained, typical) if gained >= typical * ACCELERATION_FACTOR }
  end

  def acceleration(turn, gained, typical)
    { turn: turn, production_gained: gained, times_typical: (gained / typical).round(1) }
  end

  def turn_gains(snapshots)
    snapshots.each_cons(2).map { |earlier, later| [ later.turn, stored(later) - stored(earlier) ] }
  end

  def median(values)
    return if values.empty?

    values.sort[values.size / 2].to_f
  end

  # What the contender did, never what it knew - `observed_from_turn` carries
  # that separately. Only a human made a decision worth naming: no AI code
  # reads surveillance, and AI_chooseProduction is passed
  # bInterruptWonders = false at all four call sites, so an AI that started a
  # losing wonder was never going to reconsider it.
  def response(row, accelerated)
    return unless human?(row[:civ])
    return :cut_losses if row[:outcome] == :abandoned

    accelerated.any? ? :accelerated : :pressed_on
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
