class Assignment < ApplicationRecord
  # See the note in post.rb: Ransack 4 requires an explicit allowlist.
  def self.ransackable_attributes(_auth_object = nil)
    column_names
  end
end
