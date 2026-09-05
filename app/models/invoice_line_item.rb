class InvoiceLineItem < ApplicationRecord
  belongs_to :invoice

  validates :title, presence: true

  def amount
    return 0 unless billable

    (hourly_rate || 0) * (estimate_hours || 0)
  end
end
