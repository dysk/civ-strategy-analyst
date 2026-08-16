require "test_helper"

class LekmodReferenceTest < ActiveSupport::TestCase
  ROOT = Rails.root.join("test/support/lekmod")

  test "resolves an exact version match with no resolution note" do
    result = reference(version: "1.5").call

    assert_equal "1.5", result[:version]
    assert_nil result[:resolution_note]
  end

  test "falls back to the nearest older version and notes the discrepancy" do
    result = reference(version: "1.6", civs: [ "Chile" ]).call

    assert_equal "1.5", result[:version]
    assert_match(/1\.6/, result[:resolution_note])
    assert_match(/1\.5/, result[:resolution_note])
    assert_match(/v1\.5 text for Chile/, result[:civilizations]["Chile"])
  end

  test "returns no reference data when the requested version predates every snapshot" do
    result = reference(version: "0.5", civs: [ "Chile" ]).call

    assert_nil result[:version]
    assert result[:resolution_note].present?
    assert_equal({}, result[:civilizations])
    assert_equal({}, result[:policies])
    assert_equal({}, result[:beliefs])
    assert_equal({}, result[:resolutions])
    assert_nil result[:general_rules]
    assert_equal [], result[:unmatched_ids]
  end

  test "returns no reference data when no version is given" do
    result = reference(version: nil, civs: [ "Chile" ]).call

    assert_nil result[:version]
    assert result[:resolution_note].present?
    assert_equal({}, result[:civilizations])
    assert_equal [], result[:unmatched_ids]
  end

  test "extracts only the civilizations present in the roster, by exact civ name" do
    result = reference(version: "1.5", civs: [ "Vietnam" ]).call

    assert_equal [ "Vietnam" ], result[:civilizations].keys
    assert_match(/v1\.5 text for Vietnam/, result[:civilizations]["Vietnam"])
  end

  test "omits a roster civ that has no entry in the reference data" do
    result = reference(version: "1.5", civs: [ "Chile", "Atlantis" ]).call

    assert_equal [ "Chile" ], result[:civilizations].keys
  end

  test "extracts a policy entry by its explicit backtick ID" do
    result = reference(version: "1.5", policy_ids: [ "POLICY_ARISTOCRACY" ]).call

    assert_match(/\+15% Production towards Wonders/, result[:policies]["POLICY_ARISTOCRACY"])
  end

  test "extracts a belief entry by its explicit backtick ID" do
    result = reference(version: "1.5", belief_ids: [ "BELIEF_GOD_SEA" ]).call

    assert_match(/\+1 Faith and Culture from Fish/, result[:beliefs]["BELIEF_GOD_SEA"])
  end

  test "derives an ideology tenet's name from its ID when no explicit backtick ID is annotated" do
    result = reference(version: "1.5", policy_ids: [ "POLICY_ECONOMIC_UNION" ]).call

    assert_match(/\+5% gold for each Trade Route/, result[:policies]["POLICY_ECONOMIC_UNION"])
  end

  test "reports a policy ID that isn't found anywhere as unmatched" do
    result = reference(version: "1.5", policy_ids: [ "POLICY_DOES_NOT_EXIST" ]).call

    assert_equal({}, result[:policies])
    assert_equal [ "POLICY_DOES_NOT_EXIST" ], result[:unmatched_ids]
  end

  test "reports a belief ID that isn't found anywhere as unmatched" do
    result = reference(version: "1.5", belief_ids: [ "BELIEF_DOES_NOT_EXIST" ]).call

    assert_equal({}, result[:beliefs])
    assert_equal [ "BELIEF_DOES_NOT_EXIST" ], result[:unmatched_ids]
  end

  test "resolves a belief via ids.yml when neither an inline ID nor derivation from the ID matches" do
    result = reference(version: "1.5", belief_ids: [ "BELIEF_ZAKATT" ]).call

    assert_match(/\+8 Gold from the Palace/, result[:beliefs]["BELIEF_ZAKATT"])
    assert_equal [], result[:unmatched_ids]
  end

  test "resolves a belief whose bullet name carries a parenthetical qualifier" do
    result = reference(version: "1.5", belief_ids: [ "BELIEF_SYNAGOGUES" ]).call

    assert_match(/costs 130 Faith/, result[:beliefs]["BELIEF_SYNAGOGUES"])
    assert_equal [], result[:unmatched_ids]
  end

  test "reports an ID as unmatched when ids.yml has no bullet matching its display name" do
    result = reference(version: "1.5", belief_ids: [ "BELIEF_NOMATCH" ]).call

    assert_equal({}, result[:beliefs])
    assert_equal [ "BELIEF_NOMATCH" ], result[:unmatched_ids]
  end

  test "prefers an inline backtick ID annotation over a conflicting ids.yml entry" do
    result = reference(version: "1.5", policy_ids: [ "POLICY_ARISTOCRACY" ]).call

    assert_match(/\+15% Production towards Wonders/, result[:policies]["POLICY_ARISTOCRACY"])
    assert_equal [], result[:unmatched_ids]
  end

  test "resolves gracefully, without ids.yml, when the version predates that file" do
    result = reference(version: "1.0", belief_ids: [ "BELIEF_ZAKATT" ]).call

    assert_equal({}, result[:beliefs])
    assert_equal [ "BELIEF_ZAKATT" ], result[:unmatched_ids]
  end

  test "resolves a resolution's display name from ids.yml" do
    result = reference(version: "1.5", resolution_ids: [ "RESOLUTION_WORLDS_FAIR" ]).call

    assert_equal "World's Fair", result[:resolutions]["RESOLUTION_WORLDS_FAIR"]
    assert_equal [], result[:unmatched_ids]
  end

  test "reports a resolution ID with no ids.yml entry as unmatched" do
    result = reference(version: "1.5", resolution_ids: [ "RESOLUTION_DOES_NOT_EXIST" ]).call

    assert_equal({}, result[:resolutions])
    assert_equal [ "RESOLUTION_DOES_NOT_EXIST" ], result[:unmatched_ids]
  end

  test "resolves resolutions gracefully, without ids.yml, when the version predates that file" do
    result = reference(version: "1.0", resolution_ids: [ "RESOLUTION_WORLDS_FAIR" ]).call

    assert_equal({}, result[:resolutions])
    assert_equal [ "RESOLUTION_WORLDS_FAIR" ], result[:unmatched_ids]
  end

  test "returns the full general.md content verbatim" do
    result = reference(version: "1.5").call

    assert_match(/## World Wonders/, result[:general_rules])
    assert_match(/Stonehenge: unchanged\./, result[:general_rules])
  end

  private

  def reference(version:, civs: [], policy_ids: [], belief_ids: [], resolution_ids: [])
    LekmodReference.new(
      version, civs: civs, policy_ids: policy_ids, belief_ids: belief_ids,
      resolution_ids: resolution_ids, root: ROOT
    )
  end
end
