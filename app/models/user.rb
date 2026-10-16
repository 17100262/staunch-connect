class User < ApplicationRecord
  has_secure_password
  has_many :sessions, dependent: :destroy
  has_many :ai_conversations, dependent: :destroy

  normalizes :email_address, with: ->(e) { e.strip.downcase }
  normalizes :name, :job_title, with: ->(v) { v.to_s.strip.presence }

  validates :email_address, presence: true, uniqueness: true, format: { with: URI::MailTo::EMAIL_REGEXP }

  PASSWORD_RULES = {
    "At least 12 characters" => /\A.{12,}\z/m,
    "At least one number" => /\d/,
    "At least one symbol" => /[^A-Za-z0-9\s]/
  }.freeze

  TIME_ZONES = {
    "Asia/Karachi" => "Pakistan Standard Time (GMT+5)",
    "Asia/Dubai" => "Gulf Standard Time (GMT+4)",
    "Europe/London" => "London (GMT+0)",
    "Europe/Berlin" => "Central European Time (GMT+1)",
    "America/New_York" => "Eastern Time (GMT-5)",
    "America/Chicago" => "Central Time (GMT-6)",
    "America/Los_Angeles" => "Pacific Time (GMT-8)"
  }.freeze

  def display_name
    name.presence || email_address.split("@").first.tr("._-", " ").split.map(&:capitalize).join(" ")
  end

  def first_name
    display_name.split.first
  end

  def initials
    display_name.split.first(2).map { |part| part[0] }.join.upcase
  end

  def time_zone_label
    TIME_ZONES[time_zone] || time_zone.presence || "Not set"
  end

  def self.password_problems(password)
    PASSWORD_RULES.reject { |_, rule| password.to_s.match?(rule) }.keys
  end
end
