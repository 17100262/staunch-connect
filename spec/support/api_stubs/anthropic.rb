module ApiStubs
  module Anthropic
    MESSAGES_URL = "https://api.anthropic.com/v1/messages".freeze
    MODELS_URL = %r{\Ahttps://api\.anthropic\.com/v1/models(\?.*)?\z}

    def anthropic_text(text)
      { "type" => "text", "text" => text }
    end

    def anthropic_tool_use(name, input, id: "toolu_#{SecureRandom.hex(4)}")
      { "type" => "tool_use", "id" => id, "name" => name, "input" => input }
    end

    def anthropic_message(*content, stop_reason: nil)
      stop_reason ||= content.any? { |block| block["type"] == "tool_use" } ? "tool_use" : "end_turn"
      { "id" => "msg_#{SecureRandom.hex(4)}", "type" => "message", "role" => "assistant", "model" => AiAssistant::MODEL,
        "content" => content, "stop_reason" => stop_reason, "stop_sequence" => nil,
        "usage" => { "input_tokens" => 10, "output_tokens" => 10 } }
    end

    # Each call to the Messages API returns the next response in order.
    def stub_anthropic_messages(*responses)
      stub_request(:post, MESSAGES_URL).to_return(
        *responses.map { |body| { status: 200, body: body.to_json, headers: { "Content-Type" => "application/json" } } }
      )
    end

    def stub_anthropic_error(status:, message: "boom")
      stub_request(:post, MESSAGES_URL).to_return(
        status: status, headers: { "Content-Type" => "application/json" },
        body: { type: "error", error: { type: "api_error", message: message } }.to_json
      )
    end

    def stub_anthropic_models(status: 200)
      body = status == 200 ? { data: [], has_more: false, first_id: nil, last_id: nil } : { type: "error", error: { type: "authentication_error", message: "invalid x-api-key" } }
      stub_request(:get, MODELS_URL).to_return(status: status, body: body.to_json, headers: { "Content-Type" => "application/json" })
    end
  end
end

RSpec.configure { |config| config.include ApiStubs::Anthropic }
