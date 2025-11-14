# typed: false

require 'rails_helper'
require 'spec_helper'

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

  describe 'scopes' do
    it 'returns only deleted comments for .deleted' do
      deleted = create(:comment, is_deleted: true)
      not_deleted = create(:comment, is_deleted: false)
      expect(Comment.deleted).to include(deleted)
      expect(Comment.deleted).not_to include(not_deleted)
    end

    it 'returns only not_deleted comments for .not_deleted' do
      deleted = create(:comment, is_deleted: true)
      not_deleted = create(:comment, is_deleted: false)
      expect(Comment.not_deleted).to include(not_deleted)
      expect(Comment.not_deleted).not_to include(deleted)
    end

    it 'returns only not_moderated comments for .not_moderated' do
      moderated = create(:comment, is_moderated: true)
      not_moderated = create(:comment, is_moderated: false)
      expect(Comment.not_moderated).to include(not_moderated)
      expect(Comment.not_moderated).not_to include(moderated)
    end

    it 'returns only active comments for .active' do
      active = create(:comment, is_deleted: false, is_moderated: false)
      deleted = create(:comment, is_deleted: true, is_moderated: false)
      moderated = create(:comment, is_deleted: false, is_moderated: true)
      expect(Comment.active).to include(active)
      expect(Comment.active).not_to include(deleted)
      expect(Comment.active).not_to include(moderated)
    end

    it 'returns only recent comments for .recent' do
      old = create(:comment, created_at: 7.months.ago)
      recent = create(:comment, created_at: 1.day.ago)
      expect(Comment.recent).to include(recent)
      expect(Comment.recent).not_to include(old)
    end
  end

  describe '#assign_initial_attributes' do
    it 'sets depth and thread_id for top-level and reply' do
      top = create(:comment, parent_comment: nil)
      reply = create(:comment, story: top.story, parent_comment: top)
      expect(top.depth).to eq(0)
      expect(reply.depth).to eq(1)
      expect(reply.thread_id).to eq(top.thread_id)
    end

    it 'sets defaults including confidence_order and last_edited_at' do
      c = create(:comment)
      expect(c.score).to be_present
      expect(c.confidence_order.bytesize).to eq(3)
      expect(c.last_edited_at).to be_present
    end
  end

  describe '#current_flagged? and #current_upvoted?' do
    it "detects current user's vote state" do
      c = build(:comment)
      c.current_vote = { vote: -1 }
      expect(c.current_flagged?).to be true
      c.current_vote = { vote: 1 }
      expect(c.current_upvoted?).to be true
      c.current_vote = nil
      expect(c.current_flagged?).to be false
      expect(c.current_upvoted?).to be false
    end
  end

  describe '#depth_permits_reply?' do
    it 'returns false for unsaved comment' do
      c = build(:comment)
      expect(c.depth_permits_reply?).to be false
    end

    it 'returns true when depth below maximum' do
      c = create(:comment)
      c.update_columns(depth: Comment::MAX_DEPTH - 1)
      expect(c.depth_permits_reply?).to be true
    end

    it 'returns false when depth at or beyond maximum' do
      c = create(:comment)
      c.update_columns(depth: Comment::MAX_DEPTH)
      expect(c.depth_permits_reply?).to be false
    end
  end

  describe '#update_score_and_recalculate!' do
    it 'recomputes score and flags from votes' do
      c = create(:comment)
      u1 = create(:user)
      u2 = create(:user)
      Vote.create!(story: c.story, comment: c, user: u1, vote: 1)
      Vote.create!(story: c.story, comment: c, user: u2, vote: -1)
      c.update_score_and_recalculate!(0, 0)
      c.reload
      # initial +1 from author vote + u1 +1 + u2 -1 = 1
      expect(c.score).to eq(1)
      expect(c.flags).to eq(1)
      expect(c.confidence_order.bytesize).to eq(3)
    end
  end

  describe '#gone_text' do
    it 'explains moderator removal with reason' do
      mod = create(:user, :moderator)
      c = create(:comment, is_moderated: true)
      create(:moderation, comment: c, moderator: mod, action: 'deleted comment', reason: 'Rules')
      expect(c.gone_text).to include('Comment removed by moderator')
      expect(c.gone_text).to include(mod.username)
      expect(c.gone_text).to include('Rules')
    end

    it 'explains author removal' do
      c = create(:comment, is_deleted: true, is_moderated: false)
      expect(c.gone_text).to eq('Comment removed by author')
    end

    it 'explains banned user removal' do
      c = create(:comment, is_deleted: true, is_moderated: false)
      allow(c.user).to receive(:is_banned?).and_return(true)
      expect(c.gone_text).to eq('Comment from banned user removed')
    end
  end

  describe '#has_been_edited?' do
    it 'returns true when edited after one minute' do
      c = create(:comment, created_at: 2.hours.ago)
      c.update_columns(last_edited_at: 90.minutes.ago)
      expect(c.has_been_edited?).to be true
    end

    it 'returns false when not edited beyond one minute' do
      c = create(:comment, created_at: 10.minutes.ago)
      c.update_columns(last_edited_at: c.created_at + 30.seconds)
      expect(c.has_been_edited?).to be false
    end
  end

  describe 'deletability and editability' do
    let(:author) { create(:user) }
    let(:other) { create(:user) }
    let(:mod) { create(:user, :moderator) }

    it 'is deletable by moderator always' do
      c = create(:comment, user: author, created_at: 2.years.ago)
      expect(c.is_deletable_by_user?(mod)).to be true
    end

    it 'is deletable by author within window' do
      c = create(:comment, user: author, created_at: 3.days.ago)
      expect(c.is_deletable_by_user?(author)).to be true
    end

    it 'is not deletable by non-author' do
      c = create(:comment, user: author)
      expect(c.is_deletable_by_user?(other)).to be false
    end

    it 'is disownable by author after window' do
      c = create(:comment, user: author, created_at: (Comment::DELETEABLE_DAYS + 1).days.ago)
      expect(c.is_disownable_by_user?(author)).to be true
    end

    it 'is flaggable only when recent and above min score' do
      c1 = create(:comment, created_at: 2.days.ago, score: 0)
      c2 = create(:comment, created_at: (Comment::FLAGGABLE_DAYS + 1).days.ago)
      c3 = create(:comment, created_at: 1.day.ago, score: Comment::FLAGGABLE_MIN_SCORE)
      expect(c1.is_flaggable?).to be true
      expect(c2.is_flaggable?).to be false
      expect(c3.is_flaggable?).to be false
    end

    it 'is editable by author within window and not gone' do
      c = create(:comment, user: author)
      c.update_columns(last_edited_at: Time.current - (Comment::MAX_EDIT_MINS - 1).minutes)
      expect(c.is_editable_by_user?(author)).to be true
    end

    it 'is not editable by author after window' do
      c = create(:comment, user: author)
      c.update_columns(last_edited_at: Time.current - (Comment::MAX_EDIT_MINS + 1).minutes)
      expect(c.is_editable_by_user?(author)).to be false
    end

    it 'is not editable when gone' do
      c = create(:comment, user: author, is_deleted: true)
      expect(c.is_editable_by_user?(author)).to be false
    end

    it 'is gone if deleted or moderated' do
      deleted = create(:comment, is_deleted: true, is_moderated: false)
      moderated = create(:comment, is_deleted: false, is_moderated: true)
      expect(deleted.is_gone?).to be true
      expect(moderated.is_gone?).to be true
    end

    it 'is undeletable by moderator or author when not moderated' do
      c = create(:comment, user: author, is_moderated: false)
      expect(c.is_undeletable_by_user?(mod)).to be true
      expect(c.is_undeletable_by_user?(author)).to be true
      expect(c.is_undeletable_by_user?(nil)).to be false
    end
  end

  describe 'hat moderation log' do
    it 'creates a moderation log entry when hat requires modlog_use' do
      hat = create(:hat, modlog_use: true)
      user = hat.user
      expect do
        create(:comment, user: user, hat: hat)
      end.to change { Moderation.count }.by(1)
      expect(Moderation.last.action).to include('used')
    end
  end

  describe '#mark_submitter' do
    it 'increments keystore comments_posted counter on create' do
      user = create(:user)
      key = "user:#{user.id}:comments_posted"
      initial = Keystore.value_for(key).to_i
      expect do
        create(:comment, user: user)
      end.to change { Keystore.value_for(key).to_i }.by(1)
      expect(Keystore.value_for(key).to_i).to eq(initial + 1)
    end
  end

  describe '#mailing_list_message_id' do
    it 'includes email when from email and domain' do
      c = create(:comment, is_from_email: true, created_at: 1_700_000_000.to_i)
      expect(c.mailing_list_message_id).to include('comment')
      expect(c.mailing_list_message_id).to include(c.short_id)
      expect(c.mailing_list_message_id).to include('email')
      expect(c.mailing_list_message_id).to include('@')
    end

    it 'omits email marker when not from email' do
      c = create(:comment, is_from_email: false)
      expect(c.mailing_list_message_id.split('.')).not_to include('email')
    end
  end

  describe '#parents' do
    it 'returns all ancestors oldest first' do
      story = create(:story)
      top = create(:comment, story: story, parent_comment: nil)
      mid = create(:comment, story: story, parent_comment: top)
      bottom = create(:comment, story: story, parent_comment: mid)
      expect(bottom.parents.map(&:id)).to eq([top.id, mid.id])
    end

    it 'returns empty relation when no parent' do
      c = create(:comment, parent_comment: nil)
      expect(c.parents).to be_empty
    end
  end

  describe '#plaintext_comment' do
    it 'returns the raw comment text' do
      c = create(:comment, comment: 'Hello <b>world</b>')
      expect(c.plaintext_comment).to eq('Hello <b>world</b>')
    end
  end

  describe '#record_initial_upvote' do
    it 'creates an initial upvote by author' do
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

    it 'hides score on recent near-zero comments' do
      c = create(:comment, created_at: Time.current, score: 1)
      c.current_vote = nil
      expect(c.show_score_to_user?(create(:user))).to be false
    end

    it 'shows score when old enough even if near-zero' do
      c = create(:comment, created_at: 3.days.ago, score: 1)
      expect(c.show_score_to_user?(create(:user))).to be true
    end

    it 'hides score if current user flagged it' do
      c = create(:comment, created_at: 3.days.ago, score: 10)
      c.current_vote = { vote: -1 }
      expect(c.show_score_to_user?(create(:user))).to be false
    end
  end

  describe '#to_param' do
    it 'returns the short_id' do
      c = create(:comment)
      expect(c.to_param).to eq(c.short_id)
    end
  end

  describe '#recreate_links' do
    it 'recreates links when comment attribute changed' do
      c = create(:comment)
      expect(Link).to receive(:recreate_from_comment!).with(c)
      allow(c).to receive(:saved_change_to_attribute?).with(:comment).and_return(true)
      c.recreate_links
    end
  end

  describe 'after_destroy :unassign_votes' do
    it 'updates story cached columns' do
      c = create(:comment)
      expect(c.story).to receive(:update_cached_columns)
      c.destroy
    end
  end

  describe 'validate_commenter_hasnt_flagged_parent' do
    it 'adds error when user flagged parent comment' do
      story = create(:story)
      parent = create(:comment, story: story)
      user = create(:user)
      Vote.create!(story: story, comment: parent, user: user, vote: -1)
      child = build(:comment, story: story, user: user, parent_comment: parent, comment: 'reply')
      expect(child.valid?).to be false
      expect(child.errors[:base].join).to include('flagged that comment')
    end
  end

  describe 'vote summaries' do
    it 'formats vote_summary_for_user' do
      c = build(:comment)
      c.vote_summary = [
        OpenStruct.new(count: 2, reason_text: 'Offtopic'),
        OpenStruct.new(count: 1, reason_text: 'Spam')
      ]
      expect(c.vote_summary_for_user).to eq('2 offtopic, 1 spam')
    end

    it 'formats vote_summary_for_moderator with usernames' do
      c = build(:comment)
      c.vote_summary = [
        OpenStruct.new(count: 1, reason_text: 'Spam', usernames: 'alice'),
        OpenStruct.new(count: 3, reason_text: 'Offtopic', usernames: 'bob, carol, dave')
      ]
      expect(c.vote_summary_for_moderator).to eq('1 spam (alice), 3 offtopic (bob, carol, dave)')
    end
  end

  describe '#undelete_for_user' do
    it "un-deletes and logs moderation when a moderator acts on someone else's comment" do
      mod = create(:user, :moderator)
      author = create(:user)
      c = create(:comment, user: author, is_deleted: true, is_moderated: true)
      allow(c).to receive(:update_score_and_recalculate!).with(0, 0).and_return(nil)
      expect do
        c.undelete_for_user(mod)
      end.to change { Moderation.where(comment_id: c.id, action: 'undeleted comment').count }.by(1)
      expect(c.is_deleted).to be false
      expect(c.is_moderated).to be false
    end

    it 'does not log moderation when author undeletes own comment' do
      author = create(:user)
      c = create(:comment, user: author, is_deleted: true, is_moderated: false)
      allow(c).to receive(:update_score_and_recalculate!).with(0, 0).and_return(nil)
      expect do
        c.undelete_for_user(author)
      end.not_to(change { Moderation.count })
      expect(c.is_deleted).to be false
    end
  end

  describe '.regenerate_markdown' do
    it 're-renders markeddown_comment for all comments' do
      c = create(:comment, comment: 'hello')
      allow(Markdowner).to receive(:to_html).and_call_original
      expect do
        Comment.regenerate_markdown
      end.not_to raise_error
      c.reload
      expect(Markdowner).to have_received(:to_html).at_least(:once)
      expect(c.markeddown_comment).to include('<p>')
    end
  end

  describe '#as_json' do
    it 'serializes expected keys and URLs and handles gone comments' do
      parent = create(:comment)
      child = create(:comment, parent_comment: parent)
      allow(Routes).to receive(:comment_short_id_url).and_return('short_url')
      allow(Routes).to receive(:comment_target_url).and_return('target_url')
      json = child.as_json
      expect(json[:short_id]).to eq(child.short_id)
      expect(json[:parent_comment]).to eq(parent.short_id)
      expect(json[:short_id_url]).to eq('short_url')
      expect(json[:url]).to eq('target_url')

      child.update!(is_deleted: true)
      json = child.as_json
      expect(json[:comment]).to include('<em>')
      expect(json[:comment_plain]).to eq(child.gone_text)
    end
  end
end
