class CreateChronicles < ActiveRecord::Migration[8.1]
  def change
    create_table :chronicles do |t|
      t.references :game, null: false, foreign_key: true
      t.string :model, null: false
      t.text :content, null: false
      t.jsonb :digest, null: false, default: {}
      t.text :prompt
      t.string :lekmod_version
      t.integer :input_tokens
      t.integer :output_tokens
      t.decimal :cost_usd, precision: 10, scale: 6

      t.timestamps
    end
  end
end
