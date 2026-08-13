class Game < ApplicationRecord
  has_many :players, dependent: :destroy
  has_many :game_events, dependent: :destroy
  has_many :analyses, dependent: :destroy

  validates :name, presence: true
end
