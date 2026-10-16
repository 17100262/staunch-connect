require "simplecov"
SimpleCov.start "rails" do
  enable_coverage :branch
  group "Services", "app/services"

  # Enforced on full CI runs only, so running a single spec file locally doesn't fail on coverage.
  if ENV["CI"]
    minimum_coverage line: 90, branch: 80
  end
end

require "spec_helper"
ENV["RAILS_ENV"] ||= "test"
require_relative "../config/environment"
abort("The Rails environment is running in production mode!") if Rails.env.production?
require "rspec/rails"
require "webmock/rspec"

Rails.root.glob("spec/support/**/*.rb").sort_by(&:to_s).each { |f| require f }

begin
  ActiveRecord::Migration.maintain_test_schema!
rescue ActiveRecord::PendingMigrationError => e
  abort e.to_s.strip
end

# No spec may reach a real API — every external call is stubbed in spec/support/api_stubs.
# Localhost stays open for Capybara's app server and headless Chrome.
WebMock.disable_net_connect!(allow_localhost: true)

RSpec.configure do |config|
  config.fixture_paths = [ Rails.root.join("spec/fixtures") ]
  config.use_transactional_fixtures = true
  config.infer_spec_type_from_file_location!
  config.filter_rails_from_backtrace!

  config.include FactoryBot::Syntax::Methods
  config.include ActiveSupport::Testing::TimeHelpers
  config.include ActiveJob::TestHelper
end

Shoulda::Matchers.configure do |config|
  config.integrate do |with|
    with.test_framework :rspec
    with.library :rails
  end
end
