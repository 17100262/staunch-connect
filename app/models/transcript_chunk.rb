class TranscriptChunk < ApplicationRecord
  belongs_to :meeting
  has_neighbors :embedding

  validates :source, inclusion: { in: %w[summary transcript] }
end
