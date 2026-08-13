class CreateAnalyses < ActiveRecord::Migration[8.1]
  def change
    create_table :analyses do |t|
      t.references :game, null: false, foreign_key: true
      t.string :model, null: false
      t.text :report, null: false
      t.jsonb :digest, null: false, default: {}

      t.timestamps
    end
  end
end
