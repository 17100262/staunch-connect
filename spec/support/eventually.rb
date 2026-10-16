# expect { value }.to eventually_exist — polls a block until it returns something truthy (e.g. a download).
RSpec::Matchers.define :eventually_exist do
  supports_block_expectations

  match do |block|
    Timeout.timeout(Capybara.default_max_wait_time) do
      sleep 0.1 until block.call
      true
    end
  rescue Timeout::Error
    false
  end
end
