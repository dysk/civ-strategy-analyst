require "test_helper"

class BattlesHelperTest < ActionView::TestCase
  test "shows a plain count when the record names no attacker" do
    assert_equal "Rome: 3", casualty_tally("Rome", 3, {})
  end

  test "names the attacker alongside the count when fully attributed" do
    assert_equal "Rome: 3 (Greece: 3)", casualty_tally("Rome", 3, { "Rome" => { "Greece" => 3 } })
  end

  test "names the unattributed remainder when only some losses are blamed" do
    assert_equal "Rome: 3 (Greece: 1, unknown: 2)", casualty_tally("Rome", 3, { "Rome" => { "Greece" => 1 } })
  end

  test "lists more than one attacker in sorted order" do
    assert_equal "Rome: 4 (Barbarians: 1, Greece: 3)",
                 casualty_tally("Rome", 4, { "Rome" => { "Greece" => 3, "Barbarians" => 1 } })
  end

  test "ignores another civ's attacker tally" do
    assert_equal "Rome: 3", casualty_tally("Rome", 3, { "Greece" => { "Rome" => 2 } })
  end
end
