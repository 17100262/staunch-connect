class Connection < ApplicationRecord
  # Sources whose data the app reads.
  DATA_SOURCES = %w[hubstaff clickup fathom].freeze
  # Plus the Anthropic API key that powers the AI Assistant (managed in Settings > Connectors).
  SOURCES = (DATA_SOURCES + %w[anthropic]).freeze

  # The API key saved in Settings, when the connection is set up.
  def self.anthropic_key
    connection = find_by(source: "anthropic")
    connection.credential.presence if connection&.connected?
  end

  encrypts :credential
  encrypts :access_token
  encrypts :webhook_secret

  enum :status, { disconnected: "disconnected", connected: "connected", error: "error", syncing: "syncing" }, default: "disconnected"

  validates :source, presence: true, inclusion: { in: SOURCES }, uniqueness: true
  validates :credential, presence: true
end
