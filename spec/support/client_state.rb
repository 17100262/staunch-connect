# The API clients keep class-level state between calls; reset it so specs stay independent.
RSpec.configure do |config|
  config.before do
    ClickupClient::STRUCTURE_CACHE.clear
    HubstaffClient::STRUCTURE_CACHE.clear
    MeetingAssistantTools.instance_variable_set(:@voyage_client, nil)

    # Rate-limit retries sleep up to 30s; make them instant.
    allow_any_instance_of(FathomClient).to receive(:sleep)
    allow_any_instance_of(VoyageClient).to receive(:sleep)
  end
end
