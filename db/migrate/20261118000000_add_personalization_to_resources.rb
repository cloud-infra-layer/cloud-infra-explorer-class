class AddPersonalizationToResources < ActiveRecord::Migration[8.1]
  def change
    add_column :resources, :pinned, :boolean, default: false, null: false
    add_column :resources, :hidden, :boolean, default: false, null: false
  end
end
