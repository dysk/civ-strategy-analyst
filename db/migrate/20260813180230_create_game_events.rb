class CreateGameEvents < ActiveRecord::Migration[8.1]
  def change
    create_table :game_events do |t|
      t.references :game, null: false, foreign_key: true
      t.integer :seq, null: false
      t.integer :session_index, null: false
      t.integer :turn, null: false
      t.string :event_type, null: false
      t.string :civ
      t.jsonb :payload, null: false, default: {}

      t.timestamps
    end

    add_index :game_events, [ :game_id, :turn ]
    add_index :game_events, [ :game_id, :event_type ]
    add_index :game_events, [ :game_id, :civ ]
  end
end
