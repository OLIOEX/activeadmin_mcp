class CreateAssignments < ActiveRecord::Migration[7.2]
  def change
    create_table :assignments do |t|
      t.string :name
      t.string :notes

      t.timestamps
    end
  end
end
