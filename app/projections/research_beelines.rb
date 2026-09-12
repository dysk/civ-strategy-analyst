# Whether a civ reached a marker technology on a suspiciously short tech
# count - a beeline calibrated from play, not measured. docs/research-beelines.md.
#
# The tech count is `tech_researched` events crediting the civ, up to and
# including the marker's own turn. `tech_from_ruins` is not a second
# acquisition: it fires alongside `tech_researched` for a tech the civ
# already got that way, so counting both double-counts it.
class ResearchBeelines
  extend Projection

  MARKERS = [
    { marker: "crossbows", tech: "TECH_MACHINERY", band: { min: 15, max: 17 } },
    { marker: "universities", tech: "TECH_EDUCATION", band: { min: 16, max: 19 } },
    { marker: "frigates", tech: "TECH_NAVIGATION", band: { min: 26, max: 29 } },
    { marker: "public_schools", tech: "TECH_SCIENTIFIC_THEORY", band: { min: 32, max: 34 } },
    { marker: "artillery_cavalry", tech: "TECH_DYNAMITE", band: { min: 34, max: 36 } },
    { marker: "research_labs", tech: "TECH_PLASTIC", band: { min: 42, max: 42 } },
    { marker: "planes", tech: "TECH_FLIGHT", band: { min: 46, max: 47 } },
    { marker: "battleships", tech: "TECH_ELECTRONICS", band: { min: 49, max: 50 } },
    { marker: "landships", tech: "TECH_COMBUSTION", band: { min: 51, max: 52 } },
    { marker: "the_internet", tech: "TECH_INTERNET", band: { min: 57, max: 61 } },
    { marker: "stealth_bombers", tech: "TECH_STEALTH", band: { min: 63, max: 65 } }
  ].freeze

  def initialize(game)
    @game = game
    @log = game.event_log
  end

  # Every marker this civ ever reached, each carrying the tech count it
  # took to get there, the calibrated band, and the signed distance to it -
  # zero inside the band, negative early, positive late - so a near-miss
  # reads as a near-miss instead of vanishing.
  def markers_reached(civ)
    MARKERS.filter_map { |marker| entry(marker, civ) }
  end

  private

  def entry(marker, civ)
    reached = researched(civ).find { |e| e.payload["tech"] == marker[:tech] }
    return unless reached

    tech_count = researched(civ).count { |e| e.turn <= reached.turn }
    distance_to_band = distance(tech_count, marker[:band])

    { marker: marker[:marker], tech: marker[:tech], turn: reached.turn, tech_count: tech_count,
      band: marker[:band], rush: distance_to_band.zero?, distance_to_band: distance_to_band,
      snapshot_tech_count: snapshot_tech_count(civ, reached.turn) }
  end

  def distance(tech_count, band)
    return tech_count - band[:max] if tech_count > band[:max]
    return tech_count - band[:min] if tech_count < band[:min]

    0
  end

  def researched(civ) = @log.of_type("tech_researched").select { |e| e.payload["civs"]&.include?(civ) }

  def snapshot_tech_count(civ, turn)
    MetricSeries.for(@game).values("techs", civ).find { |t, _| t == turn }&.last
  end
end
