class CreatePlayers < ActiveRecord::Migration[8.1]
  def change
    create_table :players do |t|
      t.references :game, null: false, foreign_key: true
      t.string :civ, null: false
      t.string :leader_name
      t.boolean :human, null: false, default: false
      t.string :handicap

      t.timestamps
    end
  end
end
