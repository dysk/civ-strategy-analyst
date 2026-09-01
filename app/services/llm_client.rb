# Thin adapter over RubyLLM so the services depend on a small, injectable
# interface instead of RubyLLM::Chat's full API.
class LlmClient
  Response = Struct.new(:content, :input_tokens, :output_tokens, :cost_usd, keyword_init: true)

  def call(model:, system_prompt:, input:)
    message = RubyLLM.chat(model: model).with_instructions(system_prompt).ask(input)
    cost = message.cost(model: model)

    Response.new(
      content: message.content,
      input_tokens: message.tokens&.input,
      output_tokens: message.tokens&.output,
      cost_usd: cost&.total
    )
  end
end
