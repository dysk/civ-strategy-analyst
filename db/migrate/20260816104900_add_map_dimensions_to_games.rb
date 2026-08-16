class AddMapDimensionsToGames < ActiveRecord::Migration[8.1]
  def change
    add_column :games, :map_width, :integer
    add_column :games, :map_height, :integer
  end
end
