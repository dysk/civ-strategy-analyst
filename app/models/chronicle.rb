class Chronicle < ApplicationRecord
  belongs_to :game

  validates :model, presence: true
  validates :content, presence: true
end
