class GameEvent < ApplicationRecord
  belongs_to :game

  validates :seq, presence: true, uniqueness: { scope: :game_id }
  validates :turn, presence: true
  validates :event_type, presence: true
end
