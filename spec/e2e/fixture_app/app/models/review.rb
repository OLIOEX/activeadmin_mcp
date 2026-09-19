class Review < ApplicationRecord
  belongs_to :post, optional: true

  validates :body, presence: true

  # See the note in post.rb: Ransack 4 requires an explicit allowlist.
  def self.ransackable_attributes(_auth_object = nil)
    column_names
  end
end
