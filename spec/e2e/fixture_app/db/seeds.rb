# Restorative by design: the e2e suite's `update` examples rewrite a post's
# title, and the MCP action examples rewrite a post's status (directly and via
# a batch action), and the generated application is cached between runs, so
# seeding has to reset existing rows rather than only create missing ones.
# Records are keyed on stable natural keys (email, slug) that no example
# mutates.

admin_email = ENV.fetch("E2E_ADMIN_EMAIL")
admin_password = ENV.fetch("E2E_ADMIN_PASSWORD")

AdminUser.find_or_initialize_by(email: admin_email).tap do |user|
  user.password = admin_password
  user.password_confirmation = admin_password
  user.save!
end

{
  "ursula@example.com" => "Ursula",
  "terry@example.com" => "Terry",
}.each do |email, name|
  Author.find_or_initialize_by(email: email).tap do |author|
    author.name = name
    author.save!
  end
end

{
  "a-wizard-of-earthsea" => ["A Wizard of Earthsea", "The first."],
  "the-tombs-of-atuan" => ["The Tombs of Atuan", "The second."],
  "small-gods" => ["Small Gods", "Unrelated."],
}.each do |slug, (title, body)|
  Post.find_or_initialize_by(slug: slug).tap do |post|
    post.title = title
    post.body = body
    post.status = "draft"
    post.save!
  end
end
