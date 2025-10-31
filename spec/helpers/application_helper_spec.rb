require 'rails_helper'

describe ApplicationHelper do
  describe "#avatar_img" do
    let(:user) { FactoryBot.create(:user, avatar_path: "/path/to/avatar", username: "testuser") }

    it "returns an image tag with the correct attributes" do
      result = helper.avatar_img(user, 50)
      expect(result).to include("img")
      expect(result).to include("src=\"/path/to/avatar\"")
      expect(result).to include("srcset=\"/path/to/avatar 1x, /path/to/avatar 2x\"")
      expect(result).to include("class=\"avatar\"")
      expect(result).to include("size=\"50x50\"")
      expect(result).to include("alt=\"testuser avatar\"")
      expect(result).to include("loading=\"lazy\"")
      expect(result).to include("decoding=\"async\"")
    end
  end

  describe "#errors_for" do
    let(:object) { double("Object", errors: double("Errors", blank?: false, count: 2, full_messages: ["Name can't be blank", "Email is invalid"])) }

    it "returns formatted error messages" do
      result = helper.errors_for(object)
      expect(result).to include("flash-error")
      expect(result).to include("2 errors prohibited this object from being saved")
      expect(result).to include("Name can't be blank")
      expect(result).to include("Email is invalid")
    end

    it "handles specific error message replacement" do
      allow(object.errors).to receive(:full_messages).and_return(["Comments is invalid"])
      result = helper.errors_for(object)
      expect(result).to include("Comment is missing")
    end
  end

  describe "#filtered_tags" do
    let(:user) { FactoryBot.create(:user, tag_filter_tags: ["tag1", "tag2"]) }

    it "returns user-specific tags if user is present" do
      assign(:user, user)
      expect(helper.filtered_tags).to eq(["tag1", "tag2"])
    end

    it "returns tags from cookies if user is not present" do
      allow(helper).to receive(:cookies).and_return({ "tag_filter" => "tag3,tag4" })
      expect(Tag).to receive(:where).with(tag: ["tag3", "tag4"]).and_return(["tag3", "tag4"])
      expect(helper.filtered_tags).to eq(["tag3", "tag4"])
    end
  end

  describe "#inline_avatar_for" do
    let(:viewer) { double("Viewer", show_avatars?: true) }
    let(:user) { FactoryBot.create(:user, avatar_path: "/path/to/avatar", username: "testuser") }

    it "returns a link to the user's avatar if viewer is present and shows avatars" do
      expect(helper.inline_avatar_for(viewer, user)).to include("a")
      expect(helper.inline_avatar_for(viewer, user)).to include("img")
    end

    it "returns nil if viewer is not present" do
      expect(helper.inline_avatar_for(nil, user)).to be_nil
    end

    it "returns nil if viewer does not show avatars" do
      allow(viewer).to receive(:show_avatars?).and_return(false)
      expect(helper.inline_avatar_for(viewer, user)).to be_nil
    end
  end

  describe "#link_to_different_page" do
    let(:request) { double("Request", path: "/current/page/1") }

    before do
      allow(helper).to receive(:request).and_return(request)
    end

    it "returns a link with the correct class when on a different page" do
      result = helper.link_to_different_page("Next", "/different/page/2")
      expect(result).to include("a")
      expect(result).to include("Next")
      expect(result).to include("href=\"/different/page/2\"")
      expect(result).to include("class=\"\"")
    end

    it "returns a link with the current_page class when on the same page" do
      result = helper.link_to_different_page("Current", "/current/page/1")
      expect(result).to include("a")
      expect(result).to include("Current")
      expect(result).to include("href=\"/current/page/1\"")
      expect(result).to include("class=\"current_page\"")
    end
  end

  describe "#link_post" do
    it "renders the link_post partial with the correct locals" do
      expect(helper).to receive(:render).with(partial: "helpers/link_post", locals: { button_label: "Submit", link: "/submit", class_name: nil, confirm: nil })
      helper.link_post("Submit", "/submit")
    end
  end

  describe "#possible_flag_warning" do
    let(:showing_user) { FactoryBot.create(:user) }
    let(:user) { FactoryBot.create(:user) }

    before do
      allow(helper).to receive(:self_or_mod).and_return(true)
      allow(helper).to receive(:time_interval).and_return({ param: "1m" })
    end

    it "renders the flag warning partial if conditions are met" do
      allow(Rails.env).to receive(:production?).and_return(true)
      allow(FlaggedCommenters).to receive_message_chain(:new, :check_list_for).and_return(true)
      expect(helper).to receive(:render).with(partial: "users/flag_warning", locals: { showing_user: showing_user, interval: { param: "1m" } })
      helper.possible_flag_warning(showing_user, user)
    end

    it "does not render the flag warning partial if not in production" do
      allow(Rails.env).to receive(:production?).and_return(false)
      expect(helper).not_to receive(:render)
      helper.possible_flag_warning(showing_user, user)
    end
  end

  describe "#tag_link" do
    let(:tag) { FactoryBot.create(:tag, tag: "ruby", css_class: "tag-class", description: "A programming language") }

    it "returns a link to the tag with the correct attributes" do
      allow(helper).to receive(:filtered_tags).and_return([])
      result = helper.tag_link(tag)
      expect(result).to include("a")
      expect(result).to include("href=\"/tags/ruby\"")
      expect(result).to include("class=\"tag-class\"")
      expect(result).to include("title=\"A programming language\"")
    end

    it "includes the filtered class if the tag is filtered" do
      allow(helper).to receive(:filtered_tags).and_return([tag])
      result = helper.tag_link(tag)
      expect(result).to include("class=\"tag-class filtered\"")
    end
  end

  describe "#how_long_ago_label" do
    let(:time) { Time.current }

    it "returns a time tag with the correct attributes" do
      result = helper.how_long_ago_label(time)
      expect(result).to include("time")
      expect(result).to include("title=\"#{time.strftime("%F %T")}\"")
      expect(result).to include("datetime=\"#{time.strftime("%F %T")}\"")
      expect(result).to include("data-at-unix=\"#{time.to_i}\"")
    end
  end

  describe "#how_long_ago_link" do
    let(:time) { Time.current }
    let(:url) { "https://example.com" }

    it "returns a link with the correct attributes" do
      result = helper.how_long_ago_link(url, time)
      expect(result).to include("a")
      expect(result).to include("href=\"#{url}\"")
      expect(result).to include("time")
    end
  end
end