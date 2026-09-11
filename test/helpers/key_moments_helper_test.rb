require "test_helper"

class KeyMomentsHelperTest < ActionView::TestCase
  test "narrates a war that ended in peace" do
    assert_equal "Turn 57: Chile declared war on Vietnam (peace at turn 70)",
                 key_moment_sentence(war(turn_peace: 70))
  end

  test "narrates a war still being fought" do
    assert_equal "Turn 57: Chile declared war on Vietnam (ongoing)", key_moment_sentence(war)
  end

  # A war reads as a headline the reader scans and a short list of what it
  # cost underneath, not one line that runs off the edge.
  test "breaks a war into a headline and a list of what it cost" do
    moment = war(turn_peace: 70,
                 first_blood: { turn: 58, civ: "Vietnam", unit: "UNIT_SCOUT", by: "Chile",
                                fate: :killed, kind: :scout },
                 toll: { "Chile" => toll(losses: 2), "Vietnam" => toll(losses: 11, captured: 1) },
                 forces: { "Chile" => forces(opening: { "UNIT_BOMBER" => 8 }) })

    assert_equal "Turn 57: Chile declared war on Vietnam (peace at turn 70)", key_moment_sentence(moment)
    assert_equal [ "opening on Vietnam's Scout killed",
                   "dead: Chile 2, Vietnam 11",
                   "taken: Vietnam 1",
                   "fielded: Chile Bomber 8" ],
                 key_moment_details(moment)
  end

  test "a moment that is not a war has no detail list" do
    assert_nil key_moment_details({ type: :snowball, civ: "Chile", turn: 50, turn_end: 70 })
  end

  test "narrates what a war opened with" do
    moment = war(first_blood: { turn: 58, civ: "Vietnam", unit: "UNIT_SCOUT", by: "Chile",
                                fate: :killed, kind: :scout })

    assert_equal [ "opening on Vietnam's Scout killed" ], key_moment_details(moment)
  end

  test "leaves a name that already ends in s the bare apostrophe" do
    moment = war(first_blood: { turn: 58, civ: "Philippines", unit: "UNIT_LANCER", by: "Chile",
                                fate: :killed, kind: :soldier })

    assert_includes key_moment_details(moment), "opening on Philippines' Lancer killed"
  end

  # Both sides are named whenever either bled, since a war one side came
  # through untouched reads as an even fight without the other figure.
  test "counts each side's dead" do
    moment = war(toll: { "Chile" => toll(losses: 2), "Vietnam" => toll(losses: 11) })

    assert_equal [ "dead: Chile 2, Vietnam 11" ], key_moment_details(moment)
  end

  test "counts the civilians a war took where it killed nobody" do
    moment = war(toll: { "Chile" => toll, "Vietnam" => toll(captured: 1) })

    assert_equal [ "taken: Vietnam 1" ], key_moment_details(moment)
  end

  test "names what each side had standing when the war opened" do
    moment = war(forces: { "Chile" => forces(opening: { "UNIT_BOMBER" => 8 }),
                           "Vietnam" => forces(opening: { "UNIT_RIFLEMAN" => 4 }) })

    assert_equal [ "fielded: Chile Bomber 8; Vietnam Rifleman 4" ], key_moment_details(moment)
  end

  # A roster runs to a dozen types with a tail of one unit each. Its head
  # is what tells one army from another.
  test "names only the leading types of an army" do
    moment = war(forces: { "Chile" => forces(opening: { "UNIT_BOMBER" => 8, "UNIT_TANK" => 5,
                                                        "UNIT_INFANTRY" => 3, "UNIT_SCOUT" => 1 }) })

    assert_equal [ "fielded: Chile Bomber 8, Tank 5, Infantry 3" ], key_moment_details(moment)
  end

  # A roster counts workers and caravans, which is right for a ledger and
  # wrong for a sentence about a war: the heaviest three types in a late
  # empire are its labourers.
  test "names the soldiers that took the field rather than the labourers" do
    moment = war(forces: { "Chile" => forces(opening: { "UNIT_WORKER" => 6, "UNIT_CARAVAN" => 4,
                                                        "UNIT_BOMBER" => 3, "UNIT_TANK" => 2 }) })

    assert_equal [ "fielded: Chile Bomber 3, Tank 2" ], key_moment_details(moment)
  end

  test "leaves out a side whose whole roster was labourers" do
    moment = war(forces: { "Chile" => forces(opening: { "UNIT_BOMBER" => 3 }),
                           "Vietnam" => forces(opening: { "UNIT_WORKER" => 6 }) })

    assert_equal [ "fielded: Chile Bomber 3" ], key_moment_details(moment)
  end

  test "names a weapon a side built after the war began" do
    moment = war(forces: { "Chile" => forces(raised: { "UNIT_TANK" => 2 },
                                             debuts: [ { turn: 62, unit: "UNIT_TANK", via: :built } ]) })

    assert_equal [ "built: Chile Tank 2 (turn 62)" ], key_moment_details(moment)
  end

  # A regiment handed a new weapon where it stood is a different act from
  # a new one raised to carry it, and a war is often mostly one or mostly
  # the other.
  test "keeps what a side re-armed into apart from what it built" do
    moment = war(forces: { "Chile" => forces(
      raised: { "UNIT_BOMBER" => 4 }, upgraded: { "UNIT_ARTILLERY" => 5 },
      debuts: [ { turn: 60, unit: "UNIT_ARTILLERY", via: :upgraded },
                { turn: 62, unit: "UNIT_BOMBER", via: :built } ]) })

    assert_equal [ "built: Chile Bomber 4 (turn 62)", "re-armed: Chile Artillery 5 (turn 60)" ],
                 key_moment_details(moment)
  end

  # A long war debuts a dozen types and the earliest of them are whatever
  # the tech tree happened to obsolete first. What a side put four of into
  # the field is the arrival worth the sentence.
  test "orders arrivals by how many of them reached the field" do
    moment = war(forces: { "Chile" => forces(
      raised: { "UNIT_SCOUT" => 1, "UNIT_BOMBER" => 4 },
      debuts: [ { turn: 60, unit: "UNIT_SCOUT", via: :built },
                { turn: 62, unit: "UNIT_BOMBER", via: :built } ]) })

    assert_equal [ "built: Chile Bomber 4 (turn 62), Scout 1 (turn 60)" ], key_moment_details(moment)
  end

  # A type can be both built and upgraded into. Each list counts what
  # actually happened to reach it, not the total that arrived.
  test "counts a type it built by what was built of it" do
    moment = war(forces: { "Chile" => forces(
      raised: { "UNIT_GATLINGGUN" => 1 }, upgraded: { "UNIT_GATLINGGUN" => 2 },
      debuts: [ { turn: 62, unit: "UNIT_GATLINGGUN", via: :built } ]) })

    assert_equal [ "built: Chile Gatling Gun 1 (turn 62)" ], key_moment_details(moment)
  end

  # A war of eighty turns turns on the weapons that reach it, so this list
  # runs longer than the roster's - but a list item is still not a table.
  test "names at most six arrivals of a kind" do
    units = %w[UNIT_TANK UNIT_BOMBER UNIT_INFANTRY UNIT_ARTILLERY UNIT_AIRSHIP UNIT_LANCER UNIT_CANNON]
    moment = war(forces: { "Chile" => forces(
      raised: units.index_with { 1 },
      debuts: units.each_with_index.map { |unit, i| { turn: 60 + i, unit: unit, via: :built } }) })

    assert_equal 6, key_moment_details(moment).join.scan(/\(turn \d+\)/).size
  end

  test "leaves a side that fielded nothing out of the order of battle" do
    moment = war(forces: { "Chile" => forces(opening: { "UNIT_BOMBER" => 8 }),
                           "Kathmandu" => forces })

    assert_equal [ "fielded: Chile Bomber 8" ], key_moment_details(moment)
  end

  test "narrates a lost buffer city by its captor and the rival it stood against" do
    moment = { type: :buffer_city_lost, turn: 152, civ: "Arabia", captured_by: "Babylon",
               against: "Philippines", city: "Medina" }

    assert_equal(
      "Turn 152: Arabia lost Medina to Babylon, the city between its capital and Philippines's",
      key_moment_sentence(moment)
    )
  end

  test "narrates a lost wonder race by the wonder, the winner and what was sunk" do
    moment = { type: :wonder_race_lost, turn: 158, civ: "England", city: "London",
               wonder: "BUILDING_LOUVRE", wonder_name: "Louvre", scale: :close,
               production_invested: 425, turns_left: 2, winner: "Netherlands",
               winner_city: "Amsterdam", winner_finish: :hard_built }

    assert_equal "Turn 158: England lost the race for Louvre to Netherlands, 425 production sunk in",
                 key_moment_sentence(moment)
  end

  test "notes when the winner of a race finished it ahead of a hard build" do
    moment = { type: :wonder_race_lost, turn: 158, civ: "England", city: "London",
               wonder: "BUILDING_LOUVRE", wonder_name: "Louvre", scale: :close,
               production_invested: 425, turns_left: 2, winner: "Netherlands",
               winner_city: "Amsterdam", winner_finish: :ahead_of_estimate }

    assert_match(/ahead of a hard build/, key_moment_sentence(moment))
  end

  test "names the years of vision when a human contender watched the race in full view" do
    moment = { type: :wonder_race_lost, turn: 158, civ: "England", city: "London",
               wonder: "BUILDING_LOUVRE", wonder_name: "Louvre", scale: :close,
               production_invested: 425, turns_left: 2, winner: "Netherlands",
               winner_city: "Amsterdam", winner_finish: :hard_built,
               contender_human: true, observed_from_turn: 152, observed_turns: 6 }

    assert_match(/England had 6 turns of visibility on it, from turn 152/, key_moment_sentence(moment))
  end

  test "never states a decision in the full-view clause" do
    moment = { type: :wonder_race_lost, turn: 158, civ: "England", city: "London",
               wonder: "BUILDING_LOUVRE", wonder_name: "Louvre", scale: :close,
               production_invested: 425, turns_left: 2, winner: "Netherlands",
               winner_city: "Amsterdam", winner_finish: :hard_built,
               contender_human: true, observed_from_turn: 152, observed_turns: 6, response: :pressed_on }

    refute_match(/pressed_on|pressed on/, key_moment_sentence(moment))
  end

  test "stays silent about vision for an AI contender, even when it was observed" do
    moment = { type: :wonder_race_lost, turn: 158, civ: "England", city: "London",
               wonder: "BUILDING_LOUVRE", wonder_name: "Louvre", scale: :close,
               production_invested: 425, turns_left: 2, winner: "Netherlands",
               winner_city: "Amsterdam", winner_finish: :hard_built,
               contender_human: false, observed_from_turn: 152, observed_turns: 6 }

    assert_equal "Turn 158: England lost the race for Louvre to Netherlands, 425 production sunk in",
                 key_moment_sentence(moment)
  end

  test "adds no clause for a human contender with no vision of the race" do
    moment = { type: :wonder_race_lost, turn: 158, civ: "England", city: "London",
               wonder: "BUILDING_LOUVRE", wonder_name: "Louvre", scale: :close,
               production_invested: 425, turns_left: 2, winner: "Netherlands",
               winner_city: "Amsterdam", winner_finish: :hard_built,
               contender_human: true, observed_from_turn: nil }

    assert_equal "Turn 158: England lost the race for Louvre to Netherlands, 425 production sunk in",
                 key_moment_sentence(moment)
  end

  test "narrates a wonder becoming a contest" do
    moment = { type: :wonder_race, turn: 154, wonder: "BUILDING_LOUVRE", wonder_name: "Louvre",
               winner: "Netherlands", contenders: %w[England] }

    assert_equal "Turn 154: Louvre became a contested build: Netherlands against England",
                 key_moment_sentence(moment)
  end

  test "marks a lost wonder race as a downward moment" do
    assert_match(/trend--down/, key_moment_trend({ type: :wonder_race_lost, turn: 158 }))
  end

  test "leaves the snowballed metric to the heading above the list" do
    moment = { type: :snowball, civ: "Chile", turn: 50, turn_end: 70, duration_turns: 20 }

    assert_equal "Turns 50–70: Chile pulled decisively ahead", key_moment_sentence(moment)
  end

  test "spans a range of turns only when the moment lasted more than one" do
    moment = { type: :unhappiness_period, civ: "Chile", turn: 40, turn_end: 40 }

    assert_equal "Turn 40: Chile happiness stayed below zero", key_moment_sentence(moment)
  end

  test "narrates a religion founding with its beliefs and order" do
    moment = { type: :religion_founded, turn: 30, civ: "Chile", religion: "Christianity",
               holy_city: "Santiago", beliefs: %w[BELIEF_A BELIEF_B], order: 2 }

    assert_equal(
      "Turn 30: Chile founded Christianity (#2) with BELIEF_A, BELIEF_B",
      key_moment_sentence(moment)
    )
  end

  test "marks a swing upwards so its direction is visible before reading" do
    moment = { type: :happiness_surge, civ: "Chile", turn: 73, turn_end: 74, from: 3, to: 13 }

    assert_match(/trend--up/, key_moment_trend(moment))
  end

  test "marks a swing downwards" do
    moment = { type: :army_power_collapse, civ: "Chile", turn: 80, turn_end: 85, from: 200, to: 100 }

    assert_match(/trend--down/, key_moment_trend(moment))
  end

  test "hides the arrow from screen readers, since the sentence already says it" do
    moment = { type: :happiness_surge, civ: "Chile", turn: 73, turn_end: 74, from: 3, to: 13 }

    assert_match(/aria-hidden/, key_moment_trend(moment))
  end

  test "leaves a moment that is not a swing unmarked" do
    moment = { type: :unhappiness_period, civ: "Chile", turn: 40, turn_end: 60 }

    assert_nil key_moment_trend(moment)
  end

  test "distinguishes a military collapse from a surge" do
    moment = { type: :army_power_collapse, civ: "Chile", turn: 80, turn_end: 85, from: 200, to: 100 }

    assert_equal "Turns 80–85: Chile army power dropped from 200 to 100", key_moment_sentence(moment)
  end

  test "narrates an influence level reached, humanizing the level" do
    moment = { type: :influence_level_reached, turn: 90, civ: "Chile", opponent: "Vietnam",
               level: "INFLUENCE_LEVEL_DOMINANT" }

    assert_equal "Turn 90: Chile became Dominant on Vietnam", key_moment_sentence(moment)
  end

  test "narrates cultural victory imminent" do
    moment = { type: :cultural_victory_imminent, turn: 120, civ: "Chile",
               civs_influential_on: 3, living_majors: 4 }

    assert_equal(
      "Turn 120: Chile is culturally influential on 3 of 4 living majors",
      key_moment_sentence(moment)
    )
  end

  test "narrates a Congress host change" do
    moment = { type: :congress_host_change, turn: 90, from: "Chile", to: "Vietnam" }

    assert_equal "Turn 90: World Congress host passed from Chile to Vietnam", key_moment_sentence(moment)
  end

  test "narrates the first Congress host, with no previous host" do
    moment = { type: :congress_host_change, turn: 90, from: nil, to: "Vietnam" }

    assert_equal "Turn 90: World Congress host passed from no host to Vietnam", key_moment_sentence(moment)
  end

  test "narrates the United Nations forming" do
    moment = { type: :united_nations_formed, turn: 220 }

    assert_equal "Turn 220: The United Nations formed", key_moment_sentence(moment)
  end

  test "narrates diplomatic victory imminent" do
    moment = { type: :diplomatic_victory_imminent, turn: 200, civ: "Chile", votes: 14, votes_needed: 12 }

    assert_equal(
      "Turn 200: Chile reached 14 delegate votes, meeting the 12 needed for a diplomatic victory",
      key_moment_sentence(moment)
    )
  end

  test "narrates a passed resolution with its proposer" do
    moment = { type: :resolution_passed, turn: 150, resolution: "RESOLUTION_WORLD_FAIR", proposer: "Chile" }

    assert_equal "Turn 150: RESOLUTION_WORLD_FAIR passed, proposed by Chile", key_moment_sentence(moment)
  end

  test "narrates a civilization gaining control of a capital" do
    moment = { type: :capital_gained, turn: 100, civ: "Chile", original_owner: "Vietnam" }

    assert_equal "Turn 100: Chile gained control of Vietnam's original capital", key_moment_sentence(moment)
  end

  test "narrates a civilization losing control of a capital, with a downward trend" do
    moment = { type: :capital_lost, turn: 100, civ: "Chile", original_owner: "Chile" }

    assert_equal "Turn 100: Chile lost control of Chile's original capital", key_moment_sentence(moment)
    assert_match(/trend--down/, key_moment_trend(moment))
  end

  test "narrates Apollo Program completion" do
    moment = { type: :apollo_completed, turn: 180, civ: "Chile" }

    assert_equal "Turn 180: Chile completed the Apollo Program", key_moment_sentence(moment)
  end

  test "narrates a spaceship part assembly" do
    moment = { type: :spaceship_part_assembled, turn: 190, civ: "Chile", part: "booster", count: 2 }

    assert_equal "Turn 190: Chile assembled a booster (2 total)", key_moment_sentence(moment)
  end

  test "narrates science victory imminent" do
    moment = { type: :science_victory_imminent, turn: 195, civ: "Chile", parts_assembled: 5 }

    assert_equal "Turn 195: Chile assembled 5 of 6 spaceship parts", key_moment_sentence(moment)
  end

  # The id is not the name: LEKMOD calls UNIT_WWI_BOMBER a Great War
  # Bomber, and a reader looking for one in the ruleset finds nothing
  # under "Wwi Bomber".
  test "names a unit as the ruleset names it" do
    @game = Game.new(lekmod_version: "35.3")
    moment = war(first_blood: { turn: 58, civ: "Vietnam", unit: "UNIT_WWI_BOMBER", by: "Chile",
                                fate: :killed, kind: :soldier })

    assert_includes key_moment_details(moment).join, "Vietnam's Great War Bomber killed"
  end

  test "reads a unit no ruleset names as plain English" do
    moment = war(first_blood: { turn: 58, civ: "Vietnam", unit: "UNIT_MADE_UP_RIDER", by: "Chile",
                                fate: :killed, kind: :soldier })

    assert_includes key_moment_details(moment).join, "Vietnam's Made Up Rider killed"
  end

  test "narrates a player conceding the game as unwinnable with the vote that ratified it" do
    moment = { type: :player_declared_irrelevant, turn: 120, civ: "Rome",
               proposer: "Rome", yes_votes: 4, no_votes: 0 }

    assert_equal(
      "Turn 120: Rome asked to be ruled out of contention, and the other players agreed (4–0)",
      key_moment_sentence(moment)
    )
  end

  test "marks a player ruled out of contention with a downward trend" do
    moment = { type: :player_declared_irrelevant, turn: 120, civ: "Rome",
               proposer: "Rome", yes_votes: 4, no_votes: 0 }

    assert_match(/trend--down/, key_moment_trend(moment))
  end

  private

  def war(turn_peace: nil, first_blood: nil, toll: {}, forces: nil)
    { type: :war, turn: 57, turn_peace: turn_peace, attacker_civs: %w[Chile],
      defender_civs: %w[Vietnam], first_blood: first_blood, toll: toll, forces: forces }
  end

  def forces(opening: {}, raised: {}, upgraded: {}, debuts: [])
    { opening: opening, closing: {}, raised: raised, upgraded: upgraded, raised_civilian: {},
      debuts: debuts, peak: nil, nadir: nil }
  end

  def toll(losses: 0, captured: 0)
    { losses: losses, loss_types: {}, kills: 0, kill_types: {},
      captured: captured, captured_types: {}, seized: 0, seized_types: {} }
  end
end
