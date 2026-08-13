class Player < ApplicationRecord
  belongs_to :game

  validates :civ, presence: true, uniqueness: { scope: :game_id }
end
