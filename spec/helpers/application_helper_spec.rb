require 'rails_helper'

describe ApplicationHelper do
  describe "#avatar_img" do
    let(:user) { double("User", avatar_path: "/path/to/avatar", username: "testuser") }

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

    it "handles specific error message kludge" do
      allow(object.errors).to receive(:full_messages).and_return(["Comments is invalid"])
      result = helper.errors_for(object)
      expect(result).to include("Comment is missing")
    end
  end

  describe "#filtered_tags" do
    let(:user) { double("User", tag_filter_tags: ["tag1", "tag2"]) }

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
    let(:user) { double("User", avatar_path: "/path/to/avatar", username: "testuser") }

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
    before do
      allow(helper).to receive(:request).and_return(double("Request", path: "/current/page"))
    end

    it "adds current_page class if the path matches the current path" do
      result = helper.link_to_different_page("Link", "/current/page")
      expect(result).to include("class=\"current_page\"")
    end

    it "does not add current_page class if the path does not match the current path" do
      result = helper.link_to_different_page("Link", "/different/page")
      expect(result).not_to include("class=\"current_page\"")
    end
  end

  describe "#link_post" do
    it "renders the link_post partial with correct locals" do
      expect(helper).to receive(:render).with(partial: "helpers/link_post", locals: { button_label: "Label", link: "/link", class_name: nil, confirm: nil })
      helper.link_post("Label", "/link")
    end
  end

  describe "#possible_flag_warning" do
    let(:showing_user) { double("User") }
    let(:user) { double("User") }

    it "renders dev_flag_warning partial in non-production environments" do
      allow(Rails).to receive(:env).and_return(ActiveSupport::StringInquirer.new("development"))
      expect(helper).to receive(:render).with(partial: "users/dev_flag_warning")
      helper.possible_flag_warning(showing_user, user)
    end

    it "renders flag_warning partial if user is flagged" do
      allow(Rails).to receive(:env).and_return(ActiveSupport::StringInquirer.new("production"))
      allow(helper).to receive(:self_or_mod).and_return(true)
      allow(FlaggedCommenters).to receive_message_chain(:new, :check_list_for).and_return(true)
      expect(helper).to receive(:render).with(partial: "users/flag_warning", locals: { showing_user: showing_user, interval: anything })
      helper.possible_flag_warning(showing_user, user)
    end
  end

  describe "#tag_link" do
    let(:tag) { double("Tag", tag: "tag_name", css_class: "tag_class", description: "Tag description") }

    it "returns a link to the tag with correct attributes" do
      allow(helper).to receive(:filtered_tags).and_return([])
      result = helper.tag_link(tag)
      expect(result).to include("a")
      expect(result).to include("tag_name")
      expect(result).to include("tag_class")
      expect(result).to include("title=\"Tag description\"")
    end

    it "adds filtered class if tag is in filtered_tags" do
      allow(helper).to receive(:filtered_tags).and_return([tag])
      result = helper.tag_link(tag)
      expect(result).to include("filtered")
    end
  end

  describe "#how_long_ago_label" do
    let(:time) { Time.now }

    it "returns a time tag with correct attributes" do
      result = helper.how_long_ago_label(time)
      expect(result).to include("time")
      expect(result).to include("title=\"#{time.strftime("%F %T")}\"")
      expect(result).to include("datetime=\"#{time.strftime("%F %T")}\"")
      expect(result).to include("data-at-unix=\"#{time.to_i}\"")
    end
  end

  describe "#how_long_ago_link" do
    let(:time) { Time.now }
    let(:url) { "http://example.com" }

    it "returns a link with a time label" do
      result = helper.how_long_ago_link(url, time)
      expect(result).to include("a")
      expect(result).to include("href=\"#{url}\"")
      expect(result).to include("time")
    end
  end
end