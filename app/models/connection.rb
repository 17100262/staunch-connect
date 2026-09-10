class Connection < ApplicationRecord
  SOURCES = %w[hubstaff clickup fathom].freeze

  encrypts :credential
  encrypts :access_token
  encrypts :webhook_secret

  enum :status, { disconnected: "disconnected", connected: "connected", error: "error", syncing: "syncing" }, default: "disconnected"

  validates :source, presence: true, inclusion: { in: SOURCES }, uniqueness: true
  validates :credential, presence: true
end
