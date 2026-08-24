class Game < ApplicationRecord
  has_many :players, dependent: :destroy
  has_many :game_events, dependent: :destroy
  has_many :analyses, dependent: :destroy

  validates :name, presence: true

  # Loaded once and held, so the projections built from this game all read
  # the same pass. A game instance that goes on to log more events - only
  # the importer does - must not be one that has already been projected.
  def event_log
    @event_log ||= EventLog.for(self)
  end

  # The projections built from this game, held under whatever key their
  # builder names - see Projection. Same lifetime rule as the log they read.
  def projection(key)
    @projections ||= {}
    @projections[key] ||= yield
  end
end
