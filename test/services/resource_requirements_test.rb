require "test_helper"

class ResourceRequirementsTest < ActiveSupport::TestCase
  ROOT = Rails.root.join("test/support/lekmod")
  RESOURCELESS_ROOT = Rails.root.join("test/support/lekmod_wonderless")

  test "knows a unit requires a resource from the catalogue" do
    assert requirements("1.5").requires?("UNIT_HORSEMAN", "RESOURCE_HORSE")
  end

  test "a unit does not require a resource absent from its catalogue entry" do
    assert_not requirements("1.5").requires?("UNIT_HORSEMAN", "RESOURCE_IRON")
  end

  test "a unit with no catalogue entry requires nothing" do
    assert_not requirements("1.5").requires?("UNIT_WORKER", "RESOURCE_HORSE")
  end

  test "knows a strategic resource from the catalogue" do
    assert requirements("1.5").strategic?("RESOURCE_HORSE")
  end

  test "a luxury resource is not strategic" do
    assert_not requirements("1.5").strategic?("RESOURCE_COCONUT")
  end

  # A unit's requirement and a resource's classification both outlive a
  # hotfix, so a snapshot taken before the catalogue existed is better
  # served by a later one - the same rule Wonders applies to buildings.yml.
  test "falls back to the newest snapshot that carries a catalogue" do
    assert requirements("2.3").strategic?("RESOURCE_HORSE")
    assert requirements("2.3").requires?("UNIT_HORSEMAN", "RESOURCE_HORSE")
  end

  test "without a catalogue anywhere, no resource is known to be strategic" do
    assert_not resourceless_requirements.strategic?("RESOURCE_HORSE")
  end

  test "without a catalogue anywhere, no unit is known to require a resource" do
    assert_not resourceless_requirements.requires?("UNIT_HORSEMAN", "RESOURCE_HORSE")
  end

  private

  def requirements(version) = ResourceRequirements.for(version, root: ROOT)
  def resourceless_requirements = ResourceRequirements.for("1.0", root: RESOURCELESS_ROOT)
end
