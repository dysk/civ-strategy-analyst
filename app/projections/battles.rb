# Clusters of soldiers' deaths close together in time and near one city -
# a fight worth naming on its own, not merely counted into a war's tally.
# KeyMomentDetector#theatre already places a war's losses by city across its
# whole span; a battle is the same placement read over a short window
# instead, which is what turns "the war was fought at Delhi" into "the
# battle of Delhi, turn 205".
#
# Detection stays cheap and generous on purpose: every cluster past the
# turn-and-headcount floor comes back, one-sided or not, win or rout. Sizing
# a battle against the army it was drawn from - whether three dead was a
# scouting party or half an expedition - is ChronicleSpine's job, the same
# way it already weighs a captured city by CityValue rather than by this
# projection's say-so.
class Battles
  extend Projection

  # Judgment calls, pending more than four example games to check them
  # against. A siege can fall quiet for several turns at a time - a wall
  # retaken, a relief force marching up - and still be the same fight; six
  # turns of silence breaks it into two. Two deaths reads as an incident,
  # not yet a fight.
  WINDOW_STANDARD_TURNS = 6
  MIN_LOSSES = 3

  def initialize(game)
    @tiles = TileOwnership.for(game)
    @window = GameSpeed.for(game).turns(WINDOW_STANDARD_TURNS)
    @log = game.event_log
  end

  def all
    placed_losses.group_by { |loss| loss[:city] }
      .flat_map { |city, losses| clusters(city, losses) }
      .sort_by { |battle| battle[:turn] }
  end

  private

  # Exploded one row per named candidate, so a border hex it cannot settle
  # between two cities still reaches each of them - the same generosity
  # TileOwnership#candidates already extends to a war's theatre. A
  # barbarian horde is routine background noise rather than the fight
  # this projection means to surface, so its own deaths count for
  # nothing - though a civ's losses to one still do.
  def placed_losses
    @log.of_type("unit_lost").flat_map do |event|
      next [] if event.civ == WarCasualties::BARBARIANS
      next [] if WarCasualties.kind_of(event.payload["unit"]) == :civilian

      plot = event.payload.values_at("x", "y")
      next [] unless plot.all?

      cities = @tiles.candidates(plot, turn: event.turn)&.dig(:cities) || []
      cities.map { |city| { city: city, turn: event.turn, civ: event.civ } }
    end
  end

  def clusters(city, losses)
    losses.sort_by { |loss| loss[:turn] }
      .slice_when { |before, after| after[:turn] - before[:turn] > @window }
      .select { |cluster| cluster.size >= MIN_LOSSES }
      .map { |cluster| battle_for(city, cluster) }
  end

  def battle_for(city, cluster)
    { type: :battle, city: city, turn: cluster.first[:turn],
      from_turn: cluster.first[:turn], to_turn: cluster.last[:turn],
      casualties: cluster.each_with_object(Hash.new(0)) { |loss, tally| tally[loss[:civ]] += 1 } }
  end
end
