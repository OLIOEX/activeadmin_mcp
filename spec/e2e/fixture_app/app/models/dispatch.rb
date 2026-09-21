class Dispatch < ApplicationRecord
  belongs_to :author, optional: true

  # See the note in post.rb: Ransack 4 requires an explicit allowlist.
  def self.ransackable_attributes(_auth_object = nil)
    column_names
  end
end
