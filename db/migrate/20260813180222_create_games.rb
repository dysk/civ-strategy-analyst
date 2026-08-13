class CreateGames < ActiveRecord::Migration[8.1]
  def change
    create_table :games do |t|
      t.string :name
      t.string :map_script
      t.string :map_size
      t.string :game_speed
      t.integer :max_turns
      t.string :start_era
      t.string :winner_civ
      t.string :victory_type
      t.boolean :completed, null: false, default: false

      t.timestamps
    end
  end
end
