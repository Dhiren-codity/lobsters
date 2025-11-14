# typed: false

require "rails_helper"

describe Comment do
  it "should get a short id" do
    c = create(:comment)

    expect(c.short_id).to match(/^\A[a-zA-Z0-9]{1,10}\z/)
  end

  describe "hat" do
    it "can't be worn if user doesn't have that hat" do
      comment = build(:comment, hat: build(:hat))
      comment.valid?
      expect(comment.errors[:hat]).to eq(["not wearable by user"])
    end

    it "can be one of the user's hats" do
      hat = create(:hat)
      user = hat.user
      comment = create(:comment, user: user, hat: hat)
      comment.valid?
      expect(comment.errors[:hat]).to be_empty
    end
  end

  it "validates the length of short_id" do
    comment = Comment.new(short_id: "01234567890")
    expect(comment).to_not be_valid
  end

  it "is not valid without a comment" do
    comment = Comment.new(comment: nil)
    expect(comment).to_not be_valid
  end

  it "validates the length of markeddown_comment" do
    comment = build(:comment, markeddown_comment: "a" * 16_777_216)
    expect(comment).to_not be_valid
  end

  it "extracts links from markdown" do
    c = Comment.new comment: "a [link](https://example.com)"

    # smoke test:
    expect(c.markeddown_comment).to eq("<p>a <a href=\"https://example.com\" rel=\"ugc\">link</a></p>\n")

    links = c.parsed_links
    expect(links.count).to eq(1)
    l = links.last
    expect(l.url).to eq("https://example.com")
    expect(l.title).to eq("link")
  end

  describe ".accessible_to_user" do
    it "when user is a moderator" do
      moderator = build(:user, :moderator)

      expect(Comment.accessible_to_user(moderator)).to eq(Comment.all)
    end

    it "when user does not a moderator" do
      user = build(:user)

      expect(Comment.accessible_to_user(user)).to eq(Comment.active)
    end
  end

  it "subtracts karma if mod intervenes" do
    author = create(:user)
    voter = create(:user)
    mod = create(:user, :moderator)
    c = create(:comment, user: author)
    expect {
      Vote.vote_thusly_on_story_or_comment_for_user_because(1, c.story_id, c.id, voter.id, nil)
    }.to change { author.reload.karma }.by(1)
    expect {
      c.delete_for_user(mod, "Troll")
    }.to change { author.reload.karma }.by(-4)
  end

  describe "speed limit" do
    let(:story) { create(:story) }
    let(:author) { create(:user) }

    it "is not enforced as a regular validation" do
      parent = create(:comment, story: story, user: author, created_at: 30.seconds.ago)
      c = Comment.new(
        user: author,
        story: story,
        parent_comment: parent,
        comment: "good times"
      )
      expect(c.valid?).to be true
    end

    it "is not enforced on top level, only replies" do
      create(:comment, story: story, user: author, created_at: 30.seconds.ago)
      c = Comment.new(
        user: author,
        story: story,
        comment: "good times"
      )
      expect(c.breaks_speed_limit?).to be false
    end

    it "limits within 2 minutes" do
      top = create(:comment, story: story, user: author, created_at: 90.seconds.ago)
      mid = create(:comment, story: story, parent_comment: top, created_at: 60.seconds.ago)
      c = Comment.new(
        user: author,
        story: story,
        parent_comment: mid,
        comment: "too fast"
      )
      expect(c.breaks_speed_limit?).to be_truthy
    end

    it "limits longer with flags" do
      top = create(:comment, story: story, user: author, created_at: 150.seconds.ago)
      mid = create(:comment, story: story, parent_comment: top, created_at: 60.seconds.ago)
      Vote.vote_thusly_on_story_or_comment_for_user_because(-1, story, mid, create(:user).id, "T")
      c = Comment.new(
        user: author,
        story: story,
        parent_comment: mid,
        comment: "too fast"
      )
      expect(c.breaks_speed_limit?).to be_truthy
    end

    it "has an extra message if author flagged a parent" do
      top = create(:comment, story: story, user: author, created_at: 200.seconds.ago)
      mid = create(:comment, story: story, parent_comment: top, created_at: 60.seconds.ago)
      Vote.vote_thusly_on_story_or_comment_for_user_because(-1, story, mid, author.id, "T")
      c = Comment.new(
        user: author,
        story: story,
        parent_comment: mid,
        comment: "too fast"
      )
      expect(c.breaks_speed_limit?).to be_truthy
      expect(c.errors[:comment].join(" ")).to include("You flagged")
    end

    it "doesn't limit slow responses" do
      top = create(:comment, story: story, user: author, created_at: 20.minutes.ago)
      mid = create(:comment, story: story, parent_comment: top, created_at: 60.seconds.ago)
      Vote.vote_thusly_on_story_or_comment_for_user_because(-1, story, mid, author.id, "T")
      c = Comment.new(
        user: author,
        story: story,
        parent_comment: mid,
        comment: "too fast"
      )
      expect(c.breaks_speed_limit?).to be false
    end
  end

  describe "confidence" do
    it "is low for flagged comments" do
      conf = Comment.new(score: -4, flags: 5).calculated_confidence
      expect(conf).to be < 0.3
    end

    it "it is high for upvoted comments" do
      conf = Comment.new(score: 100, flags: 0).calculated_confidence
      expect(conf).to be > 0.75
    end

    it "at the scame score, is higher for comments without flags" do
      upvoted = Comment.new(score: 10, flags: 0).calculated_confidence
      flagged = Comment.new(score: 10, flags: 4).calculated_confidence
      expect(upvoted).to be > flagged
    end
  end

  describe "confidence_order_path" do
    it "doesn't sort comments under the wrong parents when they haven't been voted on" do
      story = create(:story)
      a = create(:comment, story: story, parent_comment: nil)
      create(:comment, story: story, parent_comment: nil)
      c = create(:comment, story: story, parent_comment: a)
      sorted = Comment.story_threads(story)
      # don't care if a or b is first, just care that c is immediately after a
      # this uses each_cons to get each pair of records and ensures [a, c] appears
      relationships = sorted.map(&:id).to_a.each_cons(2).to_a
      expect(relationships).to include([a.id, c.id])
    end
  end

  describe "associations" do
    it { is_expected.to belong_to(:user) }
    it { is_expected.to belong_to(:story) }
    it { is_expected.to have_many(:votes).dependent(:delete_all) }
    it { is_expected.to belong_to(:parent_comment).optional(true) }
    it { is_expected.to have_one(:moderation).dependent(:destroy) }
    it { is_expected.to belong_to(:hat).optional(true) }
    it { is_expected.to have_many(:links).dependent(:destroy) }
    it { is_expected.to have_many(:incoming_links).class_name("Link").dependent(:destroy) }
    it { is_expected.to have_one(:notification) }
  end

  describe "additional validations" do
    it { is_expected.to validate_inclusion_of(:is_deleted).in_array([true, false]) }
    it { is_expected.to validate_inclusion_of(:is_moderated).in_array([true, false]) }
    it { is_expected.to validate_inclusion_of(:is_from_email).in_array([true, false]) }
    it { is_expected.to validate_presence_of(:confidence) }
    it { is_expected.to validate_presence_of(:confidence_order) }
    it { is_expected.to validate_presence_of(:flags) }
    it { is_expected.to validate_presence_of(:score) }
    it { is_expected.to validate_presence_of(:last_edited_at) }
  end

  describe "scopes" do
    it "deleted and not_deleted" do
      deleted = create(:comment, is_deleted: true)
      kept = create(:comment, is_deleted: false)
      expect(Comment.deleted).to include(deleted)
      expect(Comment.deleted).not_to include(kept)
      expect(Comment.not_deleted).to include(kept)
      expect(Comment.not_deleted).not_to include(deleted)
    end

    it "active excludes deleted and moderated" do
      active = create(:comment, is_deleted: false, is_moderated: false)
      moderated = create(:comment, is_moderated: true)
      deleted = create(:comment, is_deleted: true)
      expect(Comment.active).to include(active)
      expect(Comment.active).not_to include(moderated)
      expect(Comment.active).not_to include(deleted)
    end

    it "recent returns only comments from the last 6 months" do
      recent = create(:comment, created_at: 1.day.ago)
      old = create(:comment, created_at: 7.months.ago)
      expect(Comment.recent).to include(recent)
      expect(Comment.recent).not_to include(old)
    end
  end

  describe ".\/ (finder by short id)" do
    it "finds by short id" do
      c = create(:comment)
      expect(Comment./(c.short_id)).to eq(c)
    end

    it "raises when not found" do
      expect { Comment./("nope") }.to raise_error(ActiveRecord::RecordNotFound)
    end
  end

  describe "callbacks and initial attributes" do
    it "assigns depth 0 and a thread_id on top-level comments" do
      c = create(:comment, parent_comment: nil)
      expect(c.depth).to eq(0)
      expect(c.thread_id).to be_present
      expect(c.confidence_order.bytesize).to eq(3)
      expect(c.last_edited_at).to be_within(5.seconds).of(Time.current)
    end

    it "assigns depth and thread_id from parent on replies" do
      parent = create(:comment, parent_comment: nil)
      c = create(:comment, parent_comment: parent, story: parent.story)
      expect(c.depth).to eq(parent.depth + 1)
      expect(c.thread_id).to eq(parent.thread_id)
    end

    it "logs hat use when hat has modlog_use" do
      hat = create(:hat, modlog_use: true)
      user = hat.user
      c = create(:comment, user: user, hat: hat)
      m = c.moderation
      expect(m).to be_present
      expect(m.action).to eq("used #{hat.hat} hat")
      expect(m.moderator_user_id).to eq(user.id)
    end
  end

  describe "#comment= generates markdown" do
    it "sets markeddown_comment using Markdowner" do
      c = build(:comment)
      allow(Markdowner).to receive(:to_html).and_return("<p>hi</p>\n")
      c.comment = "hi"
      expect(c.markeddown_comment).to eq("<p>hi</p>\n")
    end
  end

  describe "#current_flagged? and #current_upvoted?" do
    let(:comment) { build(:comment) }

    it "detects current flagged vote" do
      comment.current_vote = { vote: -1 }
      expect(comment.current_flagged?).to be true
      expect(comment.current_upvoted?).to be false
    end

    it "detects current upvoted vote" do
      comment.current_vote = { vote: 1 }
      expect(comment.current_upvoted?).to be true
      expect(comment.current_flagged?).to be false
    end

    it "returns false when no current vote" do
      comment.current_vote = nil
      expect(comment.current_flagged?).to be false
      expect(comment.current_upvoted?).to be false
    end
  end

  describe "#depth_permits_reply?" do
    it "is false for unsaved comments" do
      expect(build(:comment).depth_permits_reply?).to be false
    end

    it "is true when below the maximum depth" do
      c = create(:comment, depth: Comment::MAX_DEPTH - 1)
      expect(c.depth_permits_reply?).to be true
    end

    it "is false when at or above the maximum depth" do
      c1 = create(:comment, depth: Comment::MAX_DEPTH)
      c2 = create(:comment, depth: Comment::MAX_DEPTH + 1)
      expect(c1.depth_permits_reply?).to be false
      expect(c2.depth_permits_reply?).to be false
    end
  end

  describe "#gone_text" do
    it "explains when moderated" do
      mod = create(:user, :moderator)
      c = create(:comment)
      c.delete_for_user(mod, "Off topic")
      expect(c.gone_text).to include("Comment removed by moderator")
      expect(c.gone_text).to include("Off topic")
      expect(c.gone_text).to include(mod.username)
    end

    it "explains when user is banned" do
      banned_user = create(:user, banned_at: Time.current)
      c = create(:comment, user: banned_user)
      c.update!(is_deleted: true)
      expect(c.gone_text).to eq("Comment from banned user removed")
    end

    it "defaults to author removed" do
      c = create(:comment, is_deleted: true)
      expect(c.gone_text).to eq("Comment removed by author")
    end
  end

  describe "edit/delete/flag permission helpers" do
    let(:author) { create(:user) }
    let(:moderator) { create(:user, :moderator) }

    describe "#has_been_edited?" do
      it "is true when last_edited_at is more than a minute after creation" do
        c = create(:comment, user: author, created_at: 10.minutes.ago, last_edited_at: 8.minutes.ago)
        expect(c.has_been_edited?).to be true
      end

      it "is false when edited within a minute" do
        c = create(:comment, user: author, created_at: 10.minutes.ago, last_edited_at: 10.minutes.ago + 30.seconds)
        expect(c.has_been_edited?).to be false
      end
    end

    describe "#is_deletable_by_user?" do
      it "allows moderators" do
        c = create(:comment)
        expect(c.is_deletable_by_user?(moderator)).to be true
      end

      it "allows author within deleteable window" do
        c = create(:comment, user: author, created_at: 1.day.ago)
        expect(c.is_deletable_by_user?(author)).to be true
      end

      it "denies author after deleteable window" do
        c = create(:comment, user: author, created_at: (Comment::DELETEABLE_DAYS + 1).days.ago)
        expect(c.is_deletable_by_user?(author)).to be false
      end

      it "denies other users" do
        c = create(:comment, user: author)
        expect(c.is_deletable_by_user?(create(:user))).to be false
      end
    end

    describe "#is_disownable_by_user?" do
      it "is true for author after deleteable window" do
        c = create(:comment, user: author, created_at: (Comment::DELETEABLE_DAYS + 1).days.ago)
        expect(c.is_disownable_by_user?(author)).to be true
      end

      it "is false before deleteable window" do
        c = create(:comment, user: author, created_at: 1.day.ago)
        expect(c.is_disownable_by_user?(author)).to be false
      end
    end

    describe "#is_flaggable?" do
      it "is true when within flaggable days and above min score" do
        c = create(:comment, created_at: 1.day.ago, score: 0)
        expect(c.is_flaggable?).to be true
      end

      it "is false when older than flaggable days" do
        c = create(:comment, created_at: (Comment::FLAGGABLE_DAYS + 1).days.ago, score: 0)
        expect(c.is_flaggable?).to be false
      end

      it "is false when score is at or below minimum" do
        c = create(:comment, created_at: 1.day.ago, score: Comment::FLAGGABLE_MIN_SCORE)
        expect(c.is_flaggable?).to be false
      end
    end

    describe "#is_editable_by_user?" do
      it "is true for author within edit window" do
        c = create(:comment, user: author, last_edited_at: Time.current)
        expect(c.is_editable_by_user?(author)).to be true
      end

      it "is false when gone" do
        c = create(:comment, user: author, is_deleted: true, last_edited_at: Time.current)
        expect(c.is_editable_by_user?(author)).to be false
      end

      it "is false after edit window" do
        c = create(:comment, user: author, last_edited_at: (Comment::MAX_EDIT_MINS + 10).minutes.ago)
        expect(c.is_editable_by_user?(author)).to be false
      end

      it "is false for non-author" do
        c = create(:comment, user: author)
        expect(c.is_editable_by_user?(create(:user))).to be false
      end
    end

    describe "#is_gone?" do
      it "is true when deleted" do
        c = create(:comment, is_deleted: true)
        expect(c.is_gone?).to be true
      end

      it "is true when moderated" do
        c = create(:comment, is_moderated: true)
        expect(c.is_gone?).to be true
      end

      it "is false otherwise" do
        c = create(:comment, is_deleted: false, is_moderated: false)
        expect(c.is_gone?).to be false
      end
    end

    describe "#is_undeletable_by_user?" do
      it "allows moderators" do
        c = create(:comment)
        expect(c.is_undeletable_by_user?(moderator)).to be true
      end

      it "allows author if not moderated" do
        c = create(:comment, user: author, is_moderated: false)
        expect(c.is_undeletable_by_user?(author)).to be true
      end

      it "denies author if moderated" do
        c = create(:comment, user: author, is_moderated: true)
        expect(c.is_undeletable_by_user?(author)).to be false
      end
    end
  end

  describe "#as_json" do
    let(:comment) { create(:comment, is_deleted: false, is_moderated: false) }

    before do
      allow(Routes).to receive(:comment_short_id_url).with(any_args).and_return("short_url")
      allow(Routes).to receive(:comment_target_url).with(any_args).and_return("target_url")
    end

    it "serializes expected fields for active comment" do
      json = comment.as_json
      expect(json[:short_id]).to eq(comment.short_id)
      expect(json[:is_deleted]).to be false
      expect(json[:is_moderated]).to be false
      expect(json[:comment]).to eq(comment.markeddown_comment)
      expect(json[:comment_plain]).to eq(comment.comment)
      expect(json[:parent_comment]).to be_nil
      expect(json[:commenting_user]).to eq(comment.user.username)
      expect(json[:short_id_url]).to eq("short_url")
      expect(json[:url]).to eq("target_url")
    end

    it "serializes gone text for deleted comment" do
      comment.update!(is_deleted: true)
      json = comment.as_json
      expect(json[:comment]).to include("<em>")
      expect(json[:comment_plain]).to eq(comment.gone_text)
    end
  end

  describe "#mailing_list_message_id" do
    it "includes type, id, email flag if present, timestamp, and domain" do
      c = create(:comment, is_from_email: true, created_at: Time.current)
      allow(Rails.application).to receive(:domain).and_return("test.local")
      expected_prefix = "comment.#{c.short_id}.email.#{c.created_at.to_i}"
      expect(c.mailing_list_message_id).to eq("#{expected_prefix}@test.local")
    end

    it "omits email flag when not from email" do
      c = create(:comment, is_from_email: false, created_at: Time.current)
      allow(Rails.application).to receive(:domain).and_return("test.local")
      expected_prefix = "comment.#{c.short_id}.#{c.created_at.to_i}"
      expect(c.mailing_list_message_id).to eq("#{expected_prefix}@test.local")
    end
  end

  describe "#parents" do
    it "returns all ancestors, oldest first" do
      story = create(:story)
      a = create(:comment, story: story)
      b = create(:comment, story: story, parent_comment: a)
      c = create(:comment, story: story, parent_comment: b)
      expect(c.parents).to eq([a, b])
    end

    it "works for unsaved replies" do
      story = create(:story)
      a = create(:comment, story: story)
      b = build(:comment, story: story, parent_comment: a)
      expect(b.parents).to eq([a])
    end
  end>

  describe "#plaintext_comment" do
    it "returns raw comment text" do
      c = build(:comment, comment: "hello <b>world</b>")
      expect(c.plaintext_comment).to eq("hello <b>world</b>")
    end
  end

  describe "record_initial_upvote (after_commit)" do
    it "creates an initial upvote by the author" do
      c = create(:comment)
      vote = c.votes.find_by(user: c.user)
      expect(vote).to be_present
      expect(vote.vote).to eq(1)
    end
  end

  describe "#show_score_to_user?" do
    let(:mod) { create(:user, :moderator) }

    it "shows score to moderators" do
      c = create(:comment)
      expect(c.show_score_to_user?(mod)).to be true
    end

    it "hides score on new near-zero comments" do
      c = create(:comment, created_at: Time.current, score: 0)
      expect(c.show_score_to_user?(create(:user))).to be false
    end

    it "shows score when out of hidden range" do
      c = create(:comment, created_at: Time.current, score: Comment::SCORE_RANGE_TO_HIDE.max + 1)
      expect(c.show_score_to_user?(create(:user))).to be true
    end

    it "hides score when viewer has flagged" do
      c = create(:comment, created_at: 2.days.ago, score: 10) # old enough but should still hide due to flag
      c.current_vote = { vote: -1 }
      expect(c.show_score_to_user?(create(:user))).to be false
    end
  end

  describe "#to_param" do
    it "returns short_id" do
      c = create(:comment)
      expect(c.to_param).to eq(c.short_id)
    end
  end

  describe "#recreate_links" do
    it "recreates links when comment changes" do
      c = create(:comment, comment: "before")
      expect(Link).to receive(:recreate_from_comment!).with(c)
      c.update!(comment: "after [x](https://example.com)")
    end
  end

  describe "#unassign_votes" do
    it "updates story cached columns after destroy" do
      c = create(:comment)
      story = c.story
      expect(story).to receive(:update_cached_columns).at_least(:once)
      c.destroy
    end
  end

  describe "creation validation: commenter hasn't flagged parent" do
    it "prevents replying to a comment flagged by the same user" do
      user = create(:user)
      parent = create(:comment)
      Vote.vote_thusly_on_story_or_comment_for_user_because(-1, parent.story_id, parent.id, user.id, "T")
      reply = build(:comment, user: user, story: parent.story, parent_comment: parent)
      expect(reply).not_to be_valid
      expect(reply.errors[:base].join).to include("flagged that comment")
    end
  end

  describe "#vote_summary_for_user and #vote_summary_for_moderator" do
    it "formats vote summaries" do
      c = build(:comment)
      summary = [
        OpenStruct.new(count: 2, reason_text: "Off-topic", usernames: "alice,bob"),
        OpenStruct.new(count: 1, reason_text: "Spam", usernames: "carol")
      ]
      c.vote_summary = summary
      expect(c.vote_summary_for_user).to eq("2 off-topic, 1 spam")
      expect(c.vote_summary_for_moderator).to eq("2 off-topic (alice,bob), 1 spam (carol)")
    end
  end

  describe "#undelete_for_user" do
    it "undeletes and unmoderates when a moderator restores another user's comment" do
      author = create(:user)
      mod = create(:user, :moderator)
      c = create(:comment, user: author)
      c.delete_for_user(mod, "Rule violation")
      expect(c.is_deleted).to be true
      expect(c.is_moderated).to be true

      c.undelete_for_user(mod)
      c.reload
      expect(c.is_deleted).to be false
      expect(c.is_moderated).to be false
      expect(c.moderation).to be_present
      expect(Moderation.where(comment_id: c.id, action: "undeleted comment")).to exist
    end
  end

  describe ".regenerate_markdown" do
    it "re-renders and persists markeddown_comment for all comments" do
      c1 = create(:comment, comment: "hello")
      c2 = create(:comment, comment: "world")
      allow(Markdowner).to receive(:to_html).and_return("<p>changed</p>\n")
      Comment.regenerate_markdown
      expect(c1.reload.markeddown_comment).to eq("<p>changed</p>\n")
      expect(c2.reload.markeddown_comment).to eq("<p>changed</p>\n")
    end
  end
end
