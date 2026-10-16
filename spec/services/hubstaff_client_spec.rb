RSpec.describe HubstaffClient do
  it "exchanges the refresh token, then calls the API with the access token" do
    token = stub_hubstaff_token_refresh.with(body: { "grant_type" => "refresh_token", "refresh_token" => "original" })
    orgs = stub_hubstaff_organizations.with(headers: { "Authorization" => "Bearer hs-access-token" })

    expect(described_class.new("original").verify!).to be(true)
    expect(token).to have_been_requested
    expect(orgs).to have_been_requested
  end

  it "keeps the rotated refresh token and new access token for the caller to persist" do
    stub_hubstaff_token_refresh(rotated_to: "rotated", access_token: "fresh")
    stub_hubstaff_organizations
    client = described_class.new("original")

    freeze_time do
      client.verify!

      expect(client).to have_attributes(refresh_token: "rotated", access_token: "fresh", access_token_expires_at: 1.hour.from_now)
    end
  end

  it "reuses a cached access token that is still valid" do
    token = stub_hubstaff_token_refresh
    stub_hubstaff_organizations
    client = described_class.new("rt", access_token: "cached", access_token_expires_at: 30.minutes.from_now)

    client.verify!

    expect(token).not_to have_been_requested
  end

  it "refreshes an access token about to expire" do
    token = stub_hubstaff_token_refresh
    stub_hubstaff_organizations

    described_class.new("rt", access_token: "old", access_token_expires_at: 30.seconds.from_now).verify!

    expect(token).to have_been_requested
  end

  it "raises AuthenticationError when the refresh token is rejected" do
    stub_hubstaff_token_refresh(status: 400)

    expect { described_class.new("bad").verify! }.to raise_error(described_class::AuthenticationError)
  end

  it "raises RequestError when the token endpoint fails" do
    stub_hubstaff_token_refresh(status: 500)

    expect { described_class.new("rt").verify! }.to raise_error(described_class::RequestError, /500/)
  end

  it "raises AuthenticationError when the API rejects the access token" do
    stub_hubstaff_token_refresh
    stub_hubstaff_organizations(status: 401)

    expect { described_class.new("rt").verify! }.to raise_error(described_class::AuthenticationError)
  end

  it "lists projects per organization" do
    stub_hubstaff_token_refresh
    stub_hubstaff_projects

    expect(described_class.new("rt").projects(11).map { |p| p["name"] }).to eq([ "Acme Website", "Other" ])
  end

  it "pages through daily activities for a project and date range" do
    stub_hubstaff_token_refresh
    first = stub_request(:get, "#{ApiStubs::Hubstaff::HUBSTAFF}/organizations/11/activities/daily")
      .with(query: { "date[start]" => "2026-09-01", "date[stop]" => "2026-09-30", "project_ids[]" => "501" })
      .to_return(body: { daily_activities: [ { tracked: 60 } ], pagination: { next_page_start_id: 7 } }.to_json)
    second = stub_request(:get, "#{ApiStubs::Hubstaff::HUBSTAFF}/organizations/11/activities/daily")
      .with(query: hash_including("page_start_id" => "7"))
      .to_return(body: { daily_activities: [ { tracked: 120 } ], pagination: {} }.to_json)

    activities = described_class.new("rt").daily_activities(organization_id: 11, project_id: 501, date_from: "2026-09-01", date_to: "2026-09-30")

    expect(activities.sum { |a| a["tracked"] }).to eq(180)
    expect([ first, second ]).to all(have_been_requested)
  end
end
