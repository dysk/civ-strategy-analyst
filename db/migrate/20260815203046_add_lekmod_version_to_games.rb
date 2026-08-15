class AddLekmodVersionToGames < ActiveRecord::Migration[8.1]
  def change
    add_column :games, :lekmod_version, :string
  end
end
