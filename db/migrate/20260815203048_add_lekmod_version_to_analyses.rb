class AddLekmodVersionToAnalyses < ActiveRecord::Migration[8.1]
  def change
    add_column :analyses, :lekmod_version, :string
  end
end
