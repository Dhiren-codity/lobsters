require 'rails_helper'

describe User do
  it 'has a valid username' do
    expect { create(:user, username: nil) }.to raise_error
    expect { create(:user, username: '') }.to raise_error
    expect { create(:user, username: '*') }.to raise_error
    # security controls, usernames are used in queries and filenames
    expect { create(:user, username: "a'b") }.to raise_error
    expect { create(:user, username: 'a"b') }.to raise_error
    expect { create(:user, username: '../b') }.to raise_error

    create(:user, username: 'newbie')
    expect { create(:user, username: 'newbie') }.to raise_error

    create(:user, username: 'underscores_and-dashes')
    invalid_username_variants = %w[underscores-and_dashes underscores_and_dashes underscores-and-dashes]

    invalid_username_variants.each do |invalid_username|
      subject = build(:user, username: invalid_username)
      expect(subject).to_not be_valid
      expect(subject.errors[:username]).to eq(['is already in use (perhaps swapping _ and -)'])
    end

    create(:user, username: 'case_insensitive')
    expect { create(:user, username: 'CASE_INSENSITIVE') }.to raise_error
    expect { create(:user, username: 'case_Insensitive') }.to raise_error
    expect { create(:user, username: 'case-insensITive') }.to raise_error
  end

  describe '#authenticate_totp' do
    it 'verifies a valid TOTP code' do
      user = create(:user, totp_secret: ROTP::Base32.random)
      code = ROTP::TOTP.new(user.totp_secret).now
      expect(user.authenticate_totp(code)).to be_truthy
    end

    it 'rejects an invalid TOTP code' do
      user = create(:user, totp_secret: ROTP::Base32.random)
      expect(user.authenticate_totp('000000')).to be_falsey
    end
  end

  describe '#avatar_path' do
    it 'returns a path for the given size' do
      user = create(:user, username: 'bob')
      expect(user.avatar_path(50)).to include('/avatars/bob-50.png')
    end
  end

  describe '#avatar_url' do
    it 'returns a url for the given size' do
      user = create(:user, username: 'bob')
      expect(user.avatar_url(80)).to include('/avatars/bob-80.png')
    end
  end

  describe '#disable_invite_by_user_for_reason!' do
    it 'disables inviting and records message and moderation' do
      disabler = create(:user)
      user = create(:user)
      reason = 'abuse of invitation privileges'

      expect do
        expect(user.disable_invite_by_user_for_reason!(disabler, reason)).to be true
      end.to change { Message.count }.by(1).and change { Moderation.count }.by(1)

      user.reload
      expect(user.disabled_invite_at).to be_present
      expect(user.disabled_invite_by_user_id).to eq(disabler.id)
      expect(user.disabled_invite_reason).to eq(reason)

      msg = Message.order(:id).last
      expect(msg.recipient_user_id).to eq(user.id)
      expect(msg.author_user_id).to eq(disabler.id)
      expect(msg.subject).to include('Your invite privileges have been revoked')
      expect(msg.body).to include(reason)

      mod = Moderation.order(:id).last
      expect(mod.user_id).to eq(user.id)
      expect(mod.moderator_user_id).to eq(disabler.id)
      expect(mod.action).to eq('Disabled invitations')
      expect(mod.reason).to eq(reason)
    end
  end

  describe '#banned_from_inviting?' do
    it 'is true when disabled_invite_at is set' do
      u = create(:user, disabled_invite_at: Time.current)
      expect(u.banned_from_inviting?).to be true
    end

    it 'is false when disabled_invite_at is nil' do
      u = create(:user, disabled_invite_at: nil)
      expect(u.banned_from_inviting?).to be false
    end
  end

  describe 'permission checks' do
    let(:old_time) { (User::NEW_USER_DAYS + 1).days.ago }

    describe '#can_flag?' do
      it 'is false for new users' do
        u = create(:user, created_at: Time.current)
        story = create(:story)
        allow(story).to receive(:is_flaggable?).and_return(true)
        expect(u.can_flag?(story)).to be false
      end

      it 'allows flagging a flaggable story' do
        u = create(:user, created_at: old_time)
        story = create(:story)
        allow(story).to receive(:is_flaggable?).and_return(true)
        allow(story).to receive(:current_flagged?).and_return(false)
        expect(u.can_flag?(story)).to be true
      end

      it 'allows unvoting an already flagged story' do
        u = create(:user, created_at: old_time)
        story = create(:story)
        allow(story).to receive(:is_flaggable?).and_return(false)
        allow(story).to receive(:current_flagged?).and_return(true)
        expect(u.can_flag?(story)).to be true
      end

      it 'requires sufficient karma to flag a comment' do
        low = create(:user, created_at: old_time, karma: User::MIN_KARMA_TO_FLAG - 1)
        high = create(:user, created_at: old_time, karma: User::MIN_KARMA_TO_FLAG)
        comment = create(:comment)
        allow(comment).to receive(:is_flaggable?).and_return(true)

        expect(low.can_flag?(comment)).to be false
        expect(high.can_flag?(comment)).to be true
      end

      it 'is false for non-flaggable comment' do
        u = create(:user, created_at: old_time, karma: 999)
        comment = create(:comment)
        allow(comment).to receive(:is_flaggable?).and_return(false)
        expect(u.can_flag?(comment)).to be false
      end
    end

    describe '#can_invite?' do
      it 'requires not banned from inviting and ability to submit stories' do
        u = create(:user, disabled_invite_at: nil, karma: User::MIN_KARMA_TO_SUBMIT_STORIES)
        expect(u.can_invite?).to be true

        u2 = create(:user, disabled_invite_at: Time.current, karma: 100)
        expect(u2.can_invite?).to be false

        u3 = create(:user, disabled_invite_at: nil, karma: User::MIN_KARMA_TO_SUBMIT_STORIES - 1)
        expect(u3.can_invite?).to be false
      end
    end

    describe '#can_offer_suggestions?' do
      it 'requires not new and minimum karma' do
        u = create(:user, created_at: (User::NEW_USER_DAYS + 2).days.ago,
                          karma: User::MIN_KARMA_TO_SUGGEST)
        expect(u.can_offer_suggestions?).to be true

        u2 = create(:user, created_at: Time.current, karma: 10_000)
        expect(u2.can_offer_suggestions?).to be false

        u3 = create(:user, created_at: (User::NEW_USER_DAYS + 2).days.ago,
                           karma: User::MIN_KARMA_TO_SUGGEST - 1)
        expect(u3.can_offer_suggestions?).to be false
      end
    end

    describe '#can_see_invitation_requests?' do
      it 'allows moderators regardless of karma if they can invite' do
        u = create(:user, is_moderator: true,
                          disabled_invite_at: nil,
                          karma: User::MIN_KARMA_TO_SUBMIT_STORIES)
        expect(u.can_see_invitation_requests?).to be true
      end

      it 'requires can_invite and minimum karma for non-moderators' do
        u = create(:user, is_moderator: false,
                          disabled_invite_at: nil,
                          karma: User::MIN_KARMA_FOR_INVITATION_REQUESTS)
        expect(u.can_see_invitation_requests?).to be true

        u2 = create(:user, is_moderator: false,
                           disabled_invite_at: nil,
                           karma: User::MIN_KARMA_FOR_INVITATION_REQUESTS - 1)
        expect(u2.can_see_invitation_requests?).to be false

        u3 = create(:user, is_moderator: false,
                           disabled_invite_at: Time.current,
                           karma: 10_000)
        expect(u3.can_see_invitation_requests?).to be false
      end
    end

    describe '#can_submit_stories?' do
      it 'checks minimum karma' do
        u = create(:user, karma: User::MIN_KARMA_TO_SUBMIT_STORIES)
        expect(u.can_submit_stories?).to be true
        u2 = create(:user, karma: User::MIN_KARMA_TO_SUBMIT_STORIES - 1)
        expect(u2.can_submit_stories?).to be false
      end
    end

    describe '#high_karma?' do
      it 'is true at threshold and above' do
        u = create(:user, karma: User::HIGH_KARMA_THRESHOLD)
        expect(u.high_karma?).to be true
        u2 = create(:user, karma: User::HIGH_KARMA_THRESHOLD + 1)
        expect(u2.high_karma?).to be true
        u3 = create(:user, karma: User::HIGH_KARMA_THRESHOLD - 1)
        expect(u3.high_karma?).to be false
      end
    end
  end

  describe 'token and callback generation' do
    it 'generates rss_token, mailing_list_token, and session_token on create/save' do
      user = build(:user, rss_token: nil, mailing_list_token: nil, session_token: nil)
      expect(user.rss_token).to be_nil
      expect(user.mailing_list_token).to be_nil
      expect(user.session_token).to be_nil

      user.save!

      expect(user.rss_token).to be_present
      expect(user.rss_token.length).to be >= 10
      expect(user.mailing_list_token).to be_present
      expect(user.mailing_list_token.length).to be >= 10
      expect(user.session_token).to be_present
      expect(user.session_token.length).to be >= 60
    end
  end

  describe '#refresh_counts!' do
    it 'stores current counts in the keystore' do
      user = create(:user)
      s1 = create(:story, user: user)
      create(:story, user: user)
      create(:comment, user: user, story: s1, is_deleted: false)
      create(:comment, user: user, story: s1, is_deleted: true)

      user.refresh_counts!

      expect(user.stories_submitted_count).to eq(2)
      expect(user.comments_posted_count).to eq(1)
      expect(user.comments_deleted_count).to eq(1)
    end
  end

  describe '#delete! and #undelete!' do
    it 'soft-deletes a user and rolls session token, then undeletes' do
      user = create(:user)
      original_session = user.session_token
      expect(original_session).to be_present

      # create some related records to exercise side effects
      recipient = create(:user)
      create(:message, author: user, recipient: recipient, deleted_by_author: false)
      create(:message, author: recipient, recipient: user, deleted_by_recipient: false)
      create(:invitation, user: user, used_at: nil)

      user.delete!
      user.reload

      expect(user.deleted_at).to be_present
      expect(user.session_token).to be_present
      expect(user.session_token).not_to eq(original_session)

      # messages should be marked deleted
      expect(Message.where(author_user_id: user.id).last.deleted_by_author).to be true
      expect(Message.where(recipient_user_id: user.id).last.deleted_by_recipient).to be true

      # undelete clears deleted_at
      user.undelete!
      user.reload
      expect(user.deleted_at).to be_nil
    end
  end

  describe '#disable_2fa! and #has_2fa?' do
    it 'clears the TOTP secret and updates has_2fa?' do
      user = create(:user, totp_secret: ROTP::Base32.random)
      expect(user.has_2fa?).to be true
      user.disable_2fa!
      user.reload
      expect(user.has_2fa?).to be false
    end
  end

  describe '#good_riddance?' do
    it 'overrides email if karma is negative and user is not banned' do
      user = create(:user, username: 'testuser', email: 'real@example.com', karma: -5, banned_at: nil)
      user.good_riddance?
      expect(user.email).to eq('testuser@lobsters.example')
    end

    it 'does nothing if user is banned' do
      user = create(:user, username: 'testuser', email: 'real@example.com', karma: -5, banned_at: Time.current)
      expect { user.good_riddance? }.not_to(change { user.email })
    end
  end

  describe '#grant_moderatorship_by_user!' do
    it 'grants moderator status and creates moderation and hat' do
      mod = create(:user)
      user = create(:user)

      expect do
        expect(user.grant_moderatorship_by_user!(mod)).to be true
      end.to change { Moderation.count }.by(1).and change { Hat.count }.by(1)

      user.reload
      expect(user.is_moderator).to be true

      moderation = Moderation.order(:id).last
      expect(moderation.user_id).to eq(user.id)
      expect(moderation.moderator_user_id).to eq(mod.id)
      expect(moderation.action).to eq('Granted moderator status')

      hat = Hat.order(:id).last
      expect(hat.user_id).to eq(user.id)
      expect(hat.granted_by_user_id).to eq(mod.id)
      expect(hat.hat).to eq('Sysop')
    end
  end

  describe '#is_wiped?' do
    it 'returns true when password_digest is "*"' do
      user = create(:user)
      user.update_column(:password_digest, '*')
      expect(user.is_wiped?).to be true
    end

    it 'returns false otherwise' do
      user = create(:user)
      expect(user.is_wiped?).to be false
    end
  end

  describe '#roll_session_token' do
    it 'generates a new session token of expected length' do
      user = create(:user)
      original = user.session_token
      user.roll_session_token
      expect(user.session_token).to be_present
      expect(user.session_token.length).to be >= 60
      expect(user.session_token).not_to eq(original)
    end
  end

  describe '#mastodon_acct' do
    it 'raises if required fields are missing' do
      user = create(:user, mastodon_username: nil, mastodon_instance: nil)
      expect { user.mastodon_acct }.to raise_error(RuntimeError)
    end

    it 'returns the acct string when fields are present' do
      user = create(:user, mastodon_username: 'alice', mastodon_instance: 'example.social')
      expect(user.mastodon_acct).to eq('@alice@example.social')
    end
  end

  describe '#pushover!' do
    it 'sends a push when user key present' do
      user = create(:user, pushover_user_key: 'userkey')
      params = { title: 'Hello', message: 'World' }
      expect(Pushover).to receive(:push).with('userkey', params)
      user.pushover!(params)
    end

    it 'does nothing when no user key' do
      user = create(:user, pushover_user_key: nil)
      expect(Pushover).not_to receive(:push)
      user.pushover!(title: 'x')
    end
  end

  describe '#to_param' do
    it 'returns the username' do
      user = create(:user, username: 'paramuser')
      expect(user.to_param).to eq('paramuser')
    end
  end

  describe '#enable_invite_by_user!' do
    it 're-enables inviting and records moderation' do
      moderator = create(:user)
      user = create(:user, disabled_invite_at: Time.current,
                           disabled_invite_by_user: moderator,
                           disabled_invite_reason: 'bad')

      expect do
        expect(user.enable_invite_by_user!(moderator)).to be true
      end.to change { Moderation.count }.by(1)

      user.reload
      expect(user.disabled_invite_at).to be_nil
      expect(user.disabled_invite_by_user_id).to be_nil
      expect(user.disabled_invite_reason).to be_nil

      mod = Moderation.order(:id).last
      expect(mod.user_id).to eq(user.id)
      expect(mod.moderator_user_id).to eq(moderator.id)
      expect(mod.action).to eq('Enabled invitations')
    end
  end

  describe '#inbox_count' do
    it 'counts unread notifications' do
      user = create(:user)
      other_user = create(:user)
      notifiable1 = create(:comment)
      notifiable2 = create(:story)
      notifiable3 = create(:comment)

      create(:notification, user: user, read_at: nil, notifiable: notifiable1)
      create(:notification, user: user, read_at: Time.current, notifiable: notifiable2)
      create(:notification, user: other_user, read_at: nil, notifiable: notifiable3)

      expect(user.inbox_count).to eq(1)
    end
  end

  describe '#votes_for_others' do
    it 'returns votes where the target is authored by others, ordered by id desc' do
      voter = create(:user)
      author1 = create(:user)
      author2 = create(:user)

      story_by_author1 = create(:story, user: author1)
      story_by_voter = create(:story, user: voter)
      comment_by_author2 = create(:comment, user: author2, story: story_by_author1)

      vote1 = create(:vote, user: voter, story: story_by_author1) # should include
      vote2 = create(:vote, user: voter, story: story_by_voter)   # should exclude
      vote3 = create(:vote, user: voter, story: story_by_author1, comment: comment_by_author2) # should include

      results = voter.votes_for_others.to_a
      expect(results).to include(vote1, vote3)
      expect(results).not_to include(vote2)
      expect(results.map(&:id)).to eq(results.map(&:id).sort.reverse)
    end
  end
end
