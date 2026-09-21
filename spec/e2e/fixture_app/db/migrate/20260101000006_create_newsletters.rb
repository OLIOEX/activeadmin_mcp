class CreateNewsletters < ActiveRecord::Migration[7.2]
  def change
    create_table :newsletters do |t|
      t.string :title
      t.text :body
      t.string :secret_note

      t.timestamps
    end
  end
end
