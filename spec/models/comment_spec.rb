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

  describe '#current_vote helpers' do
    it 'reports current_flagged? and current_upvoted? from current_vote' do
      comment = build(:comment)
      comment.current_vote = { vote: -1 }
      expect(comment.current_flagged?).to be true
      expect(comment.current_upvoted?).to be false

      comment.current_vote = { vote: 1 }
      expect(comment.current_flagged?).to be false
      expect(comment.current_upvoted?).to be true

      comment.current_vote = nil
      expect(comment.current_flagged?).to be false
      expect(comment.current_upvoted?).to be false
    end
  end

  describe '#comment=' do
    it 'strips trailing whitespace and sets markeddown_comment' do
      allow(Markdowner).to receive(:to_html).and_return('HTML')
      c = build(:comment)
      c.comment = "hello world \n"
      expect(c.comment).to eq('hello world')
      expect(c.markeddown_comment).to eq('HTML')
    end
  end

  describe '#is_editable_by_user?' do
    it 'is true for the author within edit window and not gone' do
      author = create(:user)
      c = create(:comment, user: author)
      expect(c.is_editable_by_user?(author)).to be true
    end

    it 'is false when comment is gone' do
      author = create(:user)
      c = create(:comment, user: author, is_deleted: true)
      expect(c.is_editable_by_user?(author)).to be false
    end

    it 'is false when edit window has passed' do
      author = create(:user)
      c = create(:comment, user: author)
      c.update_columns(last_edited_at: (Comment::MAX_EDIT_MINS + 1).minutes.ago)
      expect(c.is_editable_by_user?(author)).to be false
    end
  end

  describe '#is_flaggable?' do
    it 'is true for fresh comments above min score' do
      c = create(:comment, score: 1, created_at: 1.day.ago)
      expect(c.is_flaggable?).to be true
    end

    it 'is false for old comments' do
      c = create(:comment, score: 1, created_at: (Comment::FLAGGABLE_DAYS + 1).days.ago)
      expect(c.is_flaggable?).to be false
    end

    it 'is false when score is below or equal to min' do
      c = create(:comment, score: Comment::FLAGGABLE_MIN_SCORE, created_at: 1.day.ago)
      expect(c.is_flaggable?).to be false
    end
  end

  describe 'deletion/ownership checks' do
    it 'is_deletable_by_user? allows moderators always' do
      mod = create(:user, :moderator)
      c = create(:comment)
      expect(c.is_deletable_by_user?(mod)).to be true
    end

    it 'is_deletable_by_user? allows author within window' do
      author = create(:user)
      c = create(:comment, user: author, created_at: Time.current)
      expect(c.is_deletable_by_user?(author)).to be true
    end

    it 'is_deletable_by_user? disallows author after window' do
      author = create(:user)
      c = create(:comment, user: author, created_at: (Comment::DELETEABLE_DAYS + 1).days.ago)
      expect(c.is_deletable_by_user?(author)).to be false
    end

    it 'is_disownable_by_user? only after window' do
      author = create(:user)
      old = create(:comment, user: author, created_at: (Comment::DELETEABLE_DAYS + 1).days.ago)
      recent = create(:comment, user: author, created_at: 1.day.ago)
      expect(old.is_disownable_by_user?(author)).to be true
      expect(recent.is_disownable_by_user?(author)).to be false
    end

    it 'is_undeletable_by_user? allows moderators and authors unless moderated' do
      mod = create(:user, :moderator)
      author = create(:user)
      c1 = create(:comment, user: author)
      c2 = create(:comment, user: author, is_moderated: true)
      expect(c1.is_undeletable_by_user?(mod)).to be true
      expect(c1.is_undeletable_by_user?(author)).to be true
      expect(c2.is_undeletable_by_user?(author)).to be false
    end
  end

  describe '#as_json' do
    it 'includes expected keys and uses rendered content when not gone' do
      c = create(:comment, comment: 'Hello')
      allow(Routes).to receive(:comment_short_id_url).and_return('short_url')
      allow(Routes).to receive(:comment_target_url).and_return('target_url')
      json = c.as_json
      expect(json[:short_id]).to eq(c.short_id)
      expect(json[:comment]).to eq(c.markeddown_comment)
      expect(json[:comment_plain]).to eq(c.comment)
      expect(json[:short_id_url]).to eq('short_url')
      expect(json[:url]).to eq('target_url')
    end

    it 'replaces comment with gone_text when gone' do
      c = create(:comment, is_deleted: true)
      allow(Routes).to receive(:comment_short_id_url).and_return('short_url')
      allow(Routes).to receive(:comment_target_url).and_return('target_url')
      json = c.as_json
      expect(json[:comment]).to include('<em>')
      expect(json[:comment_plain]).to eq(c.gone_text)
    end
  end

  describe '#to_param' do
    it 'returns short_id' do
      c = create(:comment)
      expect(c.to_param).to eq(c.short_id)
    end
  end

  describe "validation: commenter hasn't flagged parent" do
    it 'prevents replying to a parent the user flagged' do
      user = create(:user)
      story = create(:story)
      parent = create(:comment, story: story)
      Vote.vote_thusly_on_story_or_comment_for_user_because(-1, story.id, parent.id, user.id, 'T')
      child = build(:comment, story: story, user: user, parent_comment: parent)
      expect(child.valid?).to be false
      expect(child.errors[:base].join(' ')).to include('flagged that comment')
    end
  end

  describe '#parents' do
    it 'returns ancestors oldest first' do
      story = create(:story)
      top = create(:comment, story: story)
      mid = create(:comment, story: story, parent_comment: top)
      child = create(:comment, story: story, parent_comment: mid)
      expect(child.parents).to eq([top, mid])
    end

    it 'returns none for top-level comments' do
      c = create(:comment)
      expect(c.parents).to be_empty
    end
  end

  describe '.recent' do
    it 'returns comments from the last 6 months' do
      recent = create(:comment, created_at: 1.day.ago)
      old = create(:comment, created_at: 7.months.ago)
      expect(Comment.recent).to include(recent)
      expect(Comment.recent).not_to include(old)
    end
  end

  describe '#mailing_list_message_id' do
    it 'formats a stable message id including domain' do
      allow(Rails.application).to receive(:domain).and_return('example.test')
      c = create(:comment, is_from_email: true)
      mid = c.mailing_list_message_id
      expect(mid).to include('comment')
      expect(mid).to include(c.short_id)
      expect(mid).to include('email')
      expect(mid).to end_with('@example.test')
    end
  end

  describe '.regenerate_markdown' do
    it 'recomputes markeddown_comment for all comments' do
      c = create(:comment, comment: 'old')
      allow(Markdowner).to receive(:to_html).and_call_original
      expect do
        Comment.regenerate_markdown
        c.reload
      end.to(change { c.markeddown_comment })
    end
  end

  describe '#record_initial_upvote' do
    it 'creates an initial upvote by the author and updates score' do
      c = create(:comment)
      expect(Vote.where(comment: c, user: c.user, vote: 1)).to exist
      expect(c.reload.score).to eq(1)
    end
  end

  describe '#log_hat_use' do
    it 'creates a moderation log when a modlog_use hat is used' do
      hat = create(:hat, modlog_use: true, hat: 'Wizard')
      user = hat.user
      c = create(:comment, user: user, hat: hat)
      expect(Moderation.where(comment_id: c.id, action: 'used Wizard hat')).to exist
    end

    it 'does nothing when hat does not require modlog' do
      hat = create(:hat, modlog_use: false)
      user = hat.user
      c = create(:comment, user: user, hat: hat)
      expect(Moderation.where(comment_id: c.id)).to be_empty
    end
  end

  describe '#depth_permits_reply?' do
    it 'is false on new records' do
      c = build(:comment)
      expect(c.depth_permits_reply?).to be false
    end

    it 'is true when depth is below limit' do
      c = create(:comment)
      c.update_columns(depth: Comment::MAX_DEPTH - 1)
      expect(c.depth_permits_reply?).to be true
    end

    it 'is false when depth is at or above limit' do
      c = create(:comment)
      c.update_columns(depth: Comment::MAX_DEPTH)
      expect(c.depth_permits_reply?).to be false
    end
  end

  describe '#gone_text and #is_gone?' do
    it 'returns author removed text when deleted by author' do
      c = create(:comment, is_deleted: true)
      expect(c.is_gone?).to be true
      expect(c.gone_text).to include('removed by author')
    end

    it 'returns moderator removed text when moderated' do
      mod = create(:user, :moderator)
      c = create(:comment)
      c.delete_for_user(mod, 'Off-topic')
      expect(c.reload.is_moderated?).to be true
      expect(c.gone_text).to include('removed by moderator')
    end
  end

  describe '#show_score_to_user?' do
    it 'always shows to moderators' do
      mod = create(:user, :moderator)
      c = create(:comment, score: 0, created_at: 1.hour.ago)
      c.current_vote = { vote: -1 }
      expect(c.show_score_to_user?(mod)).to be true
    end

    it 'hides score on new near-zero comments' do
      user = create(:user)
      c = create(:comment, score: 0, created_at: 1.hour.ago)
      expect(c.show_score_to_user?(user)).to be false
    end

    it 'shows score on old near-zero comments' do
      user = create(:user)
      c = create(:comment, score: 0, created_at: 37.hours.ago)
      expect(c.show_score_to_user?(user)).to be true
    end

    it 'hides score when the viewer has flagged it' do
      user = create(:user)
      c = create(:comment, score: 10, created_at: 10.days.ago)
      c.current_vote = { vote: -1 }
      expect(c.show_score_to_user?(user)).to be false
    end
  end

  describe '#recreate_links' do
    it 'recreates links after comment text changes' do
      c = create(:comment, comment: 'no links')
      allow(Link).to receive(:recreate_from_comment!)
      c.update!(comment: 'a [link](https://e.x)')
      expect(Link).to have_received(:recreate_from_comment!).with(c)
    end
  end

  describe '#unassign_votes' do
    it 'updates story cached columns after destroy' do
      c = create(:comment)
      story = c.story
      allow(story).to receive(:update_cached_columns)
      c.destroy
      expect(story).to have_received(:update_cached_columns)
    end
  end

  describe '#vote_summary_for_user and #vote_summary_for_moderator' do
    it 'formats vote summaries correctly' do
      c = build(:comment)
      summary = [
        OpenStruct.new(count: 2, reason_text: 'Off-topic', usernames: 'a,b'),
        OpenStruct.new(count: 1, reason_text: 'Spam', usernames: 'c')
      ]
      c.vote_summary = summary
      expect(c.vote_summary_for_user).to eq('2 off-topic, 1 spam')
      expect(c.vote_summary_for_moderator).to eq('2 off-topic (a,b), 1 spam (c)')
    end
  end
end
