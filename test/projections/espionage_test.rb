require "test_helper"

class EspionageTest < ActiveSupport::TestCase
  setup do
    @game = Game.create!(name: "Espionage Test Game")
    @seq = 0
  end

  test "a run of sightings of one spy in one city is one tenure" do
    moved("India", 100, spy: "INDIA_7", agent: 7, city: "Kyoto", city_civ: "Japan", state: "travelling")
    surveillance("India", 104, spy: "INDIA_7", agent: 7, city: "Kyoto", city_civ: "Japan")
    mission("India", 110, spy: "INDIA_7", agent: 7, city: "Kyoto", city_civ: "Japan", state: "gathering_intel")

    assert_equal(
      [ { civ: "India", spy: "INDIA_7", agent: 7, city: "Kyoto", city_civ: "Japan",
          from_turn: 100, to_turn: 110, until_turn: 110, visible_from_turn: 104,
          visible_from_turn_bounded: false, states: %w[travelling gathering_intel],
          ended_by: :log_end } ],
      Espionage.new(@game).tenures("India")
    )
  end

  test "a sighting in another city ends the tenure and opens the next" do
    moved("India", 100, spy: "INDIA_7", city: "Kyoto", city_civ: "Japan", state: "travelling")
    mission("India", 110, spy: "INDIA_7", city: "Kyoto", city_civ: "Japan", state: "gathering_intel")
    moved("India", 120, spy: "INDIA_7", city: "Osaka", city_civ: "Japan", state: "travelling")

    assert_equal [ [ "Kyoto", 100, 110, :moved ], [ "Osaka", 120, 120, :log_end ] ],
      Espionage.new(@game).tenures("India").map { |t| t.values_at(:city, :from_turn, :to_turn, :ended_by) }
  end

  test "a killed spy's tenure ends where it died" do
    moved("India", 100, spy: "INDIA_7", agent: 7, city: "Kyoto", city_civ: "Japan", state: "travelling")
    killed("India", 112, spy: "INDIA_7", agent: 7, city: "Kyoto", city_civ: "Japan")

    assert_equal [ [ 112, :killed ] ],
      Espionage.new(@game).tenures("India").map { |t| t.values_at(:to_turn, :ended_by) }
  end

  test "a kill ends the run even when the same agent returns to the same city" do
    moved("India", 100, spy: "INDIA_7", agent: 7, city: "Kyoto", city_civ: "Japan", state: "travelling")
    killed("India", 112, spy: "INDIA_7", agent: 7, city: "Kyoto", city_civ: "Japan")
    moved("India", 120, spy: "INDIA_9", agent: 7, city: "Kyoto", city_civ: "Japan", state: "travelling")

    assert_equal [ [ 100, 112, :killed ], [ 120, 120, :log_end ] ],
      Espionage.new(@game).tenures("India").map { |t| t.values_at(:from_turn, :to_turn, :ended_by) }
  end

  test "a location-less event does not break a run" do
    moved("India", 100, spy: "INDIA_7", agent: 7, city: "Kyoto", city_civ: "Japan", state: "travelling")
    promoted("India", 105, spy: "INDIA_7", agent: 7)
    mission("India", 110, spy: "INDIA_7", agent: 7, city: "Kyoto", city_civ: "Japan", state: "gathering_intel")

    assert_equal 1, Espionage.new(@game).tenures("India").size
  end

  test "a spy re-announced after a reload does not open a second tenure" do
    created("India", 132, spy: "INDIA_7", agent: 7, city: "Delhi", city_civ: "India")
    surveillance("India", 136, spy: "INDIA_7", agent: 7, city: "Delhi", city_civ: "India")
    created("India", 150, spy: "INDIA_7", agent: 7, city: "Delhi", city_civ: "India")

    assert_equal [ [ 132, 150 ] ],
      Espionage.new(@game).tenures("India").map { |t| t.values_at(:from_turn, :to_turn) }
  end

  test "sightings are keyed on the agent, so a recycled spy name is two tenures" do
    moved("India", 100, spy: "INDIA_3", agent: 1, city: "Kyoto", city_civ: "Japan", state: "travelling")
    moved("India", 102, spy: "INDIA_3", agent: 5, city: "Osaka", city_civ: "Japan", state: "travelling")
    mission("India", 104, spy: "INDIA_3", agent: 1, city: "Kyoto", city_civ: "Japan", state: "gathering_intel")

    assert_equal 2, Espionage.new(@game).tenures("India").size
  end

  test "vision opens on the logged surveillance turn" do
    moved("India", 100, spy: "INDIA_7", agent: 7, city: "Kyoto", city_civ: "Japan", state: "travelling")
    surveillance("India", 106, spy: "INDIA_7", agent: 7, city: "Kyoto", city_civ: "Japan")

    assert_equal [ [ 106, false ] ],
      Espionage.new(@game).tenures("India").map { |t| t.values_at(:visible_from_turn, :visible_from_turn_bounded) }
  end

  test "without the event vision is computed as the posting plus four" do
    moved("India", 100, spy: "INDIA_7", agent: 7, city: "Kyoto", city_civ: "Japan", state: "travelling")
    mission("India", 110, spy: "INDIA_7", agent: 7, city: "Kyoto", city_civ: "Japan", state: "gathering_intel")

    assert_equal [ [ 104, false ] ],
      Espionage.new(@game).tenures("India").map { |t| t.values_at(:visible_from_turn, :visible_from_turn_bounded) }
  end

  test "a tourism lead over the target cuts the computed wait to two turns" do
    influence("India", 99, over: "Japan", level: "INFLUENCE_LEVEL_FAMILIAR")
    moved("India", 100, spy: "INDIA_7", agent: 7, city: "Kyoto", city_civ: "Japan", state: "travelling")
    mission("India", 110, spy: "INDIA_7", agent: 7, city: "Kyoto", city_civ: "Japan", state: "gathering_intel")

    assert_equal [ 102 ], Espionage.new(@game).tenures("India").map { |t| t[:visible_from_turn] }
  end

  test "an influence level below familiar leaves the wait at four turns" do
    influence("India", 99, over: "Japan", level: "INFLUENCE_LEVEL_EXOTIC")
    moved("India", 100, spy: "INDIA_7", agent: 7, city: "Kyoto", city_civ: "Japan", state: "travelling")

    assert_equal [ 104 ], Espionage.new(@game).tenures("India").map { |t| t[:visible_from_turn] }
  end

  test "a counter intelligence posting takes effect the turn after it is ordered" do
    moved("India", 152, spy: "INDIA_7", agent: 7, city: "Delhi", city_civ: "India", state: "counter_intel")

    assert_equal [ [ 153, false ] ],
      Espionage.new(@game).tenures("India").map { |t| t.values_at(:visible_from_turn, :visible_from_turn_bounded) }
  end

  test "a garrison announced a turn after the order is dated from the order" do
    moved("India", 170, spy: "INDIA_7", agent: 7, city: "Delhi", city_civ: "India", state: "travelling")
    moved("India", 171, spy: "INDIA_7", agent: 7, city: "Delhi", city_civ: "India", state: "counter_intel")

    assert_equal [ 171 ], Espionage.new(@game).tenures("India").map { |t| t[:visible_from_turn] }
  end

  test "a tenure with no posting is dated from its first proof of presence and marked bounded" do
    mission("India", 110, spy: "INDIA_7", agent: 7, city: "Kyoto", city_civ: "Japan", state: "gathering_intel")
    mission("India", 118, spy: "INDIA_7", agent: 7, city: "Kyoto", city_civ: "Japan", state: "gathering_intel")

    assert_equal [ [ 110, true ] ],
      Espionage.new(@game).tenures("India").map { |t| t.values_at(:visible_from_turn, :visible_from_turn_bounded) }
  end

  test "tenures are listed in posting order across civs" do
    moved("Japan", 90, spy: "JAPAN_1", agent: 1, city: "Delhi", city_civ: "India", state: "travelling")
    moved("India", 100, spy: "INDIA_7", agent: 7, city: "Kyoto", city_civ: "Japan", state: "travelling")

    assert_equal %w[Japan India], Espionage.new(@game).tenures.map { |t| t[:civ] }
  end

  test "tenures asked for one civ leaves the other civs out" do
    moved("Japan", 90, spy: "JAPAN_1", agent: 1, city: "Delhi", city_civ: "India", state: "travelling")
    moved("India", 100, spy: "INDIA_7", agent: 7, city: "Kyoto", city_civ: "Japan", state: "travelling")

    assert_equal %w[India], Espionage.new(@game).tenures("India").map { |t| t[:civ] }
  end

  test "applicable? is false when the log carries no spy record" do
    influence("India", 99, over: "Japan", level: "INFLUENCE_LEVEL_EXOTIC")

    assert_not Espionage.new(@game).applicable?
  end

  test "applicable? is true once any spy record is present" do
    created("India", 132, spy: "INDIA_7", agent: 7, city: "Delhi", city_civ: "India")

    assert Espionage.new(@game).applicable?
  end

  test "a spy thrown out of a captured city holds the city until the eviction" do
    moved("England", 100, spy: "ENGLAND_1", agent: 1, city: "London", city_civ: "England", state: "travelling")
    surveillance("England", 104, spy: "ENGLAND_1", agent: 1, city: "London", city_civ: "England")
    evicted("England", 130, spy: "ENGLAND_1", agent: 1, city: "London", city_civ: "England")

    assert_equal [ [ 130, 130, :evicted ] ],
      Espionage.new(@game).tenures("England").map { |t| t.values_at(:to_turn, :until_turn, :ended_by) }
  end

  test "an eviction ends the run even when the spy is sent back to the same city" do
    moved("England", 100, spy: "ENGLAND_1", agent: 1, city: "London", city_civ: "England", state: "travelling")
    evicted("England", 130, spy: "ENGLAND_1", agent: 1, city: "London", city_civ: "England")
    moved("England", 140, spy: "ENGLAND_1", agent: 1, city: "London", city_civ: "France", state: "travelling")

    assert_equal 2, Espionage.new(@game).tenures("England").size
  end

  test "a city changing hands between two sightings ends the run" do
    moved("England", 100, spy: "ENGLAND_1", agent: 1, city: "London", city_civ: "England", state: "travelling")
    mission("England", 140, spy: "ENGLAND_1", agent: 1, city: "London", city_civ: "France", state: "gathering_intel")

    assert_equal [ "England", "France" ], Espionage.new(@game).tenures("England").map { |t| t[:city_civ] }
  end

  test "a kill the logger could not locate still closes the tenure it falls in" do
    moved("Iroquois", 95, spy: "IROQUOIS_3", city: "Delhi", city_civ: "India", state: "travelling")
    mission("Iroquois", 99, spy: "IROQUOIS_3", city: "Delhi", city_civ: "India", state: "gathering_intel")
    killed("Iroquois", 109, spy: "IROQUOIS_3")
    event("snapshot", "India", 150, { "event" => "snapshot", "turn" => 150, "civ" => "India" })

    assert_equal [ [ 99, 109, :killed ] ],
      Espionage.new(@game).tenures("Iroquois").map { |t| t.values_at(:to_turn, :until_turn, :ended_by) }
  end

  test "a tenure the log never closes is held to the last turn it logged" do
    moved("India", 100, spy: "INDIA_7", agent: 7, city: "Kyoto", city_civ: "Japan", state: "travelling")
    surveillance("India", 104, spy: "INDIA_7", agent: 7, city: "Kyoto", city_civ: "Japan")
    event("snapshot", "India", 183, { "event" => "snapshot", "turn" => 183, "civ" => "India" })

    assert_equal [ [ 104, 183 ] ],
      Espionage.new(@game).tenures("India").map { |t| t.values_at(:to_turn, :until_turn) }
  end

  test "a tenure the spy moved out of is held to the turn it was sent away" do
    moved("India", 100, spy: "INDIA_7", agent: 7, city: "Kyoto", city_civ: "Japan", state: "travelling")
    moved("India", 120, spy: "INDIA_7", agent: 7, city: "Osaka", city_civ: "Japan", state: "travelling")

    assert_equal [ 120 ], Espionage.new(@game).tenures("India").first.values_at(:until_turn)
  end

  test "a killed spy's tenure ends the turn it died" do
    moved("India", 100, spy: "INDIA_7", agent: 7, city: "Kyoto", city_civ: "Japan", state: "travelling")
    killed("India", 112, spy: "INDIA_7", agent: 7, city: "Kyoto", city_civ: "Japan")

    assert_equal [ 112 ], Espionage.new(@game).tenures("India").map { |t| t[:until_turn] }
  end

  test "a completed mission against a city-state is an election rigging" do
    moved("Arabia", 140, spy: "ARABIA_0", agent: 0, city: "Valletta", city_civ: "Valletta", state: "travelling")
    mission("Arabia", 151, spy: "ARABIA_0", agent: 0, city: "Valletta", city_civ: "Valletta", state: "rigging_election")

    assert_equal [ :election_rigging ], Espionage.new(@game).missions("Arabia").map { |m| m[:kind] }
  end

  test "a completed mission in another major's city is a tech theft" do
    moved("England", 100, spy: "ENGLAND_1", agent: 1, city: "Delhi", city_civ: "India", state: "travelling")
    mission("England", 110, spy: "ENGLAND_1", agent: 1, city: "Delhi", city_civ: "India", state: "gathering_intel")

    assert_equal [ :tech_theft ], Espionage.new(@game).missions("England").map { |m| m[:kind] }
  end

  test "a completion soon after the posting is the surveillance transition, not a mission" do
    moved("England", 100, spy: "ENGLAND_1", city: "Delhi", city_civ: "India", state: "travelling")
    mission("England", 104, spy: "ENGLAND_1", city: "Delhi", city_civ: "India", state: "gathering_intel")

    assert_empty Espionage.new(@game).missions("England")
  end

  test "a completion outside the transition window survives the filter" do
    moved("England", 100, spy: "ENGLAND_1", city: "Delhi", city_civ: "India", state: "travelling")
    mission("England", 110, spy: "ENGLAND_1", city: "Delhi", city_civ: "India", state: "gathering_intel")

    assert_equal [ true ], Espionage.new(@game).missions("England").map { |m| m[:anchored] }
  end

  test "a creation the logger could not place still anchors a completion" do
    created("India", 94, spy: "INDIA_7")
    mission("India", 98, spy: "INDIA_7", city: "Ljubljana", city_civ: "Ljubljana", state: "rigging_election")

    assert_empty Espionage.new(@game).missions("India")
  end

  test "a posting to somewhere else does not anchor a completion back where the spy came from" do
    moved("England", 100, spy: "ENGLAND_1", city: "Delhi", city_civ: "India", state: "travelling")
    moved("England", 110, spy: "ENGLAND_1", city: "Lhasa", city_civ: "Tibet", state: "travelling")
    mission("England", 114, spy: "ENGLAND_1", city: "Delhi", city_civ: "India", state: "gathering_intel")

    assert_equal [ false ], Espionage.new(@game).missions("England").map { |m| m[:anchored] }
  end

  test "a completion with no posting behind it is carried as unanchored" do
    mission("England", 110, spy: "ENGLAND_1", city: "Delhi", city_civ: "India", state: "gathering_intel")

    assert_equal [ false ], Espionage.new(@game).missions("England").map { |m| m[:anchored] }
  end

  test "a log that reports surveillance is counted straight, transition window and all" do
    surveillance("India", 98, spy: "INDIA_7", agent: 7, city: "Kyoto", city_civ: "Japan")
    moved("England", 100, spy: "ENGLAND_1", agent: 1, city: "Delhi", city_civ: "India", state: "travelling")
    mission("England", 104, spy: "ENGLAND_1", agent: 1, city: "Delhi", city_civ: "India", state: "gathering_intel")

    assert_equal [ true ], Espionage.new(@game).missions("England").map { |m| m[:anchored] }
  end

  test "missions asked for one civ leaves the other civs out" do
    mission("England", 110, spy: "ENGLAND_1", city: "Delhi", city_civ: "India", state: "gathering_intel")
    mission("Tibet", 112, spy: "TIBET_1", city: "Delhi", city_civ: "India", state: "gathering_intel")

    assert_equal %w[England], Espionage.new(@game).missions("England").map { |m| m[:civ] }
  end

  test "a loss reads the city it died in off the kill record" do
    moved("Arabia", 140, spy: "ARABIA_0", agent: 0, city: "Valletta", city_civ: "Valletta", state: "travelling")
    killed("Arabia", 181, spy: "ARABIA_0", agent: 0, city: "Valletta", city_civ: "Valletta")

    assert_equal [ { civ: "Arabia", spy: "ARABIA_0", agent: 0, turn: 181, city: "Valletta",
                     city_civ: "Valletta", city_inferred: false, turns_since_last_seen: 0 } ],
      Espionage.new(@game).losses("Arabia")
  end

  test "a loss with no city on the record falls back to the last sighting and says how stale it is" do
    moved("England", 100, spy: "ENGLAND_1", city: "Delhi", city_civ: "India", state: "travelling")
    killed("England", 120, spy: "ENGLAND_1")

    assert_equal [ [ "Delhi", true, 20 ] ],
      Espionage.new(@game).losses("England").map { |l| l.values_at(:city, :city_inferred, :turns_since_last_seen) }
  end

  test "a loss of a spy that was never located carries no city" do
    created("England", 90, spy: "ENGLAND_1")
    killed("England", 120, spy: "ENGLAND_1")

    assert_equal [ [ nil, nil ] ],
      Espionage.new(@game).losses("England").map { |l| l.values_at(:city, :turns_since_last_seen) }
  end

  test "capacity counts what a civ spent and what it lost" do
    created("England", 90, spy: "ENGLAND_1", agent: 1)
    created("England", 94, spy: "ENGLAND_2", agent: 2)
    promoted("England", 100, spy: "ENGLAND_1", agent: 1)
    killed("England", 120, spy: "ENGLAND_1", agent: 1)
    revived("England", 126, spy: "ENGLAND_7", agent: 1)

    assert_equal({ created: 2, revived: 1, killed: 1, promoted: 1, never_located: 2 },
                 Espionage.new(@game).capacity("England"))
  end

  test "capacity counts a spy that reached a city as located" do
    created("England", 90, spy: "ENGLAND_1", agent: 1)
    moved("England", 100, spy: "ENGLAND_1", agent: 1, city: "Delhi", city_civ: "India", state: "travelling")

    assert_equal 0, Espionage.new(@game).capacity("England")[:never_located]
  end

  test "capacity isolates one civ from another" do
    created("England", 90, spy: "ENGLAND_1", agent: 1)
    created("Tibet", 90, spy: "TIBET_1", agent: 1)

    assert_equal 1, Espionage.new(@game).capacity("England")[:created]
  end

  test "a spy posted to counter-intelligence in its own city is a garrison" do
    moved("Mysore", 151, spy: "MUGHAL_0", agent: 0, city: "Mysuru", city_civ: "Mysore", state: "travelling")
    moved("Mysore", 152, spy: "MUGHAL_0", agent: 0, city: "Mysuru", city_civ: "Mysore", state: "counter_intel")

    assert_equal(
      [ { civ: "Mysore", city: "Mysuru", spy: "MUGHAL_0", agent: 0,
          from_turn: 151, to_turn: 152, until_turn: 152, kills: 0,
          inferred: false, confidence: nil } ],
      Espionage.new(@game).counterspies("Mysore")
    )
  end

  test "a garrison first seen at a reload seam is read like any other" do
    created("Mysore", 151, spy: "MUGHAL_0", agent: 0, city: "Mysuru", city_civ: "Mysore",
            state: "counter_intel")

    assert_equal [ [ "Mysuru", false ] ],
      Espionage.new(@game).counterspies("Mysore").map { |g| g.values_at(:city, :inferred) }
  end

  test "a garrison ends when the spy is ordered to another city" do
    moved("Sioux", 170, spy: "IROQUOIS_5", city: "Isanyathi", city_civ: "Sioux", state: "travelling")
    moved("Sioux", 171, spy: "IROQUOIS_5", city: "Isanyathi", city_civ: "Sioux", state: "counter_intel")
    moved("Sioux", 172, spy: "IROQUOIS_5", city: "Ihankthunwanna", city_civ: "Sioux", state: "travelling")
    moved("Sioux", 177, spy: "IROQUOIS_5", city: "Ihankthunwanna", city_civ: "Sioux", state: "counter_intel")

    assert_equal [ [ "Isanyathi", 170, 171, 172 ], [ "Ihankthunwanna", 172, 177, 177 ] ],
      Espionage.new(@game).counterspies("Sioux").map { |g| g.values_at(:city, :from_turn, :to_turn, :until_turn) }
  end

  test "a spy ordered home is no garrison until the state says it arrived" do
    moved("Sioux", 178, spy: "IROQUOIS_5", city: "Isanyathi", city_civ: "Sioux", state: "travelling")
    moved("Sioux", 179, spy: "IROQUOIS_5", city: "Ihankthunwanna", city_civ: "Sioux", state: "travelling")

    assert_empty Espionage.new(@game).counterspies("Sioux")
  end

  test "a garrison counts the spies that died in its city while it stood" do
    moved("India", 100, spy: "INDIA_7", city: "Delhi", city_civ: "India", state: "counter_intel")
    killed("England", 109, spy: "ENGLAND_5", city: "Delhi", city_civ: "India")
    killed("Tibet", 120, spy: "CHINA_3", city: "Delhi", city_civ: "India")

    assert_equal 2, Espionage.new(@game).counterspies("India").first[:kills]
  end

  test "a death before the garrison arrived is not its kill" do
    killed("England", 90, spy: "ENGLAND_5", city: "Delhi", city_civ: "India")
    moved("India", 100, spy: "INDIA_7", city: "Delhi", city_civ: "India", state: "counter_intel")
    killed("Tibet", 120, spy: "CHINA_3", city: "Delhi", city_civ: "India")

    assert_equal 1, Espionage.new(@game).counterspies("India").first[:kills]
  end

  test "a civ whose garrison the log records is never inferred at" do
    created("India", 94, spy: "INDIA_9", agent: 9)
    moved("India", 100, spy: "INDIA_7", agent: 7, city: "Delhi", city_civ: "India", state: "counter_intel")
    killed("England", 109, spy: "ENGLAND_5", city: "Delhi", city_civ: "India")

    assert_equal [ false ], Espionage.new(@game).counterspies("India").map { |g| g[:inferred] }
  end

  test "a never-located spy alone is a garrison nobody can place" do
    created("Netherlands", 183, spy: "NETHERLANDS_1", agent: 1)

    assert_equal(
      [ { civ: "Netherlands", city: nil, spy: "NETHERLANDS_1", agent: 1,
          from_turn: 183, to_turn: 183, until_turn: 183, kills: 0,
          inferred: true, confidence: 1 } ],
      Espionage.new(@game).counterspies("Netherlands")
    )
  end

  test "spies dying in a civ's cities locate a garrison the log never mentions" do
    moved("England", 100, spy: "ENGLAND_5", city: "Delhi", city_civ: "India", state: "travelling")
    killed("England", 109, spy: "ENGLAND_5")
    moved("Tibet", 115, spy: "CHINA_3", city: "Delhi", city_civ: "India", state: "travelling")
    killed("Tibet", 120, spy: "CHINA_3")

    assert_equal(
      [ { civ: "India", city: "Delhi", spy: nil, agent: nil,
          from_turn: 109, to_turn: 120, until_turn: 120, kills: 2,
          inferred: true, confidence: 1 } ],
      Espionage.new(@game).counterspies("India")
    )
  end

  test "a never-located spy and deaths at home agree to confidence two" do
    created("India", 94, spy: "INDIA_7", agent: 7)
    moved("England", 100, spy: "ENGLAND_5", city: "Delhi", city_civ: "India", state: "travelling")
    killed("England", 109, spy: "ENGLAND_5")

    assert_equal [ [ "Delhi", "INDIA_7", 94, 109, 2 ] ],
      Espionage.new(@game).counterspies("India")
        .map { |g| g.values_at(:city, :spy, :from_turn, :to_turn, :confidence) }
  end

  test "a promotion on the turn of a death at home is the third signal" do
    created("India", 94, spy: "INDIA_7", agent: 7)
    promoted("India", 108, spy: "INDIA_7", agent: 7)
    promoted("India", 109, spy: "INDIA_7", agent: 7)
    moved("England", 100, spy: "ENGLAND_5", city: "Delhi", city_civ: "India", state: "travelling")
    killed("England", 109, spy: "ENGLAND_5")

    assert_equal 3, Espionage.new(@game).counterspies("India").first[:confidence]
  end

  test "a promotion on a turn nothing died at home is no signal" do
    created("India", 94, spy: "INDIA_7", agent: 7)
    promoted("India", 108, spy: "INDIA_7", agent: 7)
    moved("England", 100, spy: "ENGLAND_5", city: "Delhi", city_civ: "India", state: "travelling")
    killed("England", 109, spy: "ENGLAND_5")

    assert_equal 2, Espionage.new(@game).counterspies("India").first[:confidence]
  end

  test "the city a garrison is placed in is where most of the deaths were" do
    moved("England", 100, spy: "ENGLAND_5", city: "Delhi", city_civ: "India", state: "travelling")
    killed("England", 109, spy: "ENGLAND_5")
    moved("Tibet", 112, spy: "CHINA_3", city: "Delhi", city_civ: "India", state: "travelling")
    killed("Tibet", 120, spy: "CHINA_3")
    moved("Tibet", 130, spy: "CHINA_5", city: "Mumbai", city_civ: "India", state: "travelling")
    killed("Tibet", 140, spy: "CHINA_5")

    assert_equal [ [ "Delhi", 2 ] ],
      Espionage.new(@game).counterspies("India").map { |g| g.values_at(:city, :kills) }
  end

  test "a spy dying at a city-state is a coup, not a garrison" do
    city_state("Valletta", 170)
    moved("Arabia", 177, spy: "ARABIA_0", city: "Valletta", city_civ: "Valletta", state: "travelling")
    killed("Arabia", 181, spy: "ARABIA_0")

    assert_empty Espionage.new(@game).counterspies("Valletta")
  end

  test "a garrison inferred from a named spy ends when that spy dies" do
    created("India", 94, spy: "INDIA_7", agent: 7)
    killed("India", 150, spy: "INDIA_7", agent: 7)
    moved("England", 100, spy: "ENGLAND_5", city: "Delhi", city_civ: "India", state: "travelling")
    killed("England", 109, spy: "ENGLAND_5")

    assert_equal [ [ 94, 109, 150 ] ],
      Espionage.new(@game).counterspies("India")
        .map { |g| g.values_at(:from_turn, :to_turn, :until_turn) }
  end

  test "counterspies isolates one civ from another" do
    created("India", 94, spy: "INDIA_7", agent: 7)
    created("England", 94, spy: "ENGLAND_1", agent: 1)

    assert_equal [ "INDIA_7" ], Espionage.new(@game).counterspies("India").map { |g| g[:spy] }
  end

  private

  def moved(civ, turn, **fields) = spy_event("spy_moved", civ, turn, **fields)
  def created(civ, turn, **fields) = spy_event("spy_created", civ, turn, **fields)
  def killed(civ, turn, **fields) = spy_event("spy_killed", civ, turn, **fields)
  def promoted(civ, turn, **fields) = spy_event("spy_promoted", civ, turn, **fields)
  def revived(civ, turn, **fields) = spy_event("spy_revived", civ, turn, **fields)
  def evicted(civ, turn, **fields) = spy_event("spy_evicted", civ, turn, **fields)
  def mission(civ, turn, **fields) = spy_event("spy_mission_completed", civ, turn, **fields)

  def city_state(name, turn)
    event("city_state_snapshot", nil, turn,
          { "event" => "city_state_snapshot", "turn" => turn, "city_state" => name })
  end

  def surveillance(civ, turn, **fields)
    spy_event("spy_surveillance_established", civ, turn, **fields)
  end

  def spy_event(type, civ, turn, spy:, agent: nil, city: nil, city_civ: nil, state: nil)
    payload = { "event" => type, "turn" => turn, "civ" => civ, "spy" => spy }
    payload["agent"] = agent if agent
    payload.merge!("city" => city, "city_civ" => city_civ) if city
    payload["state"] = state if state
    event(type, civ, turn, payload)
  end

  def influence(civ, turn, over:, level:)
    payload = { "event" => "snapshot", "turn" => turn, "civ" => civ,
                "influence" => [ { "civ" => over, "points" => 100, "level" => level, "trend" => "up" } ] }
    event("snapshot", civ, turn, payload)
  end

  def event(type, civ, turn, payload)
    @game.game_events.create!(
      seq: @seq += 1, session_index: 0, turn: turn, event_type: type, civ: civ, payload: payload
    )
  end
end
