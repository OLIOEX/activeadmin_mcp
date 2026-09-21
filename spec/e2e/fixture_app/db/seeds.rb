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

# A resource registered without `permit_params`, so the write tools have
# something to refuse. Nothing mutates it: the examples that name it assert it
# is unchanged.
Tag.find_or_initialize_by(name: "fantasy").save!

# Written through the MCP tools by the examples covering a block-form
# permit_params, so seeded restoratively on a title no example rewrites. Two
# rows, so an example rewriting one can assert the other was left alone.
{
  "The Weekly Dispatch" => "Everything that happened.",
  "The Monthly Review" => "Everything that did not.",
}.each do |title, body|
  Newsletter.find_or_initialize_by(title: title).tap do |newsletter|
    newsletter.body = body
    newsletter.secret_note = "Not for the newsletter"
    newsletter.save!
  end
end

# Described but never written by the examples that name them: one carries a
# form block declaring no inputs, the other a form block naming an
# association with `for:`.
Bulletin.find_or_initialize_by(headline: "Library closed on Monday").save!

Dispatch.find_or_initialize_by(headline: "From the archives").tap do |dispatch|
  dispatch.author = Author.find_by(email: "ursula@example.com")
  dispatch.save!
end
