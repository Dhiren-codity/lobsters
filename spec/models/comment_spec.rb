# typed: false

require 'rails_helper'

describe Comment do
  it 'should get a short id' do
    c = create(:comment)

    expect(c.short_id).to match(/^\A[a-zA-Z0-9]{1,10}\z/)
  end

  describe 'hat' do
    it "can't be worn if user doesn't have that hat" do
      comment = build(:comment, hat: build(:hat))
      comment.valid?
      expect(comment.errors[:hat]).to eq(['not wearable by user'])
    end

    it "can be one of the user's hats" do
      hat = create(:hat)
      user = hat.user
      comment = create(:comment, user: user, hat: hat)
      comment.valid?
      expect(comment.errors[:hat]).to be_empty
    end
  end

  it 'validates the length of short_id' do
    comment = Comment.new(short_id: '01234567890')
    expect(comment).to_not be_valid
  end

  it 'is not valid without a comment' do
    comment = Comment.new(comment: nil)
    expect(comment).to_not be_valid
  end

  it 'validates the length of markeddown_comment' do
    comment = build(:comment, markeddown_comment: 'a' * 16_777_216)
    expect(comment).to_not be_valid
  end

  it 'extracts links from markdown' do
    c = Comment.new comment: 'a [link](https://example.com)'

    # smoke test:
    expect(c.markeddown_comment).to eq("<p>a <a href=\"https://example.com\" rel=\"ugc\">link</a></p>\n")

    links = c.parsed_links
    expect(links.count).to eq(1)
    l = links.last
    expect(l.url).to eq('https://example.com')
    expect(l.title).to eq('link')
  end

  describe '.accessible_to_user' do
    it 'when user is a moderator' do
      moderator = build(:user, :moderator)

      expect(Comment.accessible_to_user(moderator)).to eq(Comment.all)
    end

    it 'when user does not a moderator' do
      user = build(:user)

      expect(Comment.accessible_to_user(user)).to eq(Comment.active)
    end
  end

  it 'subtracts karma if mod intervenes' do
    author = create(:user)
    voter = create(:user)
    mod = create(:user, :moderator)
    c = create(:comment, user: author)
    expect do
      Vote.vote_thusly_on_story_or_comment_for_user_because(1, c.story_id, c.id, voter.id, nil)
    end.to change { author.reload.karma }.by(1)
    expect do
      c.delete_for_user(mod, 'Troll')
    end.to change { author.reload.karma }.by(-4)
  end

  describe 'speed limit' do
    let(:story) { create(:story) }
    let(:author) { create(:user) }

    it 'is not enforced as a regular validation' do
      parent = create(:comment, story: story, user: author, created_at: 30.seconds.ago)
      c = Comment.new(
        user: author,
        story: story,
        parent_comment: parent,
        comment: 'good times'
      )
      expect(c.valid?).to be true
    end

    it 'is not enforced on top level, only replies' do
      create(:comment, story: story, user: author, created_at: 30.seconds.ago)
      c = Comment.new(
        user: author,
        story: story,
        comment: 'good times'
      )
      expect(c.breaks_speed_limit?).to be false
    end

    it 'limits within 2 minutes' do
      top = create(:comment, story: story, user: author, created_at: 90.seconds.ago)
      mid = create(:comment, story: story, parent_comment: top, created_at: 60.seconds.ago)
      c = Comment.new(
        user: author,
        story: story,
        parent_comment: mid,
        comment: 'too fast'
      )
      expect(c.breaks_speed_limit?).to be_truthy
    end

    it 'limits longer with flags' do
      top = create(:comment, story: story, user: author, created_at: 150.seconds.ago)
      mid = create(:comment, story: story, parent_comment: top, created_at: 60.seconds.ago)
      Vote.vote_thusly_on_story_or_comment_for_user_because(-1, story, mid, create(:user).id, 'T')
      c = Comment.new(
        user: author,
        story: story,
        parent_comment: mid,
        comment: 'too fast'
      )
      expect(c.breaks_speed_limit?).to be_truthy
    end

    it 'has an extra message if author flagged a parent' do
      top = create(:comment, story: story, user: author, created_at: 200.seconds.ago)
      mid = create(:comment, story: story, parent_comment: top, created_at: 60.seconds.ago)
      Vote.vote_thusly_on_story_or_comment_for_user_because(-1, story, mid, author.id, 'T')
      c = Comment.new(
        user: author,
        story: story,
        parent_comment: mid,
        comment: 'too fast'
      )
      expect(c.breaks_speed_limit?).to be_truthy
      expect(c.errors[:comment].join(' ')).to include('You flagged')
    end

    it "doesn't limit slow responses" do
      top = create(:comment, story: story, user: author, created_at: 20.minutes.ago)
      mid = create(:comment, story: story, parent_comment: top, created_at: 60.seconds.ago)
      Vote.vote_thusly_on_story_or_comment_for_user_because(-1, story, mid, author.id, 'T')
      c = Comment.new(
        user: author,
        story: story,
        parent_comment: mid,
        comment: 'too fast'
      )
      expect(c.breaks_speed_limit?).to be false
    end
  end

  describe 'confidence' do
    it 'is low for flagged comments' do
      conf = Comment.new(score: -4, flags: 5).calculated_confidence
      expect(conf).to be < 0.3
    end

    it 'it is high for upvoted comments' do
      conf = Comment.new(score: 100, flags: 0).calculated_confidence
      expect(conf).to be > 0.75
    end

    it 'at the scame score, is higher for comments without flags' do
      upvoted = Comment.new(score: 10, flags: 0).calculated_confidence
      flagged = Comment.new(score: 10, flags: 4).calculated_confidence
      expect(upvoted).to be > flagged
    end
  end

  describe 'confidence_order_path' do
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

  describe '.regenerate_markdown' do
    it 'recomputes markeddown_comment without touching timestamps' do
      comment = create(:comment, comment: 'hello')
      original_updated_at = comment.updated_at

      expect(Markdowner).to receive(:to_html).with(comment.comment, as_of: comment.created_at).and_return('RENDERED')
      Comment.regenerate_markdown
      expect(comment.reload.markeddown_comment).to eq('RENDERED')
      expect(comment.updated_at).to eq(original_updated_at)
    end
  end

  describe '#as_json' do
    it 'includes rendered body and metadata for active comments' do
      comment = create(:comment, comment: 'hello world')
      allow(Routes).to receive(:comment_short_id_url).with(comment).and_return('http://x/short')
      allow(Routes).to receive(:comment_target_url).with(comment, true).and_return('http://x/full')

      json = comment.as_json
      expect(json[:short_id]).to eq(comment.short_id)
      expect(json[:comment]).to eq(comment.markeddown_comment)
      expect(json[:comment_plain]).to eq('hello world')
      expect(json[:commenting_user]).to eq(comment.user.username)
      expect(json[:short_id_url]).to eq('http://x/short')
      expect(json[:url]).to eq('http://x/full')
      expect(json[:parent_comment]).to be_nil
    end

    it 'returns gone text when moderated/deleted' do
      author = create(:user)
      mod = create(:user, :moderator)
      comment = create(:comment, user: author, comment: 'something')
      allow(Routes).to receive(:comment_short_id_url).with(comment).and_return('http://x/short')
      allow(Routes).to receive(:comment_target_url).with(comment, true).and_return('http://x/full')

      comment.delete_for_user(mod, 'Troll')
      json = comment.as_json
      expect(json[:is_moderated]).to be true
      expect(json[:comment]).to include('<em>')
      expect(json[:comment]).to include('Comment removed by moderator')
      expect(json[:comment]).to include('Troll')
      expect(json[:comment_plain]).to include('Comment removed by moderator')
    end
  end

  describe '#depth_permits_reply?' do
    it 'returns false for new records' do
      c = build(:comment)
      expect(c.depth_permits_reply?).to be false
    end

    it 'returns true when depth is less than MAX_DEPTH' do
      c = create(:comment)
      c.update_column(:depth, Comment::MAX_DEPTH - 1)
      expect(c.depth_permits_reply?).to be true
    end

    it 'returns false when depth is at or beyond MAX_DEPTH' do
      c = create(:comment)
      c.update_column(:depth, Comment::MAX_DEPTH)
      expect(c.depth_permits_reply?).to be false
    end
  end

  describe '#has_been_edited?' do
    it 'is false shortly after creation and true when edited later' do
      c = create(:comment)
      expect(c.has_been_edited?).to be false
      c.update_column(:last_edited_at, c.created_at + 2.minutes)
      expect(c.reload.has_been_edited?).to be true
    end
  end

  describe '#is_editable_by_user?' do
    it 'is true for author within edit window and not gone' do
      c = create(:comment)
      expect(c.is_editable_by_user?(c.user)).to be true
    end

    it 'is false if comment is deleted' do
      c = create(:comment, is_deleted: true)
      expect(c.is_editable_by_user?(c.user)).to be false
    end

    it 'is false when edit window has passed' do
      c = create(:comment)
      c.update_column(:last_edited_at, (Comment::MAX_EDIT_MINS + 1).minutes.ago)
      expect(c.is_editable_by_user?(c.user)).to be false
    end
  end

  describe '#is_flaggable?' do
    it 'is true for recent comments with score above minimum' do
      c = create(:comment, score: Comment::FLAGGABLE_MIN_SCORE + 1)
      expect(c.is_flaggable?).to be true
    end

    it 'is false for old comments' do
      c = create(:comment)
      c.update_column(:created_at, (Comment::FLAGGABLE_DAYS + 1).days.ago)
      expect(c.is_flaggable?).to be false
    end

    it 'is false when score is at or below minimum' do
      c = create(:comment, score: Comment::FLAGGABLE_MIN_SCORE)
      expect(c.is_flaggable?).to be false
    end
  end

  describe '#is_deletable_by_user?' do
    it 'allows moderators to delete' do
      mod = create(:user, :moderator)
      c = create(:comment)
      expect(c.is_deletable_by_user?(mod)).to be true
    end

    it 'allows authors to delete within the allowed window' do
      c = create(:comment)
      expect(c.is_deletable_by_user?(c.user)).to be true
    end

    it 'does not allow deletion by other users' do
      c = create(:comment)
      other = create(:user)
      expect(c.is_deletable_by_user?(other)).to be false
    end

    it 'does not allow authors to delete after the window' do
      c = create(:comment)
      c.update_column(:created_at, (Comment::DELETEABLE_DAYS + 1).days.ago)
      expect(c.is_deletable_by_user?(c.user)).to be false
    end
  end

  describe '#is_disownable_by_user?' do
    it 'is true when author and beyond deleteable window' do
      c = create(:comment)
      c.update_column(:created_at, (Comment::DELETEABLE_DAYS + 1).days.ago)
      expect(c.is_disownable_by_user?(c.user)).to be true
    end

    it 'is false for non-authors' do
      c = create(:comment)
      other = create(:user)
      c.update_column(:created_at, (Comment::DELETEABLE_DAYS + 1).days.ago)
      expect(c.is_disownable_by_user?(other)).to be false
    end
  end

  describe '#is_undeletable_by_user?' do
    it 'is true for moderators' do
      mod = create(:user, :moderator)
      c = create(:comment, is_deleted: true)
      expect(c.is_undeletable_by_user?(mod)).to be true
    end

    it 'is true for authors when not moderated' do
      c = create(:comment, is_deleted: true, is_moderated: false)
      expect(c.is_undeletable_by_user?(c.user)).to be true
    end

    it 'is false for authors when moderated' do
      c = create(:comment, is_deleted: true, is_moderated: true)
      expect(c.is_undeletable_by_user?(c.user)).to be false
    end
  end

  describe '#log_hat_use' do
    it 'creates a moderation log when a modlog hat is used' do
      user = create(:user)
      hat = create(:hat, user: user, modlog_use: true, hat: 'Wizard')
      c = create(:comment, user: user, hat: nil)

      c.hat = hat
      expect do
        c.log_hat_use
      end.to change { Moderation.count }.by(1)

      m = Moderation.order(:id).last
      expect(m.action).to eq('used Wizard hat')
      expect(m.moderator_user_id).to eq(user.id)
      expect(m.comment_id).to eq(c.id)
    end
  end

  describe '#record_initial_upvote' do
    it 'creates an upvote from the author and updates score' do
      c = create(:comment)
      c.votes.delete_all
      c.update_columns(score: 0, flags: 0)

      expect do
        c.record_initial_upvote
      end.to change { c.votes.count }.by(1)

      v = c.votes.last
      expect(v.user_id).to eq(c.user_id)
      expect(v.vote).to eq(1)
      expect(c.reload.score).to eq(1)
    end
  end

  describe '#mailing_list_message_id' do
    it 'builds the message id with domain and timestamp' do
      c = create(:comment)
      allow(Rails.application).to receive(:domain).and_return('lobste.rs')
      expect(c.mailing_list_message_id).to eq("comment.#{c.short_id}.#{c.created_at.to_i}@lobste.rs")
    end

    it "includes 'email' when comment is from email" do
      c = create(:comment, is_from_email: true)
      allow(Rails.application).to receive(:domain).and_return('lobste.rs')
      expect(c.mailing_list_message_id).to eq("comment.#{c.short_id}.email.#{c.created_at.to_i}@lobste.rs")
    end
  end

  describe '#parents' do
    it 'returns all ancestors oldest first' do
      story = create(:story)
      a = create(:comment, story: story, parent_comment: nil)
      b = create(:comment, story: story, parent_comment: a)
      c = create(:comment, story: story, parent_comment: b)

      expect(c.parents).to eq([a, b])
    end
  end

  describe '#plaintext_comment' do
    it 'returns the raw comment text' do
      c = create(:comment, comment: 'plain text')
      expect(c.plaintext_comment).to eq('plain text')
    end
  end

  describe '#show_score_to_user?' do
    it 'always shows to moderators' do
      mod = create(:user, :moderator)
      c = create(:comment, score: 0)
      expect(c.show_score_to_user?(mod)).to be true
    end

    it 'hides near-zero scores on fresh comments' do
      c = create(:comment, score: 1)
      viewer = create(:user)
      expect(c.show_score_to_user?(viewer)).to be false
    end

    it 'shows scores on old comments even if near-zero' do
      c = create(:comment, score: 1)
      c.update_column(:created_at, 3.days.ago)
      viewer = create(:user)
      expect(c.show_score_to_user?(viewer)).to be true
    end

    it 'shows scores when outside the hidden range' do
      c = create(:comment, score: 10)
      viewer = create(:user)
      expect(c.show_score_to_user?(viewer)).to be true
    end

    it 'hides scores when viewer has flagged' do
      c = create(:comment, score: 10)
      viewer = create(:user)
      c.current_vote = { vote: -1 }
      expect(c.show_score_to_user?(viewer)).to be false
    end
  end

  describe '#to_param' do
    it 'uses the short_id' do
      c = create(:comment)
      expect(c.to_param).to eq(c.short_id)
    end
  end

  describe 'validate_commenter_hasnt_flagged_parent' do
    it 'prevents replying to a comment the user flagged' do
      story = create(:story)
      user = create(:user)
      parent = create(:comment, story: story)

      Vote.vote_thusly_on_story_or_comment_for_user_because(-1, story, parent, user.id, 'T')
      reply = build(:comment, story: story, user: user, parent_comment: parent)

      expect(reply.valid?).to be false
      expect(reply.errors[:base]).to include("You've flagged that comment for the mods, so you can leave it for the mods.")
    end
  end

  describe '#vote_summary_for_user' do
    it 'renders a readable summary' do
      c = build(:comment)
      entry = Struct.new(:count, :reason_text, :usernames)
      c.vote_summary = [entry.new(3, 'Off-Topic', nil), entry.new(1, 'Spam', nil)]
      expect(c.vote_summary_for_user).to eq('3 off-topic, 1 spam')
    end
  end

  describe '#vote_summary_for_moderator' do
    it 'renders a readable summary with usernames' do
      c = build(:comment)
      entry = Struct.new(:count, :reason_text, :usernames)
      c.vote_summary = [entry.new(2, 'Troll', 'alice bob')]
      expect(c.vote_summary_for_moderator).to eq('2 troll (alice bob)')
    end
  end
end
