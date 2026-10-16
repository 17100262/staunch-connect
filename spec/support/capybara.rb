require "capybara/rspec"
require "capybara/cuprite"

Capybara.register_driver(:cuprite) do |app|
  Capybara::Cuprite::Driver.new(
    app,
    window_size: [ 1400, 1000 ],
    headless: ENV["HEADLESS"] != "0",
    process_timeout: 20,
    timeout: 15,
    js_errors: true,
    browser_options: ENV["CI"] ? { "no-sandbox" => nil } : {}
  )
end

Capybara.default_max_wait_time = 5
Capybara.save_path = Rails.root.join("tmp/capybara")

RSpec.configure do |config|
  config.before(:each, type: :system) { driven_by :cuprite }
end
