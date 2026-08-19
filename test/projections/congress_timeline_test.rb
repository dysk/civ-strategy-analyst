require "test_helper"

class CongressTimelineTest < ActiveSupport::TestCase
  setup do
    @game = Game.create!(name: "Congress Test Game")
    @seq = 0
  end

  test "host_over_time reports the host at each congress_snapshot" do
    congress_snapshot(10, host: "Rome", delegates: [], votes_needed: 12)
    congress_snapshot(40, host: "Greece", delegates: [], votes_needed: 12)

    assert_equal(
      [ { turn: 10, host: "Rome" }, { turn: 40, host: "Greece" } ],
      CongressTimeline.new(@game).host_over_time
    )
  end

  test "keeps one host entry per turn when a turn was snapshotted twice" do
    congress_snapshot(10, host: "Rome", delegates: [], votes_needed: 12)
    congress_snapshot(10, host: "Greece", delegates: [], votes_needed: 12)

    assert_equal [ { turn: 10, host: "Greece" } ], CongressTimeline.new(@game).host_over_time
  end

  test "delegate_votes returns turn/votes pairs for a civ, like a MetricSeries value series" do
    congress_snapshot(10, host: "Rome",
      delegates: [ { "civ" => "Rome", "votes" => 3, "core_votes" => 2 }, { "civ" => "Greece", "votes" => 2, "core_votes" => 2 } ],
      votes_needed: 12)
    congress_snapshot(40, host: "Rome",
      delegates: [ { "civ" => "Rome", "votes" => 5, "core_votes" => 2 }, { "civ" => "Greece", "votes" => 2, "core_votes" => 2 } ],
      votes_needed: 12)

    assert_equal [ [ 10, 3 ], [ 40, 5 ] ], CongressTimeline.new(@game).delegate_votes("Rome")
  end

  test "votes_needed reports the most recently known threshold" do
    congress_snapshot(10, host: "Rome", delegates: [], votes_needed: 12)
    congress_snapshot(40, host: "Rome", delegates: [], votes_needed: 14)

    assert_equal 14, CongressTimeline.new(@game).votes_needed
  end

  test "resolutions pairs a proposal with its passed outcome, by resolution name and turn order" do
    resolution_event("resolution_proposed", 10, resolution: "World's Fair", proposer: "Rome", repeal: false)
    resolution_event("resolution_passed", 15, resolution: "World's Fair")

    assert_equal(
      [ { resolution: "World's Fair", proposer: "Rome", repeal: false,
          proposed_turn: 10, outcome: :passed, outcome_turn: 15, repealed_turn: nil } ],
      CongressTimeline.new(@game).resolutions
    )
  end

  test "resolutions pairs a proposal with its failed outcome" do
    resolution_event("resolution_proposed", 10, resolution: "Embargo City-State", proposer: "Greece", repeal: false)
    resolution_event("resolution_failed", 15, resolution: "Embargo City-State")

    outcome = CongressTimeline.new(@game).resolutions.first
    assert_equal :failed, outcome[:outcome]
    assert_equal 15, outcome[:outcome_turn]
    assert_nil outcome[:repealed_turn]
  end

  test "resolutions attaches a later repeal to the passed resolution it repeals" do
    resolution_event("resolution_proposed", 10, resolution: "Cultural Heritage Sites", proposer: "Rome", repeal: false)
    resolution_event("resolution_passed", 15, resolution: "Cultural Heritage Sites")
    resolution_event("resolution_repealed", 60, resolution: "Cultural Heritage Sites")

    outcome = CongressTimeline.new(@game).resolutions.first
    assert_equal :passed, outcome[:outcome]
    assert_equal 60, outcome[:repealed_turn]
  end

  test "resolutions leaves a passed repeal proposal without a repealed turn of its own" do
    resolution_event("resolution_proposed", 10, resolution: "Cultural Heritage Sites", proposer: "Rome", repeal: false)
    resolution_event("resolution_passed", 15, resolution: "Cultural Heritage Sites")
    resolution_event("resolution_proposed", 20, resolution: "Cultural Heritage Sites", proposer: "Greece", repeal: true)
    resolution_event("resolution_passed", 25, resolution: "Cultural Heritage Sites")
    resolution_event("resolution_repealed", 25, resolution: "Cultural Heritage Sites")

    outcomes = CongressTimeline.new(@game).resolutions.sort_by { |o| o[:proposed_turn] }

    assert_equal [ 25, nil ], outcomes.map { |o| o[:repealed_turn] }
  end

  test "resolutions attaches a repeal to the enactment it ended, not to the next passed proposal" do
    resolution_event("resolution_proposed", 10, resolution: "Cultural Heritage Sites", proposer: "Rome", repeal: false)
    resolution_event("resolution_passed", 15, resolution: "Cultural Heritage Sites")
    resolution_event("resolution_proposed", 20, resolution: "Cultural Heritage Sites", proposer: "Greece", repeal: true)
    resolution_event("resolution_passed", 25, resolution: "Cultural Heritage Sites")
    resolution_event("resolution_repealed", 25, resolution: "Cultural Heritage Sites")
    resolution_event("resolution_proposed", 30, resolution: "Cultural Heritage Sites", proposer: "Rome", repeal: false)
    resolution_event("resolution_passed", 35, resolution: "Cultural Heritage Sites")
    resolution_event("resolution_repealed", 45, resolution: "Cultural Heritage Sites")

    outcomes = CongressTimeline.new(@game).resolutions.sort_by { |o| o[:proposed_turn] }

    assert_equal [ 25, nil, 45 ], outcomes.map { |o| o[:repealed_turn] }
  end

  test "resolutions pairs repeat proposals of the same resolution name in turn order" do
    resolution_event("resolution_proposed", 10, resolution: "World's Fair", proposer: "Rome", repeal: false)
    resolution_event("resolution_failed", 15, resolution: "World's Fair")
    resolution_event("resolution_proposed", 50, resolution: "World's Fair", proposer: "Greece", repeal: false)
    resolution_event("resolution_passed", 55, resolution: "World's Fair")

    outcomes = CongressTimeline.new(@game).resolutions.sort_by { |o| o[:proposed_turn] }

    assert_equal [ "Rome", "Greece" ], outcomes.map { |o| o[:proposer] }
    assert_equal %i[failed passed], outcomes.map { |o| o[:outcome] }
  end

  test "resolutions leaves outcome nil for a proposal with no result yet" do
    resolution_event("resolution_proposed", 10, resolution: "World's Fair", proposer: "Rome", repeal: false)

    outcome = CongressTimeline.new(@game).resolutions.first
    assert_nil outcome[:outcome]
    assert_nil outcome[:outcome_turn]
  end

  private

  def congress_snapshot(turn, host:, delegates:, votes_needed:)
    @seq += 1
    payload = { "event" => "congress_snapshot", "turn" => turn, "host" => host,
                "delegates" => delegates, "votes_needed_for_diplo_victory" => votes_needed }
    @game.game_events.create!(seq: @seq, session_index: 0, turn: turn, event_type: "congress_snapshot", civ: nil, payload: payload)
  end

  def resolution_event(event_type, turn, extra)
    @seq += 1
    payload = extra.stringify_keys.merge("event" => event_type, "turn" => turn)
    @game.game_events.create!(seq: @seq, session_index: 0, turn: turn, event_type: event_type, civ: nil, payload: payload)
  end
end
