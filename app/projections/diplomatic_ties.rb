# Diplomacy the log records as fact rather than inference: embassies, open
# borders, friendship, defensive pacts and trade agreements. `friendship_*`
# fires once per pair as a `civs` array; the other four fire once per side as
# `civ`/`other_civ`, both directions on the same turn - matched by the
# unordered pair, the mirrored pair collapses into the one span it is.
# docs/reading-the-new-log.md §6.
#
# Declaring war cancels every standing agreement with the target immediately
# - a rule of the game, not a reading of the log. India-Iroquois's embassy
# logs its own `embassy_ended` a turn after `war_declared`, which is the
# engine's bookkeeping catching up, not a second turn of real standing - a
# span still open when a war opens between the same pair is cut to the
# declaration turn regardless of what its own close event says, or whether
# it ever fires one at all.
class DiplomaticTies
  extend Projection

  TYPES = {
    "embassy" => %w[embassy_established embassy_ended],
    "open_borders" => %w[open_borders_granted open_borders_revoked],
    "friendship" => %w[friendship_declared friendship_ended],
    "defensive_pact" => %w[defensive_pact_signed defensive_pact_ended],
    "trade_agreement" => %w[trade_agreement_signed trade_agreement_ended]
  }.freeze

  def initialize(game)
    @log = game.event_log
  end

  def applicable? = TYPES.values.flatten.any? { |type| @log.of_type(type).any? }

  # Every tie between civ and other, oldest first: each type's own open/close
  # events paired into spans, `to_turn` nil while still standing.
  def spans(civ, other)
    TYPES.flat_map { |type, (open_type, close_type)| spans_for(type, open_type, close_type, civ, other) }
      .sort_by { |span| span[:from_turn] }
  end

  private

  def spans_for(type, open_type, close_type, civ, other)
    events = events_for(open_type, close_type, civ, other)
    wars = war_declaration_turns(civ, other)
    spans = []
    from_turn = nil

    events.each do |turn, action|
      if action == :open
        from_turn ||= turn
      elsif from_turn
        spans << span(type, from_turn, turn, wars)
        from_turn = nil
      end
    end

    spans << span(type, from_turn, nil, wars) if from_turn
    spans
  end

  # A war declared while the span was open outranks whatever its own close
  # event (or lack of one) says - the earliest such war is when the
  # agreement actually ended.
  def span(type, from_turn, to_turn, wars)
    war_turn = wars.select { |turn| turn >= from_turn && (to_turn.nil? || turn <= to_turn) }.min
    { type: type, from_turn: from_turn, to_turn: war_turn || to_turn }
  end

  def war_declaration_turns(civ, other)
    @log.of_type("war_declared").filter_map { |e|
      attackers, defenders = e.payload.values_at("attacker_civs", "defender_civs").map { |c| Array(c) }
      opposed = (attackers.include?(civ) && defenders.include?(other)) ||
                (attackers.include?(other) && defenders.include?(civ))
      e.turn if opposed
    }
  end

  def events_for(open_type, close_type, civ, other)
    (matching_turns(open_type, civ, other).map { |turn| [ turn, :open ] } +
     matching_turns(close_type, civ, other).map { |turn| [ turn, :close ] }).uniq.sort_by(&:first)
  end

  def matching_turns(type, civ, other)
    @log.of_type(type).select { |e| pair?(e.payload, civ, other) }.map(&:turn).uniq
  end

  def pair?(payload, civ, other)
    pair = payload.key?("civs") ? Array(payload["civs"]) : [ payload["civ"], payload["other_civ"] ]
    pair.sort == [ civ, other ].sort
  end
end
