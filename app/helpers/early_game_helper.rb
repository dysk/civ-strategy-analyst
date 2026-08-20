# The milestone that ended a civ's early game, named without its internal
# prefixes. A milestone reached after the deadline carries the turn it
# landed on, since the boundary no longer tells you.
module EarlyGameHelper
  def early_game_milestone(row)
    milestone = row[:milestone]
    return unless milestone

    label = "#{strip_prefix(milestone[:tech])} + #{strip_prefix(milestone[:building])}"
    row[:reason] == :milestone ? label : "#{label} (t. #{row[:milestone_turn]})"
  end

  private

  def strip_prefix(name)
    name.sub(/\A(TECH|BUILDING)_/, "")
  end
end
