require "test_helper"

class EspionageOperationsControllerTest < ActionDispatch::IntegrationTest
  setup do
    @game = Game.create!(name: "Espionage Operations Game")
    @game.players.create!(civ: "India")
    @seq = 0
  end

  test "reports no data for a game with no spy activity" do
    get game_espionage_url(@game)

    assert_response :success
    assert_select ".empty-state"
  end

  test "shows how many spies each civilization created, lost, promoted and never located" do
    created("India", 10, spy: "INDIA_1", agent: 1, city: "Delhi", city_civ: "India")
    created("India", 20, spy: "INDIA_2", agent: 2)
    promoted("India", 30, spy: "INDIA_1", agent: 1)
    killed("England", 5, spy: "ENGLAND_1", agent: 9, city: "London", city_civ: "England")

    get game_espionage_url(@game)

    assert_response :success
    assert_select "table.espionage-capacity tbody tr" do
      assert_select "td", "India"
      assert_select "td", "2" # created
      assert_select "td", "1" # promoted
      assert_select "td", "1" # never located (INDIA_2)
    end
  end

  test "lists a loss whose death site the log names directly" do
    killed("England", 5, spy: "ENGLAND_1", agent: 9, city: "London", city_civ: "England")

    get game_espionage_url(@game)

    assert_response :success
    assert_select "table.espionage-losses tbody tr" do
      assert_select "td", "England"
      assert_select "td", "London"
    end
    assert_select "table.espionage-losses td.reconstructed", false
  end

  test "marks a loss whose death site is reconstructed from the last sighting" do
    moved("England", 1, spy: "ENGLAND_1", agent: 9, city: "London", city_civ: "England", state: "travelling")
    killed("England", 5, spy: "ENGLAND_1", agent: 9)

    get game_espionage_url(@game)

    assert_select "table.espionage-losses td.reconstructed"
  end

  test "names a spy the ruleset gives a flavour name, in the losses table" do
    @game.update!(lekmod_version: "35.3")
    killed("India", 5, spy: "TXT_KEY_SPY_NAME_INDIA_7", agent: 7, city: "Delhi", city_civ: "India")

    get game_espionage_url(@game)

    assert_select "table.espionage-losses td", "Mukta"
  end

  test "folds each civilization's spy tenures into its own table" do
    moved("India", 100, spy: "INDIA_7", agent: 7, city: "Kyoto", city_civ: "Japan", state: "travelling")
    surveillance("India", 104, spy: "INDIA_7", agent: 7, city: "Kyoto", city_civ: "Japan")

    get game_espionage_url(@game)

    assert_response :success
    assert_select "h2", "India"
    assert_select "table.espionage-tenures tbody tr" do
      assert_select "td", "Kyoto"
      assert_select "td", "100"
      assert_select "td", "104"
    end
  end

  test "marks a tenure's vision as a floor rather than a confirmed date" do
    # No posting precedes this completion, so the mission itself is the only
    # evidence of the tenure - a floor, not a dated arrival.
    mission("India", 105, spy: "INDIA_7", agent: 7, city: "Kyoto", city_civ: "Japan", state: "gathering_intel")

    get game_espionage_url(@game)

    assert_select "table.espionage-tenures td.bounded"
  end

  test "does not mark a logged surveillance date as a floor" do
    moved("India", 100, spy: "INDIA_7", agent: 7, city: "Kyoto", city_civ: "Japan", state: "travelling")
    surveillance("India", 104, spy: "INDIA_7", agent: 7, city: "Kyoto", city_civ: "Japan")

    get game_espionage_url(@game)

    assert_select "table.espionage-tenures td.bounded", false
  end

  test "names a spy the ruleset gives a flavour name, in the tenures table" do
    @game.update!(lekmod_version: "35.3")
    moved("India", 100, spy: "TXT_KEY_SPY_NAME_INDIA_7", agent: 7, city: "Kyoto", city_civ: "Japan",
          state: "travelling")

    get game_espionage_url(@game)

    assert_select "table.espionage-tenures td", "Mukta"
    assert_select "table.espionage-tenures td", text: "TXT_KEY_SPY_NAME_INDIA_7", count: 0
  end

  test "reads an unresolved spy id as the civ and ordinal it names, not the raw id" do
    @game.update!(lekmod_version: "35.3")
    moved("India", 100, spy: "TXT_KEY_SPY_NAME_MADE_UP_9", agent: 7, city: "Kyoto", city_civ: "Japan",
          state: "travelling")

    get game_espionage_url(@game)

    assert_select "table.espionage-tenures td", "Made Up 9"
  end

  test "splits completed missions by kind" do
    surveillance("India", 104, spy: "INDIA_7", agent: 7, city: "Kyoto", city_civ: "Japan")
    mission("India", 110, spy: "INDIA_7", agent: 7, city: "Kyoto", city_civ: "Japan", state: "gathering_intel")
    mission("India", 200, spy: "INDIA_8", agent: 8, city: "Osaka", city_civ: "Japan", state: "rigging_election")

    get game_espionage_url(@game)

    assert_response :success
    assert_select "h3", "Tech Theft"
    assert_select "h3", "Election Rigging"
  end

  test "marks an unanchored mission as uncertain rather than counting it in plainly" do
    # No posting precedes this completion, so it cannot be anchored to a city visit.
    mission("India", 110, spy: "INDIA_7", agent: 7, city: "Kyoto", city_civ: "Japan", state: "gathering_intel")

    get game_espionage_url(@game)

    assert_select "table.espionage-missions td.uncertain"
  end

  test "names a spy the ruleset gives a flavour name, in the missions table" do
    @game.update!(lekmod_version: "35.3")
    mission("India", 110, spy: "TXT_KEY_SPY_NAME_INDIA_7", agent: 7, city: "Kyoto", city_civ: "Japan",
            state: "gathering_intel")

    get game_espionage_url(@game)

    assert_select "table.espionage-missions td", "Mukta"
  end

  test "lists a garrison read straight from the log" do
    moved("India", 50, spy: "INDIA_9", agent: 9, city: "Delhi", city_civ: "India", state: "counter_intel")

    get game_espionage_url(@game)

    assert_response :success
    assert_select "table.espionage-garrisons tbody tr" do
      assert_select "td", "India"
      assert_select "td", "Delhi"
      assert_select "td", "Read from log"
    end
  end

  test "marks an inferred garrison with its confidence rather than presenting it as fact" do
    created("India", 90, spy: "INDIA_7", agent: 7)
    killed("England", 109, spy: "ENGLAND_1", agent: 1, city: "Delhi", city_civ: "India")

    get game_espionage_url(@game)

    assert_select "table.espionage-garrisons td", /Inferred/
  end

  test "lists a coup with its outcome" do
    moved("Arabia", 177, spy: "ARABIA_0", city: "Valletta", city_civ: "Valletta", state: "travelling")
    killed("Arabia", 181, spy: "ARABIA_0", city: "Valletta", city_civ: "Valletta")
    city_state("Valletta", 181, relations: { "Arabia" => [ -10, 1.25 ] })

    get game_espionage_url(@game)

    assert_response :success
    assert_select "table.espionage-coups tbody tr" do
      assert_select "td", "Arabia"
      assert_select "td", "Valletta"
      assert_select "td", "failed"
    end
  end

  test "links back to the game" do
    created("India", 10, spy: "INDIA_1", agent: 1)

    get game_espionage_url(@game)

    assert_select "a[href=?]", game_path(@game)
  end

  test "404s for an unknown game id" do
    get game_espionage_url(game_id: 999_999)

    assert_response :not_found
  end

  private

  def moved(civ, turn, **fields) = spy_event("spy_moved", civ, turn, **fields)
  def created(civ, turn, **fields) = spy_event("spy_created", civ, turn, **fields)
  def killed(civ, turn, **fields) = spy_event("spy_killed", civ, turn, **fields)
  def promoted(civ, turn, **fields) = spy_event("spy_promoted", civ, turn, **fields)
  def mission(civ, turn, **fields) = spy_event("spy_mission_completed", civ, turn, **fields)

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

  def city_state(name, turn, relations: {})
    event("city_state_snapshot", nil, turn,
      { "event" => "city_state_snapshot", "turn" => turn, "city_state" => name,
        "relations" => relations.map { |civ, (influence, per_turn)|
          { "civ" => civ, "influence" => influence, "per_turn" => per_turn } } })
  end

  def event(type, civ, turn, payload)
    @game.game_events.create!(
      seq: @seq += 1, session_index: 0, turn: turn, event_type: type, civ: civ, payload: payload
    )
  end
end
