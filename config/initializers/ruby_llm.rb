RubyLLM.configure do |config|
  config.openai_api_key = Rails.application.credentials.openai_api_key
end
