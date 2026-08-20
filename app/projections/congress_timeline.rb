# World Congress state: host, delegate votes and each resolution's life
# from proposal to outcome to (maybe) repeal. The logger never emits a
# resolution ID to the JSONL - only Type/turn survive the trip - so a
# proposal is paired with its outcome by resolution name and turn order,
# the same FIFO convention KeyMomentDetector#war_declarations already
# uses to pair war_declared with peace_made by team.
class CongressTimeline
  # `undetermined` is a concluded vote whose result the logger could not
  # read - a resolution with only one-time effects leaves no trace in the
  # game state to read it from. It is not the same as a nil outcome, which
  # is a vote still to come.
  OUTCOMES = {
    "resolution_passed" => :passed,
    "resolution_failed" => :failed,
    "resolution_undetermined" => :undetermined
  }.freeze

  def initialize(game)
    @events = game.game_events.order(:seq).to_a
  end

  # A turn can be snapshotted more than once - a resumed session repeats
  # it - and the later snapshot is the state the turn ended in.
  def host_over_time
    congress_snapshots.map { |e| { turn: e.turn, host: e.payload["host"] } }.index_by { |entry| entry[:turn] }.values
  end

  def delegate_votes(civ)
    congress_snapshots.filter_map { |e| delegate_pair(e, civ) }.index_by(&:first).values
  end

  def votes_needed
    congress_snapshots.last&.payload&.[]("votes_needed_for_diplo_victory")
  end

  def resolutions
    proposals_by_name = of_type("resolution_proposed").group_by { |e| e.payload["resolution"] }

    proposals_by_name.flat_map { |name, proposals| resolutions_for(name, proposals) }
  end

  private

  # A repeal ends the enactment that was in force, so `repealed_turn`
  # belongs to the proposal that enacted the resolution - never to a repeal
  # proposal, which has nothing of its own left to repeal.
  def resolutions_for(name, proposals)
    outcomes = combined_outcomes(name)
    repeals = of_type("resolution_repealed").select { |e| e.payload["resolution"] == name }
    enactments_seen = 0

    proposals.each_with_index.map do |proposal, index|
      outcome_event, outcome_type = outcomes[index]
      repeal_event = nil

      if outcome_type == :passed && !proposal.payload["repeal"]
        repeal_event = repeals[enactments_seen]
        enactments_seen += 1
      end

      { resolution: name, proposer: proposal.payload["proposer"], repeal: proposal.payload["repeal"],
        proposed_turn: proposal.turn, outcome: outcome_type, outcome_turn: outcome_event&.turn,
        repealed_turn: repeal_event&.turn }
    end
  end

  def combined_outcomes(name)
    OUTCOMES.flat_map { |event_type, outcome|
      of_type(event_type).select { |e| e.payload["resolution"] == name }.map { |e| [ e, outcome ] }
    }.sort_by { |e, _outcome| e.turn }
  end

  def delegate_pair(snapshot, civ)
    delegate = Array(snapshot.payload["delegates"]).find { |d| d["civ"] == civ }
    return unless delegate

    [ snapshot.turn, delegate["votes"] ]
  end

  def congress_snapshots
    of_type("congress_snapshot")
  end

  def of_type(event_type)
    @events.select { |e| e.event_type == event_type }
  end
end
