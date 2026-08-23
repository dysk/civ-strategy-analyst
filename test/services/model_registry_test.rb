require "test_helper"

# The registry decides two things: whether a model id resolves at all, and
# whether a run can be priced. A default the registry does not carry costs
# nothing at boot and everything at the first analysis.
class ModelRegistryTest < ActiveSupport::TestCase
  test "the default model resolves" do
    assert RubyLLM.models.find(RubyLLM.config.default_model)
  end

  test "the default model carries pricing, so analyses record what they cost" do
    model = RubyLLM.models.find(RubyLLM.config.default_model)

    assert_operator model.input_price_per_million, :>, 0
    assert_operator model.output_price_per_million, :>, 0
  end

  test "the registry knows the models worth comparing on a real game" do
    %w[claude-opus-5 claude-sonnet-5 claude-fable-5].each do |id|
      assert RubyLLM.models.find(id), "#{id} missing from the registry"
    end
  end
end
