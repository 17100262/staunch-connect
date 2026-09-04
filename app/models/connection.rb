class Connection < ApplicationRecord
  SOURCES = %w[hubstaff clickup].freeze

  encrypts :credential
  encrypts :access_token

  enum :status, { disconnected: "disconnected", connected: "connected", error: "error" }, default: "disconnected"

  validates :source, presence: true, inclusion: { in: SOURCES }, uniqueness: true
  validates :credential, presence: true
end
