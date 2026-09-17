# How long the game actually took to play. `t_log` is the engine's own
# clock, in seconds, and it resets whenever a session does (see
# design-decisions.md in civ-narrative-logger), so a multi-session game's
# total is the sum of each session's own span rather than one subtraction
# across the whole log.
class GameDuration
  extend Projection

  def initialize(game)
    @events = game.event_log.all
  end

  def turns_played
    @events.map(&:turn).max
  end

  # nil for a log written before the logger recorded t_log at all, so the
  # view can leave the time out rather than claim a game took no time.
  def seconds_played
    return nil if timestamps_by_session.empty?

    timestamps_by_session.sum { |_, t_logs| t_logs.max - t_logs.min }
  end

  private

  def timestamps_by_session
    @events.filter_map { |event| [ event.session_index, event.payload["t_log"] ] if event.payload["t_log"] }
      .group_by(&:first)
      .transform_values { |pairs| pairs.map(&:last) }
  end
end
