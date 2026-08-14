class AddPromptToAnalyses < ActiveRecord::Migration[8.1]
  def change
    add_column :analyses, :prompt, :text
  end
end
