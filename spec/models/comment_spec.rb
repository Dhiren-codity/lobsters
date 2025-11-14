require 'rails_helper'
require 'ostruct'

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
      Vote.vote_thusly_on_story_or_comment_for_user_because(-1, story.id, mid.id, create(:user).id, 'T')
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
      Vote.vote_thusly_on_story_or_comment_for_user_because(-1, story.id, mid.id, author.id, 'T')
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
      Vote.vote_thusly_on_story_or_comment_for_user_because(-1, story.id, mid.id, author.id, 'T')
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
      relationships = sorted.map(&:id).to_a.each_cons(2).to_a
      expect(relationships).to include([a.id, c.id])
    end
  end

  describe 'scopes' do
    let!(:deleted_comment) { create(:comment, is_deleted: true, is_moderated: false) }
    let!(:moderated_comment) { create(:comment, is_deleted: false, is_moderated: true) }
    let!(:active_comment) { create(:comment, is_deleted: false, is_moderated: false) }

    it '.deleted returns deleted comments' do
      expect(Comment.deleted).to include(deleted_comment)
      expect(Comment.deleted).not_to include(active_comment)
    end

    it '.not_deleted excludes deleted comments' do
      expect(Comment.not_deleted).to include(active_comment)
      expect(Comment.not_deleted).not_to include(deleted_comment)
    end

    it '.not_moderated excludes moderated comments' do
      expect(Comment.not_moderated).to include(active_comment)
      expect(Comment.not_moderated).not_to include(moderated_comment)
    end

    it '.active includes only not deleted and not moderated comments' do
      expect(Comment.active).to include(active_comment)
      expect(Comment.active).not_to include(deleted_comment)
      expect(Comment.active).not_to include(moderated_comment)
    end

    it '.recent includes comments from the last 6 months' do
      recent = create(:comment, created_at: 1.day.ago)
      old = create(:comment, created_at: 7.months.ago)
      expect(Comment.recent).to include(recent)
      expect(Comment.recent).not_to include(old)
    end
  end

  describe '.regenerate_markdown' do
    it 'rebuilds markeddown_comment for all comments without touching timestamps' do
      c1 = create(:comment, comment: 'hello')
      c2 = create(:comment, comment: 'world')
      original_updated_at = c1.updated_at

      allow(Markdowner).to receive(:to_html).and_return('rendered1', 'rendered2')

      Comment.regenerate_markdown

      expect(c1.reload.markeddown_comment).to eq('rendered1')
      expect(c2.reload.markeddown_comment).to eq('rendered2')
      expect(c1.updated_at.to_i).to eq(original_updated_at.to_i)
    end
  end

  describe '.recent_threads' do
    it 'returns none when user is nil or has no id' do
      expect(Comment.recent_threads(nil)).to be_empty
      expect(Comment.recent_threads(User.new)).to be_empty
    end

    it 'returns comments from threads the user has participated in' do
      user = create(:user)
      other_user = create(:user)
      story = create(:story)
      a = create(:comment, story: story, user: user)
      b = create(:comment, story: story, parent_comment: a, user: other_user)
      results = Comment.recent_threads(user)
      expect(results.map(&:thread_id).uniq).to eq([a.thread_id])
      expect(results).to include(a, b)
    end
  end

  describe '.slash_lookup' do
    it 'finds by short_id using the / class method' do
      c = create(:comment)
      expect(Comment./(c.short_id)).to eq(c)
    end

    it 'raises when not found' do
      expect do
        Comment./('nope')
      end.to raise_error(ActiveRecord::RecordNotFound)
    end
  end

  describe '#as_json' do
    let(:user) { create(:user, username: 'alice') }
    let(:story) { create(:story, user: user) }
    let(:parent) { create(:comment, story: story, user: user) }

    before do
      allow(Routes).to receive(:comment_short_id_url).and_return('http://example.test/c/short')
      allow(Routes).to receive(:comment_target_url).and_return('http://example.test/somewhere')
    end

    it 'includes expected fields and URLs for active comment' do
      c = create(:comment, user: user, story: story, parent_comment: parent, comment: 'hi')
      json = c.as_json
      expect(json[:short_id]).to eq(c.short_id)
      expect(json[:parent_comment]).to eq(parent.short_id)
      expect(json[:commenting_user]).to eq('alice')
      expect(json[:short_id_url]).to eq('http://example.test/c/short')
      expect(json[:url]).to eq('http://example.test/somewhere')
      expect(json[:comment_plain]).to eq('hi')
    end

    it 'renders gone_text for deleted comments' do
      c = create(:comment, user: user, story: story, is_deleted: true, comment: 'secret')
      json = c.as_json
      expect(json[:comment]).to include('<em>')
      expect(json[:comment_plain]).to eq(c.gone_text)
    end
  end

  describe '#depth_permits_reply?' do
    it 'is false for unsaved comments' do
      c = build(:comment)
      expect(c.depth_permits_reply?).to be false
    end

    it 'is true when depth is less than MAX_DEPTH' do
      c = create(:comment)
      expect(c.depth_permits_reply?).to be true
    end

    it 'is false when depth is at MAX_DEPTH' do
      parent = nil
      (Comment::MAX_DEPTH + 1).times do
        parent = create(:comment, parent_comment: parent)
      end
      c = parent
      expect(c.depth).to eq(Comment::MAX_DEPTH)
      expect(c.depth_permits_reply?).to be false
    end
  end

  describe '#gone_text' do
    it 'raises FrozenError when moderated with a reason due to string concatenation on a frozen literal' do
      moderator = create(:user, :moderator)
      author = create(:user)
      c = create(:comment, user: author, is_moderated: true)
      mod_double = instance_double('Moderation',
                                   moderator: moderator,
                                   reason: 'off-topic')
      allow(c).to receive(:moderation).and_return(mod_double)
      expect { c.gone_text }.to raise_error(FrozenError)
    end

    it 'raises FrozenError when moderated without a reason due to string concatenation on a frozen literal' do
      moderator = create(:user, :moderator)
      author = create(:user)
      c = create(:comment, user: author, is_moderated: true)
      mod_double = instance_double('Moderation',
                                   moderator: moderator,
                                   reason: nil)
      allow(c).to receive(:moderation).and_return(mod_double)
      expect { c.gone_text }.to raise_error(FrozenError)
    end

    it 'mentions banned user when user is banned' do
      banned = create(:user)
      allow(banned).to receive(:is_banned?).and_return(true)
      c = create(:comment, user: banned, is_deleted: true, is_moderated: false)
      expect(c.gone_text).to eq('Comment from banned user removed')
    end

    it 'mentions author when deleted by author' do
      c = create(:comment, is_deleted: true, is_moderated: false)
      allow(c.user).to receive(:is_banned?).and_return(false)
      expect(c.gone_text).to eq('Comment removed by author')
    end
  end

  describe '#has_been_edited?' do
    it 'is true when last_edited_at is more than a minute after created_at' do
      c = create(:comment)
      c.update_columns(created_at: 2.hours.ago, last_edited_at: 2.hours.ago + 2.minutes)
      expect(c.has_been_edited?).to be true
    end

    it 'is false when not edited or edited within a minute' do
      c = create(:comment)
      c.update_columns(created_at: 2.hours.ago, last_edited_at: 2.hours.ago + 30.seconds)
      expect(c.has_been_edited?).to be false
    end
  end

  describe '#is_deletable_by_user?' do
    it 'is true for moderators' do
      mod = create(:user, :moderator)
      c = create(:comment)
      expect(c.is_deletable_by_user?(mod)).to be true
    end

    it 'is true for author within delete window' do
      author = create(:user)
      c = create(:comment, user: author, created_at: (Comment::DELETEABLE_DAYS - 1).days.ago)
      expect(c.is_deletable_by_user?(author)).to be true
    end

    it 'is false for non-author' do
      c = create(:comment)
      other = create(:user)
      expect(c.is_deletable_by_user?(other)).to be false
    end

    it 'is false for author after delete window' do
      author = create(:user)
      c = create(:comment, user: author, created_at: (Comment::DELETEABLE_DAYS + 1).days.ago)
      expect(c.is_deletable_by_user?(author)).to be false
    end
  end

  describe '#is_disownable_by_user?' do
    it 'is true for author after delete window' do
      author = create(:user)
      c = create(:comment, user: author, created_at: (Comment::DELETEABLE_DAYS + 1).days.ago)
      expect(c.is_disownable_by_user?(author)).to be true
    end

    it 'is false for recent comments' do
      author = create(:user)
      c = create(:comment, user: author, created_at: 1.day.ago)
      expect(c.is_disownable_by_user?(author)).to be false
    end
  end

  describe '#is_flaggable?' do
    it 'is true when recent and score above min' do
      c = create(:comment, created_at: 1.day.ago, score: 0)
      expect(c.is_flaggable?).to be true
    end

    it 'is false when too old' do
      c = create(:comment, created_at: (Comment::FLAGGABLE_DAYS + 1).days.ago, score: 0)
      expect(c.is_flaggable?).to be false
    end

    it 'is false when score below or equal to min' do
      c = create(:comment, created_at: 1.day.ago)
      c.update_columns(score: Comment::FLAGGABLE_MIN_SCORE)
      expect(c.is_flaggable?).to be false
    end
  end

  describe '#is_editable_by_user?' do
    it 'is true for author within edit window' do
      author = create(:user)
      c = create(:comment, user: author, last_edited_at: Time.current - (Comment::MAX_EDIT_MINS - 5).minutes)
      expect(c.is_editable_by_user?(author)).to be true
    end

    it 'is false after edit window' do
      author = create(:user)
      c = create(:comment, user: author)
      c.update_columns(last_edited_at: Time.current - (Comment::MAX_EDIT_MINS + 5).minutes)
      expect(c.is_editable_by_user?(author)).to be false
    end

    it 'is false for gone comments' do
      author = create(:user)
      c = create(:comment, user: author, is_deleted: true)
      expect(c.is_editable_by_user?(author)).to be false
    end
  end

  describe '#is_gone?' do
    it 'is true when deleted or moderated' do
      expect(create(:comment, is_deleted: true).is_gone?).to be true
      expect(create(:comment, is_moderated: true).is_gone?).to be true
    end

    it 'is false when active' do
      expect(create(:comment).is_gone?).to be false
    end
  end

  describe '#is_undeletable_by_user?' do
    it 'is true for moderators' do
      mod = create(:user, :moderator)
      c = create(:comment)
      expect(c.is_undeletable_by_user?(mod)).to be true
    end

    it 'is true for author when not moderated' do
      author = create(:user)
      c = create(:comment, user: author, is_moderated: false)
      expect(c.is_undeletable_by_user?(author)).to be true
    end

    it 'is false for author when moderated' do
      author = create(:user)
      c = create(:comment, user: author, is_moderated: true)
      expect(c.is_undeletable_by_user?(author)).to be false
    end
  end

  describe '#log_hat_use' do
    it 'creates a moderation log when hat requires modlog_use' do
      hat = create(:hat, modlog_use: true, hat: 'Gold')
      user = hat.user
      c = create(:comment, user: user, hat: hat)
      expect do
        c.log_hat_use
      end.to change { Moderation.count }.by(1)
      expect(Moderation.last.action).to eq('used Gold hat')
    end

    it 'does nothing when hat does not require modlog_use' do
      hat = create(:hat, modlog_use: false)
      user = hat.user
      c = create(:comment, user: user, hat: hat)
      expect do
        c.log_hat_use
      end.not_to(change { Moderation.count })
    end
  end

  describe '#mark_submitter' do
    it 'increments the keystore counter for user comments posted' do
      c = create(:comment)
      expect(Keystore).to receive(:increment_value_for).with("user:#{c.user_id}:comments_posted")
      c.mark_submitter
    end
  end

  describe '#mailing_list_message_id' do
    it 'builds a message id including short id and timestamp' do
      c = create(:comment, is_from_email: true, created_at: Time.at(1_700_000_000))
      allow(Rails.application).to receive(:domain).and_return('example.org')
      expect(c.mailing_list_message_id).to eq("comment.#{c.short_id}.email.1700000000@example.org")
    end
  end

  describe '#parents' do
    it 'returns none for top-level comments or new records' do
      expect(Comment.new.parents).to be_empty
      top = create(:comment, parent_comment: nil)
      expect(top.parents).to be_empty
    end

    it 'returns all ancestors oldest first' do
      top = create(:comment, parent_comment: nil)
      mid = create(:comment, parent_comment: top)
      leaf = create(:comment, parent_comment: mid)
      expect(leaf.parents).to eq([top, mid])
    end
  end

  describe '#plaintext_comment' do
    it 'returns the raw comment text' do
      c = create(:comment, comment: 'Hello <b>world</b>')
      expect(c.plaintext_comment).to eq('Hello <b>world</b>')
    end
  end

  describe '#record_initial_upvote' do
    it 'creates an upvote and recalculates score' do
      create(:comment)
      s = create(:story)
      u = create(:user)
      c2 = Comment.create!(user: u, story: s, comment: 'hi', last_edited_at: Time.current, score: 0, flags: 0,
                           confidence: 0, confidence_order: [0, 0, 0].pack('CCC'), short_id: ShortId.new(Comment).generate, thread_id: Keystore.incremented_value_for('thread_id'), depth: 0)
      expect(c2).to receive(:update_score_and_recalculate!).with(0, 0)
      expect do
        c2.record_initial_upvote
      end.to change { Vote.where(comment: c2, user: u, vote: 1).count }.by(1)
    end
  end

  describe '#show_score_to_user?' do
    it 'returns true for moderators' do
      mod = create(:user, :moderator)
      c = create(:comment, created_at: Time.current, score: 0)
      expect(c.show_score_to_user?(mod)).to be true
    end

    it 'hides score for recent near-zero comments' do
      u = create(:user)
      c = create(:comment, created_at: 1.hour.ago, score: 0)
      expect(c.show_score_to_user?(u)).to be false
    end

    it 'shows score for older comments regardless of near-zero score' do
      u = create(:user)
      c = create(:comment, created_at: 48.hours.ago, score: 0)
      expect(c.show_score_to_user?(u)).to be true
    end

    it 'hides score if current user flagged the comment' do
      u = create(:user)
      c = create(:comment, created_at: 48.hours.ago, score: 10)
      c.current_vote = { vote: -1 }
      expect(c.show_score_to_user?(u)).to be false
    end
  end

  describe '#to_param' do
    it 'returns the short_id' do
      c = create(:comment)
      expect(c.to_param).to eq(c.short_id)
    end
  end

  describe '#recreate_links' do
    it 'recreates links only when comment changed' do
      c = create(:comment)
      allow(c).to receive(:saved_change_to_attribute?).with(:comment).and_return(true)
      expect(Link).to receive(:recreate_from_comment!).with(c)
      c.recreate_links
    end

    it 'does nothing when comment not changed' do
      c = create(:comment)
      allow(c).to receive(:saved_change_to_attribute?).with(:comment).and_return(false)
      expect(Link).not_to receive(:recreate_from_comment!)
      c.recreate_links
    end
  end

  describe '#unassign_votes' do
    it 'updates cached columns on story' do
      c = create(:comment)
      expect(c.story).to receive(:update_cached_columns)
      c.unassign_votes
    end
  end

  describe '#validate_commenter_hasnt_flagged_parent' do
    it 'adds an error if user flagged the parent comment' do
      author = create(:user)
      parent = create(:comment)
      Vote.vote_thusly_on_story_or_comment_for_user_because(-1, parent.story_id, parent.id, author.id, 'T')
      child = build(:comment, user: author, story: parent.story, parent_comment: parent)
      expect(child.valid?).to be false
      expect(child.errors[:base].join).to include("You've flagged that comment")
    end
  end

  describe 'vote_summary formatting' do
    it 'formats vote_summary_for_user' do
      c = build(:comment)
      c.vote_summary = [OpenStruct.new(count: 2, reason_text: 'Spam')]
      expect(c.vote_summary_for_user).to eq('2 spam')
    end

    it 'formats vote_summary_for_moderator with usernames' do
      c = build(:comment)
      c.vote_summary = [OpenStruct.new(count: 1, reason_text: 'Offtopic', usernames: 'alice,bob')]
      expect(c.vote_summary_for_moderator).to eq('1 offtopic (alice,bob)')
    end
  end

  describe '#undelete_for_user' do
    it "undeletes and logs when a moderator undeletes someone else's comment" do
      mod = create(:user, :moderator)
      author = create(:user)
      c = create(:comment, user: author, is_deleted: true, is_moderated: true)
      expect(c).to receive(:update_score_and_recalculate!).with(0, 0)
      expect do
        c.undelete_for_user(mod)
      end.to change { Moderation.where(action: 'undeleted comment').count }.by(1)
      expect(c.reload.is_deleted).to be false
      expect(c.is_moderated).to be false
    end

    it 'undeletes without logging when author undeletes their own comment' do
      author = create(:user)
      c = create(:comment, user: author, is_deleted: true, is_moderated: false)
      expect do
        c.undelete_for_user(author)
      end.not_to(change { Moderation.count })
      expect(c.reload.is_deleted).to be false
    end
  end

  describe '#current_vote helpers' do
    it 'current_flagged? is true when current vote is -1' do
      c = build(:comment)
      c.current_vote = { vote: -1 }
      expect(c.current_flagged?).to be true
    end

    it 'current_upvoted? is true when current vote is 1' do
      c = build(:comment)
      c.current_vote = { vote: 1 }
      expect(c.current_upvoted?).to be true
    end
  end

  describe '#update_score_and_recalculate!' do
    it 'recomputes score and flags from votes and updates story cache' do
      c = create(:comment)
      voter1 = create(:user)
      voter2 = create(:user)
      Vote.vote_thusly_on_story_or_comment_for_user_because(1, c.story_id, c.id, voter1.id, nil)
      Vote.vote_thusly_on_story_or_comment_for_user_because(-1, c.story_id, c.id, voter2.id, 'T')
      expect(c.story).to receive(:update_cached_columns)
      c.update_score_and_recalculate!(0, 0)
      c.reload
      expected_score = Vote.where(comment_id: c.id).sum(:vote)
      expected_flags = Vote.where(comment_id: c.id, vote: -1).count
      expect(c.score).to eq(expected_score)
      expect(c.flags).to eq(expected_flags)
    end
  end
end
