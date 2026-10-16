class ProjectMapping < ApplicationRecord
  has_many :invoices, dependent: :restrict_with_error

  validates :clickup_space_id, presence: true
  validates :clickup_folder_id, uniqueness: true, allow_blank: true
  validates :clickup_space_id, uniqueness: true, if: -> { clickup_folder_id.blank? }
end
