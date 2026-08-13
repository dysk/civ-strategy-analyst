RubyLLM.configure do |config|
  config.use_new_acts_as = true

  config.openai_api_key = ENV["OPENAI_API_KEY"]
  config.anthropic_api_key = ENV["ANTHROPIC_API_KEY"]

  config.default_model = ENV.fetch("CIV_ANALYST_MODEL", "gpt-4o-mini")
end
