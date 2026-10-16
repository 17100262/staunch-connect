module ApiStubs
  module Hubstaff
    HUBSTAFF = "https://api.hubstaff.com/v2".freeze
    HUBSTAFF_TOKEN_URL = "https://account.hubstaff.com/access_tokens".freeze

    # Every exchange rotates the refresh token, like the real API.
    def stub_hubstaff_token_refresh(rotated_to: "rotated-refresh-token", access_token: "hs-access-token", status: 200)
      stub_request(:post, HUBSTAFF_TOKEN_URL).to_return(
        status: status,
        body: { access_token: access_token, refresh_token: rotated_to, expires_in: 3600 }.to_json,
        headers: { "Content-Type" => "application/json" }
      )
    end

    def stub_hubstaff(path, body, status: 200)
      stub_request(:get, %r{\A#{Regexp.escape(HUBSTAFF)}#{Regexp.escape(path)}(\?.*)?\z})
        .to_return(status: status, body: body.to_json, headers: { "Content-Type" => "application/json" })
    end

    def stub_hubstaff_organizations(orgs = [ { "id" => 11, "name" => "Staunch" } ], status: 200)
      stub_hubstaff("/organizations", { organizations: orgs }, status: status)
    end

    def stub_hubstaff_projects(org_id = 11, projects = [ { "id" => 501, "name" => "Acme Website" }, { "id" => 502, "name" => "Other" } ])
      stub_hubstaff("/organizations/#{org_id}/projects", { projects: projects })
    end

    # `tracked` is seconds, as in Hubstaff's daily activities.
    def stub_hubstaff_daily_activities(org_id = 11, tracked_seconds: [ 3600, 5400 ])
      stub_hubstaff("/organizations/#{org_id}/activities/daily",
                    { daily_activities: tracked_seconds.map { |s| { "tracked" => s } }, pagination: {} })
    end
  end
end

RSpec.configure { |config| config.include ApiStubs::Hubstaff }
