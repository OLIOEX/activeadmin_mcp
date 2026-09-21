class CreateDispatches < ActiveRecord::Migration[7.2]
  def change
    create_table :dispatches do |t|
      t.references :author
      t.string :headline

      t.timestamps
    end
  end
end
