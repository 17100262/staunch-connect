class Invoice < ApplicationRecord
  belongs_to :project_mapping
  has_many :invoice_line_items, dependent: :destroy

  accepts_nested_attributes_for :invoice_line_items

  validates :month, presence: true, uniqueness: { scope: :project_mapping_id }
  validates :name, presence: true

  def total_amount
    invoice_line_items.sum(&:amount)
  end

  def total_estimate_hours
    invoice_line_items.sum { |item| item.estimate_hours || 0 }
  end
end
