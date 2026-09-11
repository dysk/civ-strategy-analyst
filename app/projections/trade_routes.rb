# Where a civ's caravans went, how many ran at once, and which routes paid
# only one side. docs/reading-the-new-log.md §7.
#
# A route carries no id, so its lifetime is reconstructed by pairing each
# `trade_route_established` with the next `trade_route_ended` sharing its
# (civ, from_city, to_city, to_civ) key - a greedy match that is sometimes
# wrong, since a re-established pair can steal another instance's end. The
# reconstruction never trusts a matched end past the route's own
# `turns_left` estimate, and flags every point where it had to fall back.
class TradeRoutes
  extend Projection

  YIELDS = %w[gold science tourism].freeze

  def initialize(game)
    @game = game
    @log = game.event_log
  end

  def applicable? = established.any?

  # A civ's routes split by where the caravan went: its own empire (food or
  # production, never gold), a city-state, or another major.
  def by_destination(civ)
    mine = established.select { |e| e.civ == civ }
    own, abroad = mine.partition { |e| e.payload["to_civ"] == civ }

    { own: own.group_by { |e| e.payload["type"] }.transform_values(&:size).symbolize_keys,
      city_state: abroad.count { |e| city_state?(e.payload["to_civ"]) },
      major: abroad.count { |e| !city_state?(e.payload["to_civ"]) } }
  end

  # Established major-to-major routes where one side receives nothing of a
  # yield the other side does - a civ feeding a rival's science or tourism
  # without ever seeing a return, invisible unless the two sides are
  # compared directly.
  def one_sided
    established.select { |e| e.payload["type"] == "international" && !city_state?(e.payload["to_civ"]) }
      .flat_map { |e| asymmetries(e) }
  end

  # Live route count for civ at every turn a route starts or stops being
  # live. Each point flags whether any route contributing to its count fell
  # back to `turns_left` - because no end was recorded, or because the one
  # matched ran past that estimate.
  def concurrency(civ)
    routes = reconstructed_routes(civ)
    boundaries = (routes.map { |r| r[:from_turn] } + routes.map { |r| r[:to_turn] }).uniq.sort

    boundaries.map do |turn|
      live = routes.select { |r| r[:from_turn] <= turn && turn < r[:to_turn] }
      { turn: turn, count: live.size, flagged: live.any? { |r| r[:flagged] } }
    end
  end

  private

  def city_state?(civ) = @game.city_state_civs.include?(civ)

  def asymmetries(event)
    payload = event.payload

    YIELDS.filter_map do |yield_type|
      civ_value = payload.fetch("from_#{yield_type}", 0)
      other_value = payload.fetch("to_#{yield_type}", 0)
      next unless civ_value.zero? != other_value.zero?

      { civ: event.civ, other_civ: payload["to_civ"], from_city: payload["from_city"], to_city: payload["to_city"],
        turn: event.turn, yield: yield_type, civ_value: civ_value, other_civ_value: other_value }
    end
  end

  def reconstructed_routes(civ)
    starts = established.select { |e| e.civ == civ }.group_by { |e| route_key(e) }
    ends = ended.select { |e| e.civ == civ }.group_by { |e| route_key(e) }

    starts.flat_map { |key, events| match(events.sort_by(&:turn), ends.fetch(key, []).sort_by(&:turn)) }
  end

  # First-end-after-start, chronological, one end consumed per start.
  def match(starts, available_ends)
    available_ends = available_ends.dup

    starts.map do |start|
      matched = available_ends.find { |e| e.turn > start.turn }
      available_ends.delete(matched) if matched
      expiry = start.turn + start.payload["turns_left"].to_i

      { from_turn: start.turn, to_turn: [ matched&.turn, expiry ].compact.min,
        flagged: matched.nil? || matched.turn > expiry }
    end
  end

  def route_key(event) = [ event.civ, event.payload["from_city"], event.payload["to_city"], event.payload["to_civ"] ]

  def established = @log.of_type("trade_route_established")
  def ended = @log.of_type("trade_route_ended")
end
