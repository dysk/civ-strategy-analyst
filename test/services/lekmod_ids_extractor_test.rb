require "test_helper"

class LekmodIdsExtractorTest < ActiveSupport::TestCase
  SOURCE_DIR = Rails.root.join("test/support/lekmod_source")

  test "resolves a policy name via a plain Row in the Policies table" do
    ids = LekmodIdsExtractor.new(SOURCE_DIR).call

    assert_equal "Test Policy", ids["POLICY_TEST_ONE"]
  end

  test "resolves a belief name via ShortDescription, preferring a Replace over the Row it overrides" do
    ids = LekmodIdsExtractor.new(SOURCE_DIR).call

    assert_equal "New Name", ids["BELIEF_TEST_ONE"]
  end

  test "resolves a resolution name via a plain Row in the Resolutions table" do
    ids = LekmodIdsExtractor.new(SOURCE_DIR).call

    assert_equal "Test Resolution", ids["RESOLUTION_TEST_ONE"]
  end

  test "ignores text defined outside the Language_en_US wrapper" do
    ids = LekmodIdsExtractor.new(SOURCE_DIR).call

    refute_equal "Deutscher Name", ids["BELIEF_TEST_ONE"]
  end

  test "omits an entity whose text key has no resolved text anywhere" do
    ids = LekmodIdsExtractor.new(SOURCE_DIR).call

    refute ids.key?("BELIEF_TEST_UNRESOLVED")
  end

  test "merges entity and text definitions across multiple XML files in the source directory" do
    ids = LekmodIdsExtractor.new(SOURCE_DIR).call

    assert_equal "Test Policy", ids["POLICY_TEST_ONE"]
    assert_equal "New Name", ids["BELIEF_TEST_ONE"]
  end

  test "scans XML files in subdirectories recursively" do
    ids = LekmodIdsExtractor.new(SOURCE_DIR).call

    assert_equal "Nested Belief", ids["BELIEF_TEST_NESTED"]
  end

  test "resolves a unit name from the Units table via its text key" do
    names = LekmodIdsExtractor.new(SOURCE_DIR).unit_names

    assert_equal "Test Gatling Gun", names["UNIT_TEST_ONE"]
  end

  # LEKMOD's own units skip the text tables and write their English name
  # straight into Description, where vanilla units carry a TXT_KEY.
  test "takes a unit description that is already English as the name" do
    names = LekmodIdsExtractor.new(SOURCE_DIR).unit_names

    assert_equal "Test Anti-Tank Rifle", names["UNIT_TEST_LITERAL"]
  end

  test "leaves entities out of the unit names" do
    names = LekmodIdsExtractor.new(SOURCE_DIR).unit_names

    refute names.key?("POLICY_TEST_ONE")
  end

  test "resolves a spy name straight from its text key, preferring a Replace over the Row it overrides" do
    names = LekmodIdsExtractor.new(SOURCE_DIR).spy_names

    assert_equal "New Spy", names["TXT_KEY_SPY_NAME_TEST_ONE"]
  end

  test "resolves every spy name text key present, not just the overridden one" do
    names = LekmodIdsExtractor.new(SOURCE_DIR).spy_names

    assert_equal "Test Spy Two", names["TXT_KEY_SPY_NAME_TEST_TWO"]
  end

  test "leaves non-spy text keys out of the spy names" do
    names = LekmodIdsExtractor.new(SOURCE_DIR).spy_names

    refute names.key?("TXT_KEY_POLICY_TEST_ONE")
  end

  test "resolves a building name from the Buildings table via its text key" do
    assert_equal "Test Wonder", buildings["BUILDING_TEST_WONDER"]["name"]
  end

  # Same as units: LEKMOD's own buildings write English straight into Description.
  test "takes a building description that is already English as the name" do
    assert_equal "Test Team Wonder", buildings["BUILDING_TEST_TEAM"]["name"]
  end

  # A wonder is whatever the ruleset caps, and it caps in three scopes -
  # the cap sits on the building's class, not the building.
  test "classifies a building whose class is capped once globally as a world wonder" do
    assert_equal "world", buildings["BUILDING_TEST_WONDER"]["wonder"]
  end

  test "classifies a building whose class is capped per team as a team wonder" do
    assert_equal "team", buildings["BUILDING_TEST_TEAM"]["wonder"]
  end

  test "classifies a building whose class is capped per player as a national wonder" do
    assert_equal "national", buildings["BUILDING_TEST_NATIONAL"]["wonder"]
  end

  test "leaves an uncapped building unclassified" do
    refute buildings["BUILDING_TEST_PLAIN"].key?("wonder")
  end

  test "omits a building whose text key resolves to nothing" do
    refute buildings.key?("BUILDING_TEST_UNNAMED")
  end

  # National wonders carry the game's [COLOR_...] markup and a trailing "*"
  # marker in their name text; a display name wants neither.
  test "strips Civ5 text markup and the national-wonder marker from a building name" do
    assert_equal "Test Markup Wonder", buildings["BUILDING_TEST_MARKUP"]["name"]
  end

  test "resolves a technology name from the Technologies table via its text key" do
    assert_equal "Test Technology", technologies["TECH_TEST_ONE"]
  end

  # Same as units and buildings: LEKMOD's own techs write English straight into Description.
  test "takes a technology description that is already English as the name" do
    assert_equal "Test Literal Tech", technologies["TECH_TEST_LITERAL"]
  end

  # ResourceUsage is an integer column (CIV5Units.xml:192705), not a string
  # enum - RESOURCEUSAGE_BONUS/STRATEGIC/LUXURY = 0/1/2 per CvEnums.h:1194.
  test "classifies a resource whose ResourceUsage is 1 as strategic" do
    assert_equal "strategic", resource_usages["RESOURCE_TEST_STRATEGIC"]
  end

  test "classifies a resource whose ResourceUsage is 2 as luxury" do
    assert_equal "luxury", resource_usages["RESOURCE_TEST_LUXURY"]
  end

  test "classifies a resource whose ResourceUsage is 0 as bonus" do
    assert_equal "bonus", resource_usages["RESOURCE_TEST_BONUS"]
  end

  test "maps a unit to the resource it requires, with cost" do
    assert_equal [ { "resource" => "RESOURCE_TEST_STRATEGIC", "cost" => 1 } ],
                 unit_resource_requirements["UNIT_TEST_ONE"]
  end

  # A unit can need more than one resource at once - Unit_ResourceQuantityRequirements
  # carries one row per (unit, resource) pair, not one row per unit.
  test "lists every resource a unit requires when it requires more than one" do
    reqs = unit_resource_requirements["UNIT_TEST_LITERAL"]

    assert_equal 2, reqs.size
    assert_includes reqs, { "resource" => "RESOURCE_TEST_STRATEGIC", "cost" => 2 }
    assert_includes reqs, { "resource" => "RESOURCE_TEST_LUXURY", "cost" => 1 }
  end

  test "omits a unit with no resource requirement" do
    refute unit_resource_requirements.key?("UNIT_TEST_NO_REQUIREMENT")
  end

  private

  def buildings = LekmodIdsExtractor.new(SOURCE_DIR).buildings
  def technologies = LekmodIdsExtractor.new(SOURCE_DIR).technologies
  def resource_usages = LekmodIdsExtractor.new(SOURCE_DIR).resource_usages
  def unit_resource_requirements = LekmodIdsExtractor.new(SOURCE_DIR).unit_resource_requirements
end
