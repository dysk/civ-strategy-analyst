class AddUsageToAnalyses < ActiveRecord::Migration[8.1]
  def change
    add_column :analyses, :input_tokens, :integer
    add_column :analyses, :output_tokens, :integer
    add_column :analyses, :cost_usd, :decimal, precision: 10, scale: 6
  end
end
