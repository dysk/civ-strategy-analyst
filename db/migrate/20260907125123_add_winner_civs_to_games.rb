class AddWinnerCivsToGames < ActiveRecord::Migration[8.1]
  def change
    add_column :games, :winner_civs, :string, array: true
  end
end
