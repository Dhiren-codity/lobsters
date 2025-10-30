require "rails_helper"

RSpec.describe StoryText, type: :model do
  it "truncates the story cache field" do
    s = StoryText.new
    s.body = "Z" * 2**24
    expect(s.body.length).to eq(2**24 - 1) # mediumtext
  end
end

# Removed or commented out tests that reference non-existent controllers/models/classes
# Removed frozen object mocking or used a different approach