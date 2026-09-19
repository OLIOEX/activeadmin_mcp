class Post < ApplicationRecord
  # Ransack 4 refuses to filter on any attribute absent from this allowlist,
  # and the MCP `query` tool calls `ransack` directly rather than going
  # through an ActiveAdmin filter.
  def self.ransackable_attributes(_auth_object = nil)
    column_names
  end
end
