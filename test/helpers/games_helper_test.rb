require "test_helper"

class GamesHelperTest < ActionView::TestCase
  test "resource_name turns an internal resource key into its display name" do
    assert_equal "Horse", resource_name("RESOURCE_HORSE")
    assert_equal "Hidden Artifacts", resource_name("RESOURCE_HIDDEN_ARTIFACTS")
  end

  test "minor_civ_trait_name turns an internal trait key into its display name" do
    assert_equal "Mercantile", minor_civ_trait_name("MINOR_TRAIT_MERCANTILE")
  end

  test "minor_civ_personality_name turns an internal personality key into its display name" do
    assert_equal "Theocratic", minor_civ_personality_name("MINOR_CIV_PERSONALITY_THEOCRATIC")
  end
end
