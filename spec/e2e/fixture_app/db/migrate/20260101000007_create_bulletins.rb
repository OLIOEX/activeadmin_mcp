class CreateBulletins < ActiveRecord::Migration[7.2]
  def change
    create_table :bulletins do |t|
      t.string :headline
      t.text :body

      t.timestamps
    end
  end
end
