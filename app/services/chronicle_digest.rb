# What the chronicler is given: everything the analysis sees, plus the
# calendar that turns turns into years and the spine that decides which of
# those years the chronicle stops at.
class ChronicleDigest
  def initialize(game, lekmod_version: nil, lekmod_root: Rails.root.join("db/lekmod"))
    @game = game
    @lekmod_version = lekmod_version || game.lekmod_version
    @lekmod_root = lekmod_root
  end

  def call
    digest = analysis_digest

    digest.merge(
      metrics: with_souls(digest[:metrics]), calendar: calendar.series(last_turn), chronicle: chronicle
    )
  end

  private

  def analysis_digest
    DigestBuilder.new(@game, lekmod_version: @lekmod_version, lekmod_root: @lekmod_root).call
  end

  # Population points are of no use to a chronicler; the people behind them are.
  def with_souls(metrics)
    metrics.transform_values do |checkpoints|
      checkpoints.transform_values do |snapshot|
        souls = Demographics.new(population: snapshot["population"], cities: snapshot["cities"]).souls
        snapshot.merge("souls" => souls)
      end
    end
  end

  def chronicle
    { entries: entries, background: dated(spine.background), quiet_spans: quiet_spans }
  end

  def entries
    spine.entries.map do |entry|
      entry.merge(
        year: year_for(entry[:turn]), from_year: year_for(entry[:from_turn]),
        to_year: year_for(entry[:to_turn]), moments: dated(entry[:moments])
      )
    end
  end

  def quiet_spans
    spine.quiet_spans.map do |span|
      span.merge(from_year: year_for(span[:from_turn]), to_year: year_for(span[:to_turn]))
    end
  end

  def dated(moments)
    moments.map { |moment| moment.merge(year: year_for(moment[:turn])) }
  end

  def year_for(turn) = calendar.year_for(turn)

  def calendar = TurnCalendar.for(@game)

  def spine = ChronicleSpine.for(@game)

  def last_turn = @game.game_events.maximum(:turn).to_i
end
