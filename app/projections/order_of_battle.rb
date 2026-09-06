# What each civilization had under arms, turn by turn.
#
# Nothing in the log states an army's composition, so it is kept as a
# ledger: every unit_created adds one of its type, every unit_lost takes
# one away. That is exact enough to trust - measured against the
# snapshots' own military_units across three finished games, the count
# runs one unit low per civilization and no more. The missing one is the
# unit each civilization starts the game holding, placed before the
# logger attaches and so never created in the log's eyes.
#
# An upgrade needs no rule of its own: the game logs it as the new unit
# appearing and the old one leaving on the same turn, so the army changes
# shape while the ledger stays balanced.
class OrderOfBattle
  extend Projection

  DELTAS = { "unit_created" => 1, "unit_lost" => -1 }.freeze

  def initialize(game)
    @log = game.event_log
    @last_turn = @log.all.map(&:turn).max.to_i
    @movements = (@log.of_type("unit_created") + @log.of_type("unit_lost"))
                   .sort_by(&:seq).group_by(&:civ)
    @upgraded = upgraded_arrivals(@log)
    @ledgers = {}
  end

  def at(turn, civ) = ordered(stock_at(turn, civ))

  # A war is read from the turn before it was declared - what a side
  # marched in with - to the peace, or to the end of the log for a war
  # still burning when the record stops.
  def during(war)
    span = (war[:turn])..(war[:turn_peace] || @last_turn)
    sides(war).index_with { |civ| account(civ, span) }
  end

  private

  def sides(war) = Array(war[:attacker_civs]) + Array(war[:defender_civs])

  def account(civ, span)
    held = at(span.first - 1, civ)
    soldiers, civilians = arrivals_in(civ, span).partition { |event| soldier?(event.payload["unit"]) }
    built, re_armed = soldiers.partition { |event| !upgraded?(event) }

    { opening: held, closing: at(span.last, civ),
      raised: tally(built), upgraded: tally(re_armed), raised_civilian: tally(civilians),
      debuts: debuts(soldiers, held), **turning_points(civ, span) }
  end

  # A type the side did not already field is the arrival of a weapon, and
  # how it arrived separates a war paid for with production from one paid
  # for with gold. Great people are born mid-war whatever is happening at
  # the front, so they are none of this.
  def debuts(arrivals, held)
    arrivals.reject { |event| held.key?(event.payload["unit"]) }
            .sort_by(&:turn).uniq { |event| event.payload["unit"] }
            .map { |event| debut(event) }
  end

  def debut(event)
    { turn: event.turn, unit: event.payload["unit"], via: upgraded?(event) ? :upgraded : :built }
  end

  def upgraded?(event) = @upgraded.include?(event.seq)

  # Which arrivals re-armed a unit already standing. The game says how
  # many of a type were upgraded on a turn but not which of that turn's
  # arrivals they were, so each upgrade claims one arrival and the ones
  # left over were built.
  def upgraded_arrivals(log)
    budget = Hash.new(0)
    log.of_type("unit_upgraded").each { |event| budget[replacement(event)] += 1 }

    log.of_type("unit_created").filter_map do |event|
      next unless budget[arrival(event)].positive?

      budget[arrival(event)] -= 1
      event.seq
    end.to_set
  end

  def replacement(event) = [ event.civ, event.turn, event.payload["to"] ]

  def arrival(event) = [ event.civ, event.turn, event.payload["unit"] ]

  # The two ends of a long war hide its middle: a side can be built up,
  # broken and rebuilt without either end showing it. Only a high or a
  # low that beats both ends is worth a reader's attention, which leaves
  # a war that merely grew reporting neither.
  def turning_points(civ, span)
    sizes = ledger(civ).select { |turn, _| span.cover?(turn) }
                       .map { |turn, stock| [ turn, soldiers_in(stock) ] }
    ends = [ span.first - 1, span.last ].map { |turn| soldiers_in(stock_at(turn, civ)) }

    { peak: extreme(civ, sizes.select { |_turn, size| size > ends.max }, :max_by),
      nadir: extreme(civ, sizes.select { |_turn, size| size < ends.min }, :min_by) }
  end

  # Ties go to the earliest turn: the moment the army reached that
  # strength, not the last turn it held it.
  def extreme(civ, candidates, pick)
    reached = candidates.public_send(pick) { |_turn, size| size }&.last
    turn = candidates.find { |_turn, size| size == reached }&.first
    { turn: turn, units: at(turn, civ) } if turn
  end

  def arrivals_in(civ, span)
    movements_for(civ).select { |event| event.event_type == "unit_created" && span.cover?(event.turn) }
  end

  def movements_for(civ) = @movements.fetch(civ, [])

  def tally(events) = ordered(events.map { |event| event.payload["unit"] }.tally)

  def soldiers_in(stock) = stock.sum { |unit, count| soldier?(unit) ? count : 0 }

  def soldier?(unit) = WarCasualties.kind_of(unit) != :civilian

  # A type is dropped once its last unit is gone rather than left standing
  # at zero, and the heaviest comes first: a chronicle names what an army
  # was mostly made of.
  def ordered(stock)
    stock.reject { |_unit, count| count.zero? }.sort_by { |_unit, count| -count }.to_h
  end

  def stock_at(turn, civ)
    ledger(civ).reverse_each.find { |recorded, _| recorded <= turn }&.last || {}
  end

  # One stock per turn on which the army changed, in turn order.
  def ledger(civ)
    @ledgers[civ] ||= build_ledger(civ)
  end

  def build_ledger(civ)
    stock = Hash.new(0)
    movements_for(civ).chunk_while { |before, after| before.turn == after.turn }.map do |turn|
      turn.each { |event| apply(stock, event) }
      [ turn.first.turn, stock.dup ]
    end
  end

  # A unit lost without ever having been created is one the civilization
  # began the game with. It costs the count a unit; it must not cost it a
  # negative army.
  def apply(stock, event)
    unit = event.payload["unit"]
    stock[unit] = [ stock[unit] + DELTAS.fetch(event.event_type), 0 ].max
  end
end
