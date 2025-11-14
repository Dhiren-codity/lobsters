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

  describe 'assign_initial_attributes' do
    it 'sets depth and thread_id for top-level comments' do
      story = create(:story)
      c = create(:comment, story: story, parent_comment: nil)
      expect(c.depth).to eq(0)
      expect(c.thread_id).to be_present
    end

    it 'sets depth and thread_id from parent for replies' do
      story = create(:story)
      parent = create(:comment, story: story, parent_comment: nil)
      child = create(:comment, story: story, parent_comment: parent)
      expect(child.depth).to eq(parent.depth + 1)
      expect(child.thread_id).to eq(parent.thread_id)
    end
  end

  describe '#depth_permits_reply?' do
    it 'returns false for new records' do
      expect(build(:comment).depth_permits_reply?).to be false
    end

    it 'returns false when at MAX_DEPTH' do
      c = create(:comment)
      c.update_columns(depth: Comment::MAX_DEPTH)
      expect(c.depth_permits_reply?).to be false
    end

    it 'returns true when below MAX_DEPTH' do
      c = create(:comment)
      c.update_columns(depth: Comment::MAX_DEPTH - 1)
      expect(c.depth_permits_reply?).to be true
    end
  end

  describe '#comment=' do
    it 'strips trailing whitespace and updates markeddown_comment' do
      c = build(:comment)
      allow(Markdowner).to receive(:to_html).and_return("<p>x</p>\n")
      c.comment = "test line  \n"
      expect(c.comment).to eq('test line')
      expect(c.markeddown_comment).to eq("<p>x</p>\n")
    end
  end

  describe '#gone_text' do
    it 'returns moderator removal text with reason and moderator name' do
      mod = create(:user, :moderator)
      c = create(:comment)
      c.delete_for_user(mod, 'Off-topic')
      expect(c.gone_text).to include('Comment removed by moderator')
      expect(c.gone_text).to include(mod.username)
      expect(c.gone_text).to include('Off-topic')
    end

    it 'returns author removal text when author deletes' do
      author = create(:user)
      c = create(:comment, user: author)
      c.delete_for_user(author)
      expect(c.gone_text).to eq('Comment removed by author')
    end

    it 'returns banned user removal text' do
      banned = create(:user, :banned)
      c = create(:comment, user: banned)
      expect(c.gone_text).to eq('Comment from banned user removed')
    end
  end

  describe '#has_been_edited?' do
    it 'returns false when edited within one minute' do
      c = create(:comment)
      c.update_columns(created_at: 2.minutes.ago, last_edited_at: 1.minute.ago + 10.seconds)
      expect(c.has_been_edited?).to be false
    end

    it 'returns true when edited after more than one minute' do
      c = create(:comment)
      c.update_columns(created_at: 3.minutes.ago, last_edited_at: 1.minute.ago)
      expect(c.has_been_edited?).to be true
    end
  end

  describe '#is_deletable_by_user?' do
    it 'allows moderators to delete' do
      mod = create(:user, :moderator)
      c = create(:comment)
      expect(c.is_deletable_by_user?(mod)).to be true
    end

    it 'allows author to delete within DELETEABLE_DAYS' do
      author = create(:user)
      c = create(:comment, user: author)
      c.update_columns(created_at: (Comment::DELETEABLE_DAYS - 1).days.ago)
      expect(c.is_deletable_by_user?(author)).to be true
    end

    it 'does not allow author to delete after DELETEABLE_DAYS' do
      author = create(:user)
      c = create(:comment, user: author)
      c.update_columns(created_at: (Comment::DELETEABLE_DAYS + 1).days.ago)
      expect(c.is_deletable_by_user?(author)).to be false
    end

    it 'does not allow other users to delete' do
      c = create(:comment)
      other = create(:user)
      expect(c.is_deletable_by_user?(other)).to be false
    end
  end

  describe '#is_disownable_by_user?' do
    it 'allows author to disown after DELETEABLE_DAYS' do
      author = create(:user)
      c = create(:comment, user: author)
      c.update_columns(created_at: (Comment::DELETEABLE_DAYS + 1).days.ago)
      expect(c.is_disownable_by_user?(author)).to be true
    end

    it 'does not allow author to disown before DELETEABLE_DAYS' do
      author = create(:user)
      c = create(:comment, user: author)
      c.update_columns(created_at: (Comment::DELETEABLE_DAYS - 1).days.ago)
      expect(c.is_disownable_by_user?(author)).to be false
    end

    it 'does not allow non-authors to disown' do
      c = create(:comment)
      other = create(:user)
      expect(c.is_disownable_by_user?(other)).to be false
    end
  end

  describe '#is_flaggable?' do
    it 'returns true for recent comments above minimum score' do
      c = create(:comment)
      expect(c.is_flaggable?).to be true
    end

    it 'returns false for old comments' do
      c = create(:comment)
      c.update_columns(created_at: (Comment::FLAGGABLE_DAYS + 1).days.ago)
      expect(c.is_flaggable?).to be false
    end

    it 'returns false for low score comments' do
      c = create(:comment)
      c.update_columns(score: Comment::FLAGGABLE_MIN_SCORE)
      expect(c.is_flaggable?).to be false
    end
  end

  describe '#is_editable_by_user?' do
    it 'returns true for author within edit window' do
      author = create(:user)
      c = create(:comment, user: author)
      c.update_columns(last_edited_at: Time.current - (Comment::MAX_EDIT_MINS - 5).minutes)
      expect(c.is_editable_by_user?(author)).to be true
    end

    it 'returns false outside edit window' do
      author = create(:user)
      c = create(:comment, user: author)
      c.update_columns(last_edited_at: Time.current - (Comment::MAX_EDIT_MINS + 5).minutes)
      expect(c.is_editable_by_user?(author)).to be false
    end

    it 'returns false if comment is gone' do
      author = create(:user)
      c = create(:comment, user: author, is_deleted: true)
      expect(c.is_editable_by_user?(author)).to be false
    end

    it 'returns false for non-author' do
      c = create(:comment)
      other = create(:user)
      expect(c.is_editable_by_user?(other)).to be false
    end
  end

  describe '#is_gone?' do
    it 'is true when deleted' do
      c = build(:comment, is_deleted: true)
      expect(c.is_gone?).to be true
    end

    it 'is true when moderated' do
      c = build(:comment, is_moderated: true)
      expect(c.is_gone?).to be true
    end

    it 'is false otherwise' do
      c = build(:comment, is_deleted: false, is_moderated: false)
      expect(c.is_gone?).to be false
    end
  end

  describe '#is_undeletable_by_user?' do
    it 'returns true for moderator' do
      mod = create(:user, :moderator)
      c = create(:comment)
      expect(c.is_undeletable_by_user?(mod)).to be true
    end

    it 'returns true for author when not moderated' do
      author = create(:user)
      c = create(:comment, user: author)
      expect(c.is_undeletable_by_user?(author)).to be true
    end

    it 'returns false for author when moderated' do
      author = create(:user)
      mod = create(:user, :moderator)
      c = create(:comment, user: author)
      c.delete_for_user(mod, 'Rule')
      expect(c.is_undeletable_by_user?(author)).to be false
    end

    it 'returns false for non-author' do
      c = create(:comment)
      other = create(:user)
      expect(c.is_undeletable_by_user?(other)).to be false
    end
  end

  describe '#log_hat_use' do
    it 'creates a moderation log entry when hat requires modlog' do
      hat = create(:hat, modlog_use: true)
      user = hat.user
      expect do
        create(:comment, user: user, hat: hat)
      end.to change(Moderation, :count).by(1)
      expect(Moderation.last.action).to include("used #{hat.hat} hat")
      expect(Moderation.last.moderator_user_id).to eq(user.id)
    end

    it 'does not create a moderation entry when hat does not require modlog' do
      hat = create(:hat, modlog_use: false)
      user = hat.user
      expect do
        create(:comment, user: user, hat: hat)
      end.to_not change(Moderation, :count)
    end
  end

  describe '#mailing_list_message_id' do
    it 'includes short_id, email indicator, timestamp, and domain' do
      c = create(:comment, is_from_email: true)
      allow(Rails.application).to receive(:domain).and_return('example.test')
      mid = c.mailing_list_message_id
      expect(mid).to include('comment')
      expect(mid).to include(c.short_id)
      expect(mid).to include('email')
      expect(mid).to include(c.created_at.to_i.to_s)
      expect(mid).to end_with('@example.test')
    end
  end

  describe '#parents' do
    it 'returns all ancestors oldest first' do
      story = create(:story)
      top = create(:comment, story: story, parent_comment: nil)
      mid = create(:comment, story: story, parent_comment: top)
      bottom = create(:comment, story: story, parent_comment: mid)
      expect(bottom.parents).to eq([top, mid])
      expect(mid.parents).to eq([top])
      expect(top.parents).to be_empty
    end
  end

  describe '#plaintext_comment' do
    it 'returns the raw comment text' do
      c = create(:comment, comment: 'Hello <b>world</b>')
      expect(c.plaintext_comment).to eq('Hello <b>world</b>')
    end
  end

  describe '#record_initial_upvote' do
    it 'creates an initial upvote from the author on create' do
      c = create(:comment)
      expect(Vote.where(comment: c, user: c.user, vote: 1)).to exist
    end
  end

  describe '#show_score_to_user?' do
    it 'always shows score to moderators' do
      mod = create(:user, :moderator)
      c = create(:comment)
      expect(c.show_score_to_user?(mod)).to be true
    end

    it 'hides score when viewer flagged the comment' do
      c = create(:comment)
      c.current_vote = { vote: -1 }
      expect(c.show_score_to_user?(create(:user))).to be false
    end

    it 'hides score for near-zero new comments' do
      c = create(:comment)
      c.update_columns(created_at: Time.current)
      expect(c.show_score_to_user?(create(:user))).to be false
    end

    it 'shows score for older comments' do
      c = create(:comment)
      c.update_columns(created_at: 37.hours.ago)
      expect(c.show_score_to_user?(create(:user))).to be true
    end

    it 'shows score for high-score comments even if new' do
      c = create(:comment)
      c.update_columns(score: 10)
      expect(c.show_score_to_user?(create(:user))).to be true
    end
  end

  describe '#to_param' do
    it 'returns short_id' do
      c = create(:comment)
      expect(c.to_param).to eq(c.short_id)
    end
  end

  describe '#recreate_links' do
    it 'recreates links when comment changes' do
      c = create(:comment, comment: 'one')
      allow(Link).to receive(:recreate_from_comment!)
      c.update!(comment: 'two [link](https://example.com)')
      expect(Link).to have_received(:recreate_from_comment!).with(c)
    end
  end

  describe '#unassign_votes' do
    it 'updates story cached columns after destroy' do
      allow_any_instance_of(Story).to receive(:update_cached_columns)
      c = create(:comment)
      expect_any_instance_of(Story).to receive(:update_cached_columns).at_least(:once)
      c.destroy
    end
  end

  describe '#validate_commenter_hasnt_flagged_parent' do
    it 'prevents replying to a comment flagged by the same user' do
      story = create(:story)
      author = create(:user)
      parent = create(:comment, story: story, user: create(:user))
      Vote.vote_thusly_on_story_or_comment_for_user_because(-1, story, parent, author.id, 'T')
      reply = build(:comment, story: story, user: author, parent_comment: parent, comment: 'reply')
      expect(reply.valid?).to be false
      expect(reply.errors[:base].join).to include('leave it for the mods')
    end
  end

  describe '#vote_summary_for_user' do
    it 'joins counts and reasons lowercased' do
      c = build(:comment)
      c.vote_summary = [OpenStruct.new(count: 2, reason_text: 'Troll')]
      expect(c.vote_summary_for_user).to eq('2 troll')
    end
  end

  describe '#vote_summary_for_moderator' do
    it 'includes usernames in summary' do
      c = build(:comment)
      c.vote_summary = [OpenStruct.new(count: 3, reason_text: 'Spam', usernames: 'alice,bob')]
      expect(c.vote_summary_for_moderator).to eq('3 spam (alice,bob)')
    end
  end

  describe '.regenerate_markdown' do
    it 'rebuilds markeddown_comment for all comments' do
      c = create(:comment, comment: 'original')
      c.update_columns(markeddown_comment: 'stale')
      allow_any_instance_of(Comment).to receive(:generated_markeddown_comment).and_return('fresh')
      Comment.regenerate_markdown
      expect(c.reload.markeddown_comment).to eq('fresh')
    end
  end

  describe '#as_json' do
    it 'serializes fields including urls and rendered/plain text' do
      c = create(:comment)
      allow(Routes).to receive(:comment_short_id_url).and_return('short_url')
      allow(Routes).to receive(:comment_target_url).and_return('target_url')

      json = c.as_json
      expect(json[:short_id]).to eq(c.short_id)
      expect(json[:parent_comment]).to be_nil
      expect(json[:comment]).to eq(c.markeddown_comment)
      expect(json[:comment_plain]).to eq(c.comment)
      expect(json[:commenting_user]).to eq(c.user.username)
      expect(json[:short_id_url]).to eq('short_url')
      expect(json[:url]).to eq('target_url')
    end

    it 'uses gone text when comment is deleted' do
      c = create(:comment, is_deleted: true)
      allow(Routes).to receive(:comment_short_id_url).and_return('short_url')
      allow(Routes).to receive(:comment_target_url).and_return('target_url')
      json = c.as_json
      expect(json[:comment]).to include('<em>')
      expect(json[:comment_plain]).to eq(c.gone_text)
    end
  end

  describe '#update_score_and_recalculate!' do
    it 'recalculates score and flags from votes' do
      c = create(:comment)
      u1 = create(:user)
      u2 = create(:user)
      Vote.vote_thusly_on_story_or_comment_for_user_because(1, c.story, c, u1.id, nil)
      Vote.vote_thusly_on_story_or_comment_for_user_because(-1, c.story, c, u2.id, 'T')
      c.update_score_and_recalculate!(0, 0)
      c.reload
      # initial author upvote + u1 upvote = 2 upvotes; flags = 1
      expect(c.score).to eq(2 - 1) # sum of votes per SQL is ups + downs
      expect(c.flags).to eq(1)
      expect(c.confidence).to be_between(0, 1)
    end
  end

  describe '#delete_for_user and #undelete_for_user' do
    it "marks as deleted and moderated when a moderator deletes another user's comment" do
      author = create(:user)
      mod = create(:user, :moderator)
      c = create(:comment, user: author)
      expect do
        c.delete_for_user(mod, 'Off-topic')
      end.to change(Moderation, :count).by(1)
      expect(c.is_deleted).to be true
      expect(c.is_moderated).to be true
      expect(Moderation.last.action).to eq('deleted comment')
      expect(Moderation.last.reason).to eq('Off-topic')
    end

    it 'does not set moderated when author deletes own comment' do
      author = create(:user)
      c = create(:comment, user: author)
      c.delete_for_user(author)
      expect(c.is_deleted).to be true
      expect(c.is_moderated).to be false
    end

    it 'can be undeleted and clears moderation when a moderator undeletes' do
      author = create(:user)
      mod = create(:user, :moderator)
      c = create(:comment, user: author)
      c.delete_for_user(mod, 'Rule')
      expect do
        c.undelete_for_user(mod)
      end.to change(Moderation, :count).by(1)
      expect(c.is_deleted).to be false
      expect(c.is_moderated).to be false
      expect(Moderation.last.action).to eq('undeleted comment')
    end
  end
end
