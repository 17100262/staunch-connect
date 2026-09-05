class ProjectMapping < ApplicationRecord
  has_many :invoices, dependent: :destroy

  validates :clickup_space_id, presence: true, uniqueness: true
  validates :hubstaff_project_id, presence: true
end
