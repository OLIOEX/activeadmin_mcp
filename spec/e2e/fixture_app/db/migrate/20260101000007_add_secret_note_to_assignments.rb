class AddSecretNoteToAssignments < ActiveRecord::Migration[7.2]
  def change
    add_column :assignments, :secret_note, :string
  end
end
