module JsonFixtures
  # Parsed contents of spec/fixtures/files/<path>.json.
  def json_fixture(path)
    JSON.parse(Rails.root.join("spec/fixtures/files/#{path}.json").read)
  end
end

RSpec.configure { |config| config.include JsonFixtures }
