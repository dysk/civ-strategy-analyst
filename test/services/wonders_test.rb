require "test_helper"

class WondersTest < ActiveSupport::TestCase
  ROOT = Rails.root.join("test/support/lekmod")
  WONDERLESS_ROOT = Rails.root.join("test/support/lekmod_wonderless")

  test "names a building from the catalogue" do
    assert_equal "Louvre", wonders("1.5").name("BUILDING_LOUVRE")
  end

  # Most ids read as their own name; the catalogue only carries the ones
  # that don't, plus the wonder flags.
  test "reads a building the catalogue does not name as plain English" do
    assert_equal "Aqueduct", wonders("1.5").name("BUILDING_AQUEDUCT")
  end

  test "knows a catalogued world wonder" do
    assert wonders("1.5").world?("BUILDING_LOUVRE")
  end

  test "a team wonder is not a world wonder" do
    assert_not wonders("1.5").world?("BUILDING_OXFORD_UNIVERSITY")
  end

  test "an ordinary building is not a world wonder" do
    assert_not wonders("1.5").world?("BUILDING_LIBRARY")
  end

  # A building keeps its name and its cap across versions, so a snapshot
  # taken before the catalogue existed is better served by a later one.
  test "falls back to the newest snapshot that carries a catalogue" do
    assert wonders("2.3").world?("BUILDING_LOUVRE")
  end

  # With no catalogue anywhere, the only wonders known are the ones this
  # game was seen to complete.
  test "without a catalogue, only observed wonders count as world wonders" do
    reader = Wonders.for("1.0", observed: %w[BUILDING_LOUVRE], root: WONDERLESS_ROOT)

    assert reader.world?("BUILDING_LOUVRE")
    assert_not reader.world?("BUILDING_GREAT_LIBRARY")
  end

  private

  def wonders(version) = Wonders.for(version, observed: [], root: ROOT)
end
