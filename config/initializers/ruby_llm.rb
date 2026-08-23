RubyLLM.configure do |config|
  config.use_new_acts_as = true

  config.openai_api_key = ENV["OPENAI_API_KEY"]
  config.anthropic_api_key = ENV["ANTHROPIC_API_KEY"]

  # The gem ships its own registry, which ages with the gem: model ids
  # released since 1.16.0 are unknown to it, and an unknown id costs both
  # the call and the price it would have been recorded at. config/models.json
  # is ours, refreshed on demand — see the README.
  config.model_registry_file = Rails.root.join("config/models.json")

  config.default_model = ENV.fetch("CIV_ANALYST_MODEL", "claude-opus-5")
end
