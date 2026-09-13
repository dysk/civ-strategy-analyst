require "test_helper"

class OpeningStrategyHelperTest < ActionView::TestCase
  helper GamesHelper
  test "opening_strategy_branch names the opened branch without its internal prefix" do
    assert_equal "Tradition", opening_strategy_branch({ branch: "POLICY_BRANCH_TRADITION" })
  end

  test "opening_strategy_branch has nothing to name for a civ that never opened a branch" do
    assert_equal "&mdash;", opening_strategy_branch({ branch: nil })
  end

  test "opening_strategy_closed reports how long the tree took to close" do
    row = { closed_opening: { finished_turn: 40, turns_to_close: 29 } }

    assert_equal "29 (t. 40)", opening_strategy_closed(row)
  end

  test "opening_strategy_closed has nothing to report while the tree is still open" do
    assert_equal "&mdash;", opening_strategy_closed({ closed_opening: { finished_turn: nil, turns_to_close: nil } })
    assert_equal "&mdash;", opening_strategy_closed({ closed_opening: nil })
  end

  test "opening_strategy_first_tech names whatever tech came first" do
    assert_equal "Mining", opening_strategy_first_tech({ first_tech: "TECH_MINING" })
    assert_equal "Pottery", opening_strategy_first_tech({ first_tech: "TECH_POTTERY" })
  end

  test "opening_strategy_first_tech has nothing to name for a civ with no logged tech" do
    assert_equal "&mdash;", opening_strategy_first_tech({ first_tech: nil })
  end

  test "opening_strategy_scouts names the scout opening category" do
    assert_equal "2 scouts", opening_strategy_scouts({ opening_scouts: { category: :opened_with_two_scouts } })
    assert_equal "2 scouts (interrupted)", opening_strategy_scouts({ opening_scouts: { category: :two_scouts_interrupted } })
    assert_equal "1 scout", opening_strategy_scouts({ opening_scouts: { category: :one_scout } })
    assert_equal "no scouts", opening_strategy_scouts({ opening_scouts: { category: :no_scouts } })
  end

  test "opening_strategy_items lists the first built items with their turn and kind" do
    row = { opening_scouts: { items: [
      { turn: 1, kind: :unit, id: "UNIT_SCOUT" },
      { turn: 1, kind: :unit, id: "UNIT_SCOUT" },
      { turn: 5, kind: :building, id: "BUILDING_MONUMENT" }
    ] } }

    assert_equal "t1 Scout, t1 Scout, t5 Monument", opening_strategy_items(row)
  end

  test "opening_strategy_items has nothing to list for a civ that built nothing" do
    assert_equal "&mdash;", opening_strategy_items({ opening_scouts: { items: [] } })
  end

  test "opening_strategy_style titleizes the playstyle" do
    assert_equal "Tall", opening_strategy_style({ playstyle: { style: :tall } })
    assert_equal "Wide", opening_strategy_style({ playstyle: { style: :wide } })
  end

  test "opening_strategy_style has nothing to name for an unresolved tie" do
    assert_equal "&mdash;", opening_strategy_style({ playstyle: { style: nil } })
  end

  test "opening_strategy_worker_theft counts raids and bullying together" do
    assert_equal "2", opening_strategy_worker_theft({ worker_theft: 2 })
  end

  test "opening_strategy_worker_theft has nothing to report when no worker was stolen" do
    assert_equal "&mdash;", opening_strategy_worker_theft({ worker_theft: 0 })
  end

  test "opening_strategy_national_college reports turns early against the target" do
    row = { national_college: { built_turn: 58, target_turn: 67, turns_early: 9, turns_after_finisher: nil } }

    assert_equal "t. 58 (9 early)", opening_strategy_national_college(row)
  end

  test "opening_strategy_national_college reports a negative turns_early as turns late" do
    row = { national_college: { built_turn: 159, target_turn: 67, turns_early: -92, turns_after_finisher: nil } }

    assert_equal "t. 159 (92 late)", opening_strategy_national_college(row)
  end

  test "opening_strategy_national_college reports turns after the finisher for a Liberty opening" do
    row = { national_college: { built_turn: 90, target_turn: nil, turns_early: nil, turns_after_finisher: 5 } }

    assert_equal "t. 90 (5 after finisher)", opening_strategy_national_college(row)
  end

  test "opening_strategy_national_college has nothing to report when it was never built" do
    row = { national_college: { built_turn: nil, target_turn: 67, turns_early: nil, turns_after_finisher: nil } }

    assert_equal "&mdash;", opening_strategy_national_college(row)
  end

  test "opening_strategy_wonders counts good wonders built against the targets for its style" do
    row = { good_wonders: { targets: %w[BUILDING_ORACLE BUILDING_PYRAMID], built: %w[BUILDING_ORACLE] } }

    assert_equal "1/2", opening_strategy_wonders(row)
  end

  test "opening_strategy_workers_per_city reports the ratio to two decimal places" do
    assert_equal "1.50", opening_strategy_workers_per_city({ workers_per_city: { ratio: 1.5 } })
  end

  test "opening_strategy_workers_per_city has nothing to report for a civ that never founded a city" do
    assert_equal "&mdash;", opening_strategy_workers_per_city({ workers_per_city: { ratio: nil } })
  end

  test "opening_strategy_universities counts how many hit the population target" do
    row = { universities: [ { on_target: true }, { on_target: false } ] }

    assert_equal "1/2", opening_strategy_universities(row)
  end

  test "opening_strategy_universities has nothing to report when none was built" do
    assert_equal "&mdash;", opening_strategy_universities({ universities: [] })
  end

  test "opening_strategy_caravans reports the turn of the first caravan and how many arrived" do
    row = { caravans_to_capital: { first_turn: 12, routes: [ { turn: 12 }, { turn: 20 }, { turn: 35 } ] } }

    assert_equal "12 (×3)", opening_strategy_caravans(row)
  end

  test "opening_strategy_caravans reports a single caravan the same way as several" do
    row = { caravans_to_capital: { first_turn: 12, routes: [ { turn: 12 } ] } }

    assert_equal "12 (×1)", opening_strategy_caravans(row)
  end

  test "opening_strategy_caravans has nothing to report when no caravan ever arrived" do
    assert_equal "&mdash;", opening_strategy_caravans({ caravans_to_capital: { first_turn: nil, routes: [] } })
  end
end
