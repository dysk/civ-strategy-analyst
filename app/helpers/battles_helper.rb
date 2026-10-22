module BattlesHelper
  def casualty_tally(civ, lost, attackers)
    blamed = attackers[civ]
    return "#{civ}: #{lost}" if blamed.blank?

    "#{civ}: #{lost} (#{attacker_breakdown(blamed, lost).join(", ")})"
  end

  private

  def attacker_breakdown(blamed, lost)
    parts = blamed.sort.map { |attacker, count| "#{attacker}: #{count}" }
    unattributed = lost - blamed.values.sum
    parts << "unknown: #{unattributed}" if unattributed.positive?
    parts
  end
end
