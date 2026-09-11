require "test_helper"

class SpyNamesTest < ActiveSupport::TestCase
  ROOT = Rails.root.join("test/support/lekmod")

  test "names a spy the mod gave a flavour name" do
    assert_equal "Mukta", names("1.5").call("TXT_KEY_SPY_NAME_INDIA_7")
  end

  # A spy's id is a civ code and an ordinal, not English with the odd
  # rename the way a unit's usually is - so the fallback only makes the id
  # legible, never invents a name.
  test "reads an unresolved id as the civ and ordinal it names, not the raw id" do
    assert_equal "Mc Mughal 5", names("1.5").call("TXT_KEY_SPY_NAME_MC_MUGHAL_5")
  end

  # A flavour name outlives the rules that change between versions: a
  # snapshot taken before names were extracted is better served by another
  # snapshot's names than by none.
  test "falls back to the newest snapshot that names spies" do
    assert_equal "Abyadh", names("2.3").call("TXT_KEY_SPY_NAME_ARABIA_4")
  end

  test "names spies for a game that never recorded its mod version" do
    assert_equal "Mukta", names(nil).call("TXT_KEY_SPY_NAME_INDIA_7")
  end

  test "glosses the ids it is given and no others" do
    assert_equal(
      { "TXT_KEY_SPY_NAME_ARABIA_9" => "Arabia 9", "TXT_KEY_SPY_NAME_INDIA_7" => "Mukta" },
      names("1.5").glossary(%w[TXT_KEY_SPY_NAME_INDIA_7 TXT_KEY_SPY_NAME_ARABIA_9])
    )
  end

  private

  def names(version) = SpyNames.for(version, root: ROOT)
end
