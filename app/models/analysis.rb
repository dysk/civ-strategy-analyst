class Analysis < ApplicationRecord
  belongs_to :game

  validates :model, presence: true
  validates :report, presence: true
end
