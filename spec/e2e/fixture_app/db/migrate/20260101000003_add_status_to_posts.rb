class AddStatusToPosts < ActiveRecord::Migration[7.2]
  def change
    add_column :posts, :status, :string, default: "draft", null: false
  end
end
