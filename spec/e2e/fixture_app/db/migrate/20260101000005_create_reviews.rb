class CreateReviews < ActiveRecord::Migration[7.2]
  def change
    create_table :reviews do |t|
      t.references :post
      t.text :body
      t.string :status, default: "pending", null: false

      t.timestamps
    end
  end
end
