# typed: false

require "rails_helper"

describe ApplicationHelper do
  describe "excerpt_fragment_around_link" do
    it "strips HTML tags besides the link" do
      comment = create(:comment, comment: "I **love** [example](https://example.com) so much")
      expect(comment.markeddown_comment).to include("strong") # the double star
      excerpt = helper.excerpt_fragment_around_link(comment.markeddown_comment, "https://example.com")
      expect(excerpt).to_not include("strong")
      expect(excerpt).to start_with("I love")    # text before
      expect(excerpt).to include("example.com")  # link href
      expect(excerpt).to end_with("so much")     # text after
    end

    it "strips HTML tags wrapping the link" do
      comment = create(:comment, comment: "I **love [example](https://example.com)**")
      expect(comment.markeddown_comment).to include("strong") # the double star
      excerpt = helper.excerpt_fragment_around_link(comment.markeddown_comment, "https://example.com")
      expect(excerpt).to_not include("strong")
      expect(excerpt).to include("example.com")
    end

    it "excerpts even in multiple nesting" do
      comment = create(:comment, comment: "See:\n\n * an _[example](https://example.com)_")
      expect(comment.markeddown_comment).to include("<li>")
      expect(comment.markeddown_comment).to include("<em>")
      excerpt = helper.excerpt_fragment_around_link(comment.markeddown_comment, "https://example.com")
      expect(excerpt).to_not include("li")
      expect(excerpt).to_not include("em")
      expect(excerpt).to include("example.com")
    end

    it "displays a few words around links in comments" do
      comment = create(:comment, comment: "This reminds me of [a great site](https://example.com) with more info. #{Faker::Lorem.sentences(number: 30).join(" ")}")
      excerpt = helper.excerpt_fragment_around_link(comment.markeddown_comment, "https://example.com")
      expect(excerpt.split.length).to be < 20
    end

    it "strips unpaired, invalid HTML tags" do
      html = '<p>i <strong>love <a href="https://example.com">example</a></p>'
      excerpt = helper.excerpt_fragment_around_link(html, "https://example.com")
      expect(excerpt).to_not include("strong")
      expect(excerpt).to include("example.com")
    end

    it "returns the first few words if the link is not present" do
      html = "Hello world. #{Faker::Lorem.sentences(number: 30).join(" ")} Removed."
      excerpt = helper.excerpt_fragment_around_link(html, "https://example.com")
      expect(excerpt).to_not include("Removed")
      expect(excerpt).to start_with("Hello world")
    end
  end

  describe "#page_numbers_for_pagination" do
    it "returns the right number of pages" do
      expect(helper.page_numbers_for_pagination(10, 1))
        .to eq([1, 2, 3, 4, 5, 6, 7, 8, 9, 10])

      expect(helper.page_numbers_for_pagination(20, 1))
        .to eq([1, 2, 3, 4, 5, 6, 7, 8, 9, 10, 11, 12, 13, "...", 20])

      expect(helper.page_numbers_for_pagination(25, 1))
        .to eq([1, 2, 3, 4, 5, 6, 7, 8, 9, 10, 11, 12, 13, "...", 25])

      expect(helper.page_numbers_for_pagination(25, 10))
        .to eq([1, "...", 4, 5, 6, 7, 8, 9, 10, 11, 12, 13, 14, 15, 16, "...", 25])

      expect(helper.page_numbers_for_pagination(25, 20))
        .to eq([1, "...", 13, 14, 15, 16, 17, 18, 19, 20, 21, 22, 23, 24, 25])
    end
  end

  describe "#page_count" do
    it "returns the right number of pages" do
      expect(page_count(49, 50)).to eq(1)
      expect(page_count(50, 50)).to eq(1)
      expect(page_count(51, 50)).to eq(2)
      expect(page_count(99, 50)).to eq(2)
      expect(page_count(100, 50)).to eq(2)
    end
  end

  describe "comment_score_for_user" do
    let(:comment) { create(:comment, score: 4) }
    let(:user) { create(:user) }

    it "when user can see the score" do
      allow_any_instance_of(Comment).to receive(:show_score_to_user?).and_return(true)
      expect(helper.comment_score_for_user(comment, user)[:score_value]).to eq 4
    end

    it "when user cannot see the score" do
      allow_any_instance_of(Comment).to receive(:show_score_to_user?).and_return(false)
      expect(helper.comment_score_for_user(comment, user)[:score_value]).to eq "&nbsp;"
    end

    it "when user is moderator" do
      expect(helper.comment_score_for_user(comment, create(:user, :moderator))[:score_value]).to eq 4
    end

    it "when user can flag the comment" do
      allow_any_instance_of(User).to receive(:can_flag?).and_return(true)
      expect(helper.comment_score_for_user(comment, user)[:score_value]).to eq "~"
    end

    it "when no user" do
      expect(helper.comment_score_for_user(comment, nil)[:score_value]).to eq nil
    end

    it "when no comment" do
      expect(helper.comment_score_for_user(nil, user)[:score_value]).to eq nil
    end

    it "when score is 1000" do
      comment.update(score: 1000)
      expect(helper.comment_score_for_user(comment, user)[:score_value]).to eq 1000
      expect(helper.comment_score_for_user(comment, user)[:score_formatted]).to eq "1K"
    end
  end

  describe "#avatar_img" do
    it "builds an img tag with srcset, dimensions, alt and lazy-loading" do
      user = build(:user, username: "alice")
      allow(user).to receive(:avatar_path).with(32).and_return("/avatars/alice-32.png")
      allow(user).to receive(:avatar_path).with(64).and_return("/avatars/alice-64.png")

      html = helper.avatar_img(user, 32)
      expect(html).to include('src="/avatars/alice-32.png"')
      expect(html).to include('srcset="/avatars/alice-32.png 1x, /avatars/alice-64.png 2x"')
      expect(html).to include('class="avatar"')
      expect(html).to include('alt="alice avatar"')
      expect(html).to include('loading="lazy"')
      expect(html).to include('decoding="async"')
      expect(html).to include('width="32"')
      expect(html).to include('height="32"')
    end
  end

  describe "#errors_for" do
    it "renders a formatted error list with custom message for comments invalid" do
      errors = double(blank?: false, count: 2, full_messages: ["Name can't be blank", "Comments is invalid"])
      object = double(class: double(name: "Thing"), errors: errors)
      html = helper.errors_for(object)

      expect(html).to include('class="flash-error"')
      expect(html).to include("2 errors prohibited this thing from being saved")
      expect(html).to include("There were the problems with the following fields:")
      expect(html).to include("<li>Name can't be blank</li>")
      expect(html).to include("<li>Comment is missing</li>")
    end

    it "returns empty string when there are no errors" do
      errors = double(blank?: true)
      object = double(class: double(name: "Thing"), errors: errors)
      html = helper.errors_for(object)
      expect(html).to eq("")
    end
  end

  describe "#filtered_tags" do
    before { helper.instance_variable_set(:@_filtered_tags, nil) }

    it "returns user tag filter tags when @user is present" do
      t = create(:tag, tag: "ruby")
      user = double(tag_filter_tags: [t])
      helper.instance_variable_set(:@user, user)
      expect(helper.filtered_tags).to eq([t])
    end

    it "returns tags from cookie when @user is not present" do
      helper.instance_variable_set(:@user, nil)
      t1 = create(:tag, tag: "ruby")
      t2 = create(:tag, tag: "rails")
      cookies[ApplicationController::TAG_FILTER_COOKIE] = "ruby,rails"
      expect(helper.filtered_tags.map(&:id)).to match_array([t1.id, t2.id])
    end
  end }

  describe "#inline_avatar_for" do
    let(:user) { create(:user) }

    it "returns a link with avatar when viewer is nil" do
      allow(helper).to receive(:avatar_img).with(user, 16).and_return("IMG")
      html = helper.inline_avatar_for(nil, user)
      expect(html).to include(%(href="#{user_path(user)}"))
      expect(html).to include("IMG")
    end

    it "returns a link with avatar when viewer shows avatars" do
      viewer = double(show_avatars?: true)
      allow(helper).to receive(:avatar_img).with(user, 16).and_return("IMG")
      html = helper.inline_avatar_for(viewer, user)
      expect(html).to include(%(href="#{user_path(user)}"))
      expect(html).to include("IMG")
    end

    it "returns nil when viewer hides avatars" do
      viewer = double(show_avatars?: false)
      expect(helper.inline_avatar_for(viewer, user)).to be_nil
    end
  end

  describe "#link_to_different_page" do
    it "marks link as current when paths match after stripping page segment" do
      allow(helper).to receive(:request).and_return(double(path: "/posts/page/3"))
      html = helper.link_to_different_page("Posts", "/posts/page/2", class: "btn")
      # href path stripped to /posts and class includes current_page
      expect(html).to include('href="/posts"')
      expect(html).to include('class="btn current_page"')
    end

    it "does not mark as current when paths do not match" do
      allow(helper).to receive(:request).and_return(double(path: "/posts"))
      html = helper.link_to_different_page("Other", "/other", class: "btn")
      expect(html).to include('href="/other"')
      expect(html).to include('class="btn"')
      expect(html).not_to include('current_page')
    end
  end

  describe "#link_post" do
    it "renders the partial with defaults" do
      expect(helper).to receive(:render).with(
        partial: "helpers/link_post",
        locals: { button_label: "Delete", link: "/items/1", class_name: nil, confirm: nil }
      ).and_return("OK")
      expect(helper.link_post("Delete", "/items/1")).to eq("OK")
    end

    it "renders the partial with provided options" do
      expect(helper).to receive(:render).with(
        partial: "helpers/link_post",
        locals: { button_label: "Delete", link: "/items/1", class_name: "danger", confirm: "Are you sure?" }
      ).and_return("OK")
      expect(helper.link_post("Delete", "/items/1", class_name: "danger", confirm: "Are you sure?")).to eq("OK")
    end
  end

  describe "#tag (override)" do
    it "defaults to open tag true producing an opening tag" do
      expect(helper.tag(:div)).to eq("<div>")
    end
  end

  describe "#tag_link" do
    let(:tag_record) { create(:tag, tag: "ruby", css_class: "tag-ruby", description: "Ruby lang") }

    it "builds a link to the tag with classes and title" do
      allow(helper).to receive(:filtered_tags).and_return([])
      html = helper.tag_link(tag_record)
      expect(html).to include(%(href="#{tag_path(tag_record)}"))
      expect(html).to include(">ruby<")
      expect(html).to include('class="tag-ruby"')
      expect(html).to include('title="Ruby lang"')
      expect(html).not_to include("filtered")
    end

    it "includes filtered class when tag is filtered" do
      allow(helper).to receive(:filtered_tags).and_return([tag_record])
      html = helper.tag_link(tag_record)
      expect(html).to include('class="tag-ruby filtered"')
    end
  end

  describe "#how_long_ago_label" do
    it "renders a time element with proper attributes and content" do
      time = Time.at(1_700_000_000).in_time_zone
      allow(helper).to receive(:how_long_ago).with(time).and_return("x ago")
      html = helper.how_long_ago_label(time)
      at = time.strftime("%F %T")
      expect(html).to include("<time")
      expect(html).to include(">x ago</time>")
      expect(html).to include(%(title="#{at}"))
      expect(html).to include(%(datetime="#{at}"))
      expect(html).to include(%(data-at-unix="#{time.to_i}"))
    end
  end

  describe "#how_long_ago_link" do
    it "wraps the label in an anchor tag" do
      time = Time.at(1_700_000_000).in_time_zone
      allow(helper).to receive(:how_long_ago).with(time).and_return("just now")
      html = helper.how_long_ago_link("/path", time)
      expect(html).to include(%(href="/path"))
      expect(html).to include("<time")
      expect(html).to include(">just now</time>")
    end
  end

  describe "#possible_flag_warning" do
    let(:showing_user) { create(:user) }
    let(:user) { create(:user) }

    it "renders dev flag warning in non-production environments" do
      # In test env, production? is false
      expect(helper).to receive(:render).with(partial: "users/dev_flag_warning").and_return("DEV")
      expect(helper.possible_flag_warning(showing_user, user)).to eq("DEV")
    end

    context "in production" do
      before do
        allow(Rails).to receive(:env).and_return(ActiveSupport::StringInquirer.new("production"))
      end

      it "returns nil if user is not self or mod" do
        expect(helper).to receive(:self_or_mod).with(showing_user, user).and_return(false)
        expect(helper.possible_flag_warning(showing_user, user)).to be_nil
      end

      it "returns nil if user is self/mod but not flagged in interval" do
        expect(helper).to receive(:self_or_mod).with(showing_user, user).and_return(true)
        interval = { param: "1m" }
        expect(helper).to receive(:time_interval).with("1m").and_return(interval)
        checker = double(check_list_for: false)
        expect(FlaggedCommenters).to receive(:new).and_return(checker)
        expect(helper.possible_flag_warning(showing_user, user)).to be_nil
      end

      it "renders flag warning when flagged in interval" do
        expect(helper).to receive(:self_or_mod).with(showing_user, user).and_return(true)
        interval = { param: "1m" }
        expect(helper).to receive(:time_interval).with("1m").and_return(interval)
        checker = double(check_list_for: true)
        expect(FlaggedCommenters).to receive(:new).and_return(checker)
        expect(helper).to receive(:render).with(
          partial: "users/flag_warning",
          locals: { showing_user: showing_user, interval: interval }
        ).and_return("FLAG")
        expect(helper.possible_flag_warning(showing_user, user)).to eq("FLAG")
      end
    end
  end
end
