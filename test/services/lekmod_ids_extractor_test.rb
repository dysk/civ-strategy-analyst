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
end
