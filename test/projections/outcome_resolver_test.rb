require "test_helper"

class OutcomeResolverTest < ActiveSupport::TestCase
  setup do
    @game = Game.create!(name: "Outcome Test Game", max_turns: 100)
    @seq = 0
  end

  test "uses the declared winner and victory_type when given, regardless of game state" do
    snapshot("Rome", 50, score: 100)
    snapshot("Greece", 50, score: 200)

    outcome = OutcomeResolver.new(@game, winner_civ: "Rome", victory_type: "domination").call

    assert_equal(
      { winner_civ: "Rome", victory_type: "domination", in_progress: false, source: :declared },
      outcome
    )
  end

  test "infers the score leader and marks the game in progress when turns remain" do
    snapshot("Rome", 50, score: 300)
    snapshot("Greece", 50, score: 200)

    outcome = OutcomeResolver.new(@game).call

    assert_equal(
      { winner_civ: "Rome", victory_type: nil, in_progress: true, source: :inferred },
      outcome
    )
  end

  test "infers the score leader and marks the game not in progress once max_turns is reached" do
    snapshot("Rome", 100, score: 300)
    snapshot("Greece", 100, score: 200)

    outcome = OutcomeResolver.new(@game).call

    assert_equal(
      { winner_civ: "Rome", victory_type: nil, in_progress: false, source: :inferred },
      outcome
    )
  end

  test "infers cultural victory when a civ is influential on all but one living major at the final snapshot" do
    snapshot("Rome", 100, score: 100, civs_influential_on: 2)
    snapshot("Greece", 100, score: 300, civs_influential_on: 0)
    snapshot("Egypt", 100, score: 250, civs_influential_on: 0)

    outcome = OutcomeResolver.new(@game).call

    assert_equal(
      { winner_civ: "Rome", victory_type: "cultural", in_progress: false, source: :inferred },
      outcome
    )
  end

  test "falls back to the score leader when no civ nears a cultural victory" do
    snapshot("Rome", 50, score: 300, civs_influential_on: 1)
    snapshot("Greece", 50, score: 200, civs_influential_on: 0)
    snapshot("Egypt", 50, score: 100, civs_influential_on: 0)

    outcome = OutcomeResolver.new(@game).call

    assert_equal(
      { winner_civ: "Rome", victory_type: nil, in_progress: true, source: :inferred },
      outcome
    )
  end

  test "does not infer a cultural victory with only one living major - that's domination, not culture" do
    snapshot("Rome", 100, score: 500, civs_influential_on: 0)

    outcome = OutcomeResolver.new(@game).call

    assert_equal(
      { winner_civ: "Rome", victory_type: nil, in_progress: false, source: :inferred },
      outcome
    )
  end

  test "infers diplomatic victory when a civ's delegate votes meet the threshold at the final Congress snapshot" do
    snapshot("Rome", 100, score: 100)
    snapshot("Greece", 100, score: 300)
    congress_snapshot(100, delegates: [ { "civ" => "Rome", "votes" => 14 }, { "civ" => "Greece", "votes" => 3 } ], votes_needed: 12)

    outcome = OutcomeResolver.new(@game).call

    assert_equal(
      { winner_civ: "Rome", victory_type: "diplomatic", in_progress: false, source: :inferred },
      outcome
    )
  end

  test "falls back to the score leader when no civ's delegate votes meet the threshold" do
    snapshot("Rome", 50, score: 300)
    snapshot("Greece", 50, score: 200)
    congress_snapshot(50, delegates: [ { "civ" => "Rome", "votes" => 5 }, { "civ" => "Greece", "votes" => 3 } ], votes_needed: 12)

    outcome = OutcomeResolver.new(@game).call

    assert_equal(
      { winner_civ: "Rome", victory_type: nil, in_progress: true, source: :inferred },
      outcome
    )
  end

  test "prefers diplomatic victory over a simultaneous cultural-victory reading" do
    snapshot("Rome", 100, score: 100, civs_influential_on: 2)
    snapshot("Greece", 100, score: 300, civs_influential_on: 0)
    snapshot("Egypt", 100, score: 250, civs_influential_on: 0)
    congress_snapshot(100, delegates: [ { "civ" => "Greece", "votes" => 14 } ], votes_needed: 12)

    outcome = OutcomeResolver.new(@game).call

    assert_equal(
      { winner_civ: "Greece", victory_type: "diplomatic", in_progress: false, source: :inferred },
      outcome
    )
  end

  test "infers domination victory when a civ's capitals cover the entire roster" do
    player("Rome")
    player("Greece")
    snapshot("Rome", 100, score: 100, capitals: %w[Rome Greece])
    snapshot("Greece", 80, score: 500, capitals: %w[Greece])

    outcome = OutcomeResolver.new(@game).call

    assert_equal(
      { winner_civ: "Rome", victory_type: "domination", in_progress: false, source: :inferred },
      outcome
    )
  end

  test "infers domination victory from a capture that completes it with no snapshot logged afterward" do
    player("Rome")
    player("Greece")
    snapshot("Rome", 100, score: 100, capitals: %w[Rome])
    snapshot("Greece", 100, score: 500, capitals: %w[Greece])
    city_captured(101, city: "Athens", old_owner: "Greece", new_owner: "Rome")

    outcome = OutcomeResolver.new(@game).call

    assert_equal(
      { winner_civ: "Rome", victory_type: "domination", in_progress: false, source: :inferred },
      outcome
    )
  end

  test "does not infer domination while any roster civ's original capital is still unaccounted for" do
    player("Rome")
    player("Greece")
    snapshot("Rome", 50, score: 500, capitals: %w[Rome])
    snapshot("Greece", 50, score: 200, capitals: %w[Greece])

    outcome = OutcomeResolver.new(@game).call

    assert_equal(
      { winner_civ: "Rome", victory_type: nil, in_progress: true, source: :inferred },
      outcome
    )
  end

  test "infers science victory when a civ's spaceship is fully assembled" do
    player("Rome")
    player("Greece")
    snapshot("Rome", 100, score: 100,
      spaceship: { "apollo" => 1, "booster" => 3, "cockpit" => 1, "stasis_chamber" => 1, "engine" => 1 })
    snapshot("Greece", 100, score: 500, spaceship: { "apollo" => 0, "booster" => 0, "cockpit" => 0, "stasis_chamber" => 0, "engine" => 0 })

    outcome = OutcomeResolver.new(@game).call

    assert_equal(
      { winner_civ: "Rome", victory_type: "science", in_progress: false, source: :inferred },
      outcome
    )
  end

  test "does not infer science victory while any spaceship part is short" do
    player("Rome")
    snapshot("Rome", 50, score: 500,
      spaceship: { "apollo" => 1, "booster" => 2, "cockpit" => 1, "stasis_chamber" => 1, "engine" => 1 })

    outcome = OutcomeResolver.new(@game).call

    assert_equal(
      { winner_civ: "Rome", victory_type: nil, in_progress: true, source: :inferred },
      outcome
    )
  end

  test "prefers domination over science, diplomatic and cultural readings" do
    player("Rome")
    player("Greece")
    snapshot("Rome", 100, score: 100, capitals: %w[Rome Greece],
      spaceship: { "apollo" => 1, "booster" => 3, "cockpit" => 1, "stasis_chamber" => 1, "engine" => 1 })
    snapshot("Greece", 80, score: 500, capitals: %w[Greece])
    congress_snapshot(100, delegates: [ { "civ" => "Rome", "votes" => 14 } ], votes_needed: 12)

    outcome = OutcomeResolver.new(@game).call

    assert_equal "domination", outcome[:victory_type]
    assert_equal "Rome", outcome[:winner_civ]
  end

  test "prefers science over diplomatic and cultural readings" do
    player("Rome")
    player("Greece")
    snapshot("Rome", 100, score: 100,
      spaceship: { "apollo" => 1, "booster" => 3, "cockpit" => 1, "stasis_chamber" => 1, "engine" => 1 })
    snapshot("Greece", 100, score: 300)
    congress_snapshot(100, delegates: [ { "civ" => "Rome", "votes" => 14 } ], votes_needed: 12)

    outcome = OutcomeResolver.new(@game).call

    assert_equal "science", outcome[:victory_type]
  end

  test "reports in progress with no leader when there are no snapshots yet" do
    outcome = OutcomeResolver.new(@game).call

    assert_equal(
      { winner_civ: nil, victory_type: nil, in_progress: true, source: :inferred },
      outcome
    )
  end

  # ImportGame reads the winner off the logger's game_ended record onto the
  # game itself. When it is there, it is read rather than inferred.
  test "reads the logged winner and victory type from a finished game" do
    finish(winner_civ: "India", winner_civs: %w[India], victory_type: "diplomatic")
    snapshot("India", 183, score: 100)
    snapshot("Rome", 183, score: 900)

    outcome = OutcomeResolver.new(@game).call

    assert_equal(
      { winner_civ: "India", victory_type: "diplomatic", in_progress: false, source: :logged },
      outcome
    )
  end

  # The logged outcome sits between the two existing sources: a hand-given
  # --winner still wins, so a user override is never silently discarded.
  test "a declared winner still overrides the logged outcome" do
    finish(winner_civ: "India", winner_civs: %w[India], victory_type: "diplomatic")

    outcome = OutcomeResolver.new(@game, winner_civ: "Rome", victory_type: "domination").call

    assert_equal(
      { winner_civ: "Rome", victory_type: "domination", in_progress: false, source: :declared },
      outcome
    )
  end

  # A passed scrap vote ends the game with no winner. Inferring the score
  # leader would invent one for a game nobody won.
  test "a scrapped game is over with no winner and no inference" do
    finish(winner_civ: nil, winner_civs: nil, victory_type: "scrapped")
    snapshot("Rome", 140, score: 900)
    snapshot("Greece", 140, score: 100)

    outcome = OutcomeResolver.new(@game).call

    assert_equal(
      { winner_civ: nil, victory_type: "scrapped", in_progress: false, source: :logged },
      outcome
    )
  end

  test "prefers the logged outcome over a contradicting inferred reading" do
    player("Rome")
    player("Greece")
    finish(winner_civ: "Greece", winner_civs: %w[Greece], victory_type: "diplomatic")
    snapshot("Rome", 100, score: 100, capitals: %w[Rome Greece])
    snapshot("Greece", 80, score: 500, capitals: %w[Greece])

    outcome = OutcomeResolver.new(@game).call

    assert_equal "diplomatic", outcome[:victory_type]
    assert_equal "Greece", outcome[:winner_civ]
    assert_equal :logged, outcome[:source]
  end

  private

  def finish(winner_civ:, victory_type:, winner_civs: nil)
    @game.update!(completed: true, winner_civ: winner_civ, winner_civs: winner_civs, victory_type: victory_type)
  end

  def player(civ)
    @game.players.create!(civ: civ, leader_name: civ, human: false, handicap: "PRINCE")
  end

  def congress_snapshot(turn, delegates:, votes_needed:)
    @seq += 1
    payload = { "event" => "congress_snapshot", "turn" => turn,
                "delegates" => delegates, "votes_needed_for_diplo_victory" => votes_needed }
    @game.game_events.create!(seq: @seq, session_index: 0, turn: turn, event_type: "congress_snapshot", civ: nil, payload: payload)
  end

  def city_captured(turn, city:, old_owner:, new_owner:, capital: true)
    @seq += 1
    payload = { "event" => "city_captured", "turn" => turn, "city" => city,
                "old_owner" => old_owner, "new_owner" => new_owner, "capital" => capital }
    @game.game_events.create!(seq: @seq, session_index: 0, turn: turn, event_type: "city_captured", civ: nil, payload: payload)
  end

  def snapshot(civ, turn, **metrics)
    @seq += 1
    payload = metrics.stringify_keys.merge("event" => "snapshot", "turn" => turn, "civ" => civ)
    @game.game_events.create!(
      seq: @seq, session_index: 0, turn: turn, event_type: "snapshot", civ: civ, payload: payload
    )
  end
end
