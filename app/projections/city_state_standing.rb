# A city-state's standing with each civ, and who has held its alliance and
# when. `docs/reading-the-new-log.md` §5: the friend/ally split is already in
# `relations[].level`, so `series` carries it for free - only the alliance,
# being the one exclusive slot, needs its own span history.
class CityStateStanding
  extend Projection

  # Measured off eight Ljubljana rigs ten turns apart against a decay of
  # −1.25 - see docs/city-state-influence.md. Rigs are the only cause the
  # residual is ever credited with; the rest is named, not explained.
  RIG_GAIN = 45
  MERCHANT_CONFEDERACY = "POLICY_MERCHANT_CONFEDERACY"

  def initialize(game)
    @game = game
    @log = game.event_log
  end

  def applicable? = snapshots.any?

  # Sparse points for one city-state's standing with one civ. A turn can be
  # snapshotted more than once - a resumed session repeats it - and the
  # later snapshot is the state the turn ended in, the convention
  # InfluenceTimeline, CityCensus and CongressTimeline already share.
  def series(city_state, civ)
    snapshots_for(city_state).filter_map { |e| point(e, civ) }.index_by { |p| p[:turn] }.values
  end

  # Held alliance spans for civ, across every city-state, from
  # city_state_ally_changed. A span already open at the first snapshot has no
  # gaining event to date it, so from_turn falls back to that snapshot's turn,
  # flagged :observed rather than :event.
  def alliances(civ)
    ally_changes_by_city_state.flat_map { |city_state, changes| spans_for(city_state, civ, changes) }
  end

  # The influence a civ bought at a city-state, split into what the log
  # explains and what it does not. `unexplained` is the headline field and is
  # never labelled with a cause - it is where gold gifts, quests and
  # successful coups live, none of them logged.
  def attribution(city_state, civ)
    points = series(city_state, civ).sort_by { |p| p[:turn] }
    gain, decay = points.size >= 2 ? [ gain_across(points), decay_across(points) ] : [ 0, 0 ]
    rigs = rig_count(city_state, civ)
    explained = rigs * RIG_GAIN

    { gain: gain, decay: decay, rigs: rigs, explained: explained, unexplained: (gain - decay) - explained,
      cs_routes: cs_routes(city_state, civ), merchant_confederacy: merchant_confederacy?(civ) }
  end

  def traits
    Array(session_started&.payload&.[]("city_states")).map { |cs|
      { city_state: cs["civ"], trait: cs["trait"], personality: cs["personality"], unique_unit: cs["unique_unit"] }
    }
  end

  private

  # A relation can be logged with no influence value at all - real in
  # india-diplo.jsonl, alongside per_turn and protected. Gain falls back to
  # the nearest snapshots that do carry it, rather than crash on a boundary
  # point that happens to be the one missing it.
  def gain_across(points)
    known = points.select { |p| p[:influence] }
    return 0 if known.size < 2

    known.last[:influence] - known.first[:influence]
  end

  # A relation can be logged with no per_turn at all - real in
  # india-diplo.jsonl. That stretch's decay is simply unmeasured, so it
  # counts as zero rather than crashing; the gap still surfaces, in
  # `unexplained`, same as every other unlogged cause.
  def decay_across(points) = points.each_cons(2).sum { |a, b| (a[:per_turn] || 0) * (b[:turn] - a[:turn]) }

  def rig_count(city_state, civ)
    espionage.missions(civ).count { |m| m[:kind] == :election_rigging && m[:city_civ] == city_state }
  end

  def espionage = @espionage ||= Espionage.for(@game)

  def cs_routes(city_state, civ)
    @log.of_type("trade_route_established").count { |e| e.civ == civ && e.payload["to_civ"] == city_state }
  end

  def merchant_confederacy?(civ)
    @log.of_type("policy_adopted").any? { |e| e.civ == civ && e.payload["policy"] == MERCHANT_CONFEDERACY }
  end

  def spans_for(city_state, civ, changes)
    changes = changes.sort_by(&:turn)
    spans = []
    open_span = observed_start(city_state, civ, changes)

    changes.each do |e|
      if e.payload["new_ally"] == civ
        open_span = { city_state: city_state, from_turn: e.turn, origin: :event }
      elsif e.payload["old_ally"] == civ && open_span
        spans << open_span.merge(until_turn: e.turn)
        open_span = nil
      end
    end

    spans << open_span.merge(until_turn: nil) if open_span
    spans
  end

  # civ already held the alliance before any change event touched this
  # city-state - the only evidence is the earliest snapshot's `ally` field.
  def observed_start(city_state, civ, changes)
    first = snapshots_for(city_state).first
    return unless first && first.payload["ally"] == civ
    return if changes.any? { |e| e.turn <= first.turn }

    { city_state: city_state, from_turn: first.turn, origin: :observed }
  end

  def ally_changes_by_city_state
    @log.of_type("city_state_ally_changed").group_by { |e| e.payload["city_state"] }
  end

  def point(snapshot, civ)
    relation = Array(snapshot.payload["relations"]).find { |r| r["civ"] == civ }
    return unless relation

    { turn: snapshot.turn, influence: relation["influence"], level: relation["level"],
      per_turn: relation["per_turn"], protected: relation.fetch("protected", false) }
  end

  def session_started = @log.of_type("session_started").first

  def snapshots_for(city_state) = snapshots_by_city_state.fetch(city_state, [])
  def snapshots_by_city_state = @snapshots_by_city_state ||= snapshots.group_by { |e| e.payload["city_state"] }
  def snapshots = @log.of_type("city_state_snapshot")
end
