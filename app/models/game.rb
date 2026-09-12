class Game < ApplicationRecord
  has_many :players, dependent: :destroy
  has_many :game_events, dependent: :destroy
  has_many :analyses, dependent: :destroy

  validates :name, presence: true

  PANGAEA = /pangaea|oval/i

  # Pangaea puts every player on one landmass with ocean at the map's edges,
  # so the seam the coordinates wrap across is neither a route an army can
  # march nor a place a border can reach: the world has a real east and west.
  def pangaea?
    map_script.to_s.match?(PANGAEA)
  end

  # The minor civilizations, named by the logger when the session started.
  # A log from before the logger named them lists none, and those games
  # never logged a city-state's cities either.
  def city_state_civs
    @city_state_civs ||= event_log.of_type("session_started")
      .flat_map { |event| Array(event.payload["city_states"]) }
      .filter_map { |city_state| city_state["civ"] }
      .to_set
  end

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
