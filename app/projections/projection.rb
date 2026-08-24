# One projection per game.
#
# A projection reads the log and indexes it when it is built, and a single
# digest asks for the same ones over and over - the score series thirteen
# times. Going through the game means that work happens once.
module Projection
  def for(game) = game.projection(self) { new(game) }
end
