require "capybara/rspec"
require "capybara/cuprite"

DOWNLOADS_PATH = Rails.root.join("tmp/downloads")

Capybara.default_max_wait_time = 5
# Icon-only buttons are named by aria-label (e.g. "Account menu").
Capybara.enable_aria_label = true
Capybara.save_path = Rails.root.join("tmp/capybara")

RSpec.configure do |config|
  config.before(:each, type: :system) do
    FileUtils.rm_rf(DOWNLOADS_PATH)
    FileUtils.mkdir_p(DOWNLOADS_PATH)

    # driven_by registers its own driver, so Cuprite's options go here rather than in register_driver.
    driven_by :cuprite, screen_size: [ 1400, 1000 ], options: {
      headless: ENV["HEADLESS"] != "0",
      js_errors: true,
      process_timeout: 20,
      timeout: 15,
      save_path: DOWNLOADS_PATH.to_s,
      browser_options: ENV["CI"] ? { "no-sandbox" => nil } : {}
    }
  end
end
