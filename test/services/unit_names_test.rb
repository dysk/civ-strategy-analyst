require "test_helper"

class UnitNamesTest < ActiveSupport::TestCase
  ROOT = Rails.root.join("test/support/lekmod")

  test "names a unit the mod calls something its id does not say" do
    assert_equal "Gatling Gun", names("1.5").call("UNIT_GATLINGGUN")
  end

  # Most ids read as their own name, and shipping all of them would be a
  # dictionary of words that spell themselves.
  test "reads an id the mod does not name as plain English" do
    assert_equal "Crossbowman", names("1.5").call("UNIT_CROSSBOWMAN")
  end

  # Unit names outlive the rules that change between versions: a snapshot
  # taken before names were extracted is better served by another
  # snapshot's names than by none.
  test "falls back to the newest snapshot that names units" do
    assert_equal "Landship", names("2.3").call("UNIT_WWI_TANK")
  end

  test "names units for a game that never recorded its mod version" do
    assert_equal "Great War Bomber", names(nil).call("UNIT_WWI_BOMBER")
  end

  test "glosses the ids it is given and no others" do
    assert_equal({ "UNIT_WWI_BOMBER" => "Great War Bomber", "UNIT_SETTLER" => "Settler" },
                 names("1.5").glossary(%w[UNIT_WWI_BOMBER UNIT_SETTLER]))
  end

  private

  def names(version) = UnitNames.for(version, root: ROOT)
end
