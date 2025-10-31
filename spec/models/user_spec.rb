require 'rails_helper'

RSpec.describe User do
  describe '#as_json' do
    it 'returns the correct JSON representation for a non-admin user' do
      user = create(:user, is_admin: false, github_username: 'github_user', mastodon_username: 'mastodon_user')
      json = user.as_json

      expect(json[:username]).to eq(user.username)
      expect(json[:created_at]).to eq(user.created_at)
      expect(json[:is_admin]).to eq(false)
      expect(json[:karma]).to eq(user.karma)
      expect(json[:homepage]).to eq(user.homepage)
      expect(json[:github_username]).to eq('github_user')
      expect(json[:mastodon_username]).to eq('mastodon_user')
    end

    it 'returns the correct JSON representation for an admin user' do
      user = create(:user, is_admin: true)
      json = user.as_json

      expect(json[:username]).to eq(user.username)
      expect(json[:created_at]).to eq(user.created_at)
      expect(json[:is_admin]).to eq(true)
      expect(json).not_to have_key(:karma)
    end
  end

  describe '#authenticate_totp' do
    it 'authenticates with a valid TOTP code' do
      user = create(:user, totp_secret: 'base32secret3232')
      totp = ROTP::TOTP.new(user.totp_secret)
      code = totp.now

      expect(user.authenticate_totp(code)).to be_truthy
    end

    it 'fails to authenticate with an invalid TOTP code' do
      user = create(:user, totp_secret: 'base32secret3232')
      expect(user.authenticate_totp('123456')).to be_falsey
    end
  end

  describe '#avatar_path' do
    it 'returns the correct avatar path' do
      user = create(:user, username: 'testuser')
      expect(user.avatar_path).to eq('/avatars/testuser-100.png')
    end
  end

  describe '#avatar_url' do
    it 'returns the correct avatar URL' do
      user = create(:user, username: 'testuser')
      expect(user.avatar_url).to eq(ActionController::Base.helpers.image_url('/avatars/testuser-100.png', skip_pipeline: true))
    end
  end

  describe '#disable_invite_by_user_for_reason!' do
    it 'disables invite privileges and creates a moderation record' do
      user = create(:user)
      disabler = create(:user)
      reason = 'Violation of terms'

      expect {
        user.disable_invite_by_user_for_reason!(disabler, reason)
      }.to change { user.disabled_invite_at }.from(nil).to(be_within(1.second).of(Time.current))
        .and change { user.disabled_invite_by_user_id }.from(nil).to(disabler.id)
        .and change { user.disabled_invite_reason }.from(nil).to(reason)
        .and change { Moderation.count }.by(1)

      moderation = Moderation.last
      expect(moderation.moderator_user_id).to eq(disabler.id)
      expect(moderation.user_id).to eq(user.id)
      expect(moderation.action).to eq('Disabled invitations')
      expect(moderation.reason).to eq(reason)
    end
  end

  describe '#ban_by_user_for_reason!' do
    it 'bans the user and creates a moderation record' do
      user = create(:user)
      banner = create(:user)
      reason = 'Spamming'

      expect {
        user.ban_by_user_for_reason!(banner, reason)
      }.to change { user.banned_at }.from(nil).to(be_within(1.second).of(Time.current))
        .and change { user.banned_by_user_id }.from(nil).to(banner.id)
        .and change { user.banned_reason }.from(nil).to(reason)
        .and change { Moderation.count }.by(1)

      moderation = Moderation.last
      expect(moderation.moderator_user_id).to eq(banner.id)
      expect(moderation.user_id).to eq(user.id)
      expect(moderation.action).to eq('Banned')
      expect(moderation.reason).to eq(reason)
    end
  end

  describe '#banned_from_inviting?' do
    it 'returns true if the user is banned from inviting' do
      user = create(:user, disabled_invite_at: Time.current)
      expect(user.banned_from_inviting?).to be true
    end

    it 'returns false if the user is not banned from inviting' do
      user = create(:user, disabled_invite_at: nil)
      expect(user.banned_from_inviting?).to be false
    end
  end

  describe '#can_flag?' do
    it 'returns false for new users' do
      user = create(:user, created_at: Time.current)
      story = create(:story, is_flaggable: true)
      expect(user.can_flag?(story)).to be false
    end

    it 'returns true for users with sufficient karma' do
      user = create(:user, karma: 100)
      story = create(:story, is_flaggable: true)
      expect(user.can_flag?(story)).to be true
    end
  end

  describe '#can_invite?' do
    it 'returns false if the user is banned from inviting' do
      user = create(:user, disabled_invite_at: Time.current)
      expect(user.can_invite?).to be false
    end

    it 'returns true if the user can submit stories' do
      user = create(:user, karma: 10)
      expect(user.can_invite?).to be true
    end
  end

  describe '#can_offer_suggestions?' do
    it 'returns false for new users' do
      user = create(:user, created_at: Time.current)
      expect(user.can_offer_suggestions?).to be false
    end

    it 'returns true for users with sufficient karma' do
      user = create(:user, karma: 20)
      expect(user.can_offer_suggestions?).to be true
    end
  end

  describe '#can_see_invitation_requests?' do
    it 'returns false if the user cannot invite' do
      user = create(:user, disabled_invite_at: Time.current)
      expect(user.can_see_invitation_requests?).to be false
    end

    it 'returns true for moderators' do
      user = create(:user, is_moderator: true)
      expect(user.can_see_invitation_requests?).to be true
    end
  end

  describe '#can_submit_stories?' do
    it 'returns false for users with insufficient karma' do
      user = create(:user, karma: -5)
      expect(user.can_submit_stories?).to be false
    end

    it 'returns true for users with sufficient karma' do
      user = create(:user, karma: 0)
      expect(user.can_submit_stories?).to be true
    end
  end

  describe '#check_session_token' do
    it 'rolls a new session token if blank' do
      user = create(:user, session_token: nil)
      expect { user.check_session_token }.to change { user.session_token }.from(nil)
    end
  end

  describe '#create_mailing_list_token' do
    it 'creates a mailing list token if blank' do
      user = create(:user, mailing_list_token: nil)
      expect { user.create_mailing_list_token }.to change { user.mailing_list_token }.from(nil)
    end
  end

  describe '#create_rss_token' do
    it 'creates an RSS token if blank' do
      user = create(:user, rss_token: nil)
      expect { user.create_rss_token }.to change { user.rss_token }.from(nil)
    end
  end

  describe '#fetched_avatar' do
    it 'returns the fetched avatar data' do
      user = create(:user, email: 'user@example.com')
      stub_request(:get, /gravatar.com/).to_return(body: 'avatar_data')
      expect(user.fetched_avatar).to eq('avatar_data')
    end

    it 'returns nil if fetching fails' do
      user = create(:user, email: 'user@example.com')
      stub_request(:get, /gravatar.com/).to_timeout
      expect(user.fetched_avatar).to be_nil
    end
  end

  describe '#refresh_counts!' do
    it 'updates the keystore with the correct counts' do
      user = create(:user)
      create_list(:story, 3, user: user)
      create_list(:comment, 2, user: user)

      expect(Keystore).to receive(:put).with("user:#{user.id}:stories_submitted", 3)
      expect(Keystore).to receive(:put).with("user:#{user.id}:comments_posted", 2)
      expect(Keystore).to receive(:put).with("user:#{user.id}:comments_deleted", 0)

      user.refresh_counts!
    end
  end

  describe '#delete!' do
    it 'marks the user as deleted and updates related records' do
      user = create(:user)
      create(:comment, user: user, score: -1)
      create(:message, author_user: user)
      create(:invitation, user: user)

      expect { user.delete! }.to change { user.deleted_at }.from(nil)
      expect(user.comments.where(score: -1).count).to eq(0)
      expect(user.sent_messages.where(deleted_by_author: true).count).to eq(1)
      expect(user.invitations.unused.count).to eq(0)
    end
  end

  describe '#undelete!' do
    it 'restores a deleted user' do
      user = create(:user, deleted_at: Time.current)
      expect { user.undelete! }.to change { user.deleted_at }.to(nil)
    end
  end

  describe '#disable_2fa!' do
    it 'removes the TOTP secret' do
      user = create(:user, totp_secret: 'secret')
      expect { user.disable_2fa! }.to change { user.totp_secret }.to(nil)
    end
  end

  describe '#good_riddance?' do
    it 'anonymizes the email for users with negative karma' do
      user = create(:user, karma: -1, username: 'testuser')
      expect { user.good_riddance? }.to change { user.email }.to('testuser@lobsters.example')
    end
  end

  describe '#grant_moderatorship_by_user!' do
    it 'grants moderatorship and creates a moderation record' do
      user = create(:user)
      moderator = create(:user)

      expect {
        user.grant_moderatorship_by_user!(moderator)
      }.to change { user.is_moderator }.from(false).to(true)
        .and change { Moderation.count }.by(1)
        .and change { Hat.count }.by(1)

      moderation = Moderation.last
      expect(moderation.moderator_user_id).to eq(moderator.id)
      expect(moderation.user_id).to eq(user.id)
      expect(moderation.action).to eq('Granted moderator status')
    end
  end

  describe '#initiate_password_reset_for_ip' do
    it 'sets a password reset token and sends an email' do
      user = create(:user)
      ip = '127.0.0.1'

      expect {
        user.initiate_password_reset_for_ip(ip)
      }.to change { user.password_reset_token }.from(nil)
        .and have_enqueued_mail(PasswordResetMailer, :password_reset_link).with(user, ip)
    end
  end

  describe '#has_2fa?' do
    it 'returns true if the user has a TOTP secret' do
      user = create(:user, totp_secret: 'secret')
      expect(user.has_2fa?).to be true
    end

    it 'returns false if the user does not have a TOTP secret' do
      user = create(:user, totp_secret: nil)
      expect(user.has_2fa?).to be false
    end
  end

  describe '#is_active?' do
    it 'returns false if the user is deleted or banned' do
      user = create(:user, deleted_at: Time.current)
      expect(user.is_active?).to be false

      user = create(:user, banned_at: Time.current)
      expect(user.is_active?).to be false
    end

    it 'returns true if the user is neither deleted nor banned' do
      user = create(:user)
      expect(user.is_active?).to be true
    end
  end

  describe '#is_wiped?' do
    it 'returns true if the password digest is wiped' do
      user = create(:user, password_digest: '*')
      expect(user.is_wiped?).to be true
    end

    it 'returns false if the password digest is not wiped' do
      user = create(:user)
      expect(user.is_wiped?).to be false
    end
  end

  describe '#ids_replied_to' do
    it 'returns a hash of comment IDs the user has replied to' do
      user = create(:user)
      comment1 = create(:comment, user: user)
      comment2 = create(:comment, user: user)
      create(:comment, parent_comment: comment1, user: user)
      create(:comment, parent_comment: comment2, user: user)

      result = user.ids_replied_to([comment1.id, comment2.id])
      expect(result[comment1.id]).to be true
      expect(result[comment2.id]).to be true
    end
  end

  describe '#roll_session_token' do
    it 'generates a new session token' do
      user = create(:user, session_token: 'old_token')
      expect { user.roll_session_token }.to change { user.session_token }.from('old_token')
    end
  end

  describe '#linkified_about' do
    it 'returns the about text as HTML' do
      user = create(:user, about: 'This is **bold** text.')
      expect(user.linkified_about).to include('<strong>bold</strong>')
    end
  end

  describe '#mastodon_acct' do
    it 'returns the Mastodon account string' do
      user = create(:user, mastodon_username: 'user', mastodon_instance: 'instance')
      expect(user.mastodon_acct).to eq('@user@instance')
    end

    it 'raises an error if Mastodon username or instance is missing' do
      user = create(:user, mastodon_username: nil, mastodon_instance: 'instance')
      expect { user.mastodon_acct }.to raise_error(RuntimeError)
    end
  end

  describe '#most_common_story_tag' do
    it 'returns the most common tag for the user\'s stories' do
      user = create(:user)
      tag1 = create(:tag)
      tag2 = create(:tag)
      create(:story, user: user, tags: [tag1])
      create(:story, user: user, tags: [tag1, tag2])

      expect(user.most_common_story_tag).to eq(tag1)
    end
  end

  describe '#pushover!' do
    it 'sends a pushover notification if user has a pushover key' do
      user = create(:user, pushover_user_key: 'key')
      params = { message: 'Test' }

      expect(Pushover).to receive(:push).with('key', params)
      user.pushover!(params)
    end

    it 'does not send a pushover notification if user does not have a pushover key' do
      user = create(:user, pushover_user_key: nil)
      params = { message: 'Test' }

      expect(Pushover).not_to receive(:push)
      user.pushover!(params)
    end
  end

  describe '#recent_threads' do
    it 'returns recent thread IDs for the user\'s comments' do
      user = create(:user)
      comment1 = create(:comment, user: user)
      comment2 = create(:comment, user: user)
      thread_ids = user.recent_threads(2)

      expect(thread_ids).to include(comment1.thread_id, comment2.thread_id)
    end
  end

  describe '#stories_submitted_count' do
    it 'returns the count of stories submitted by the user' do
      user = create(:user)
      create_list(:story, 3, user: user)

      expect(user.stories_submitted_count).to eq(3)
    end
  end

  describe '#stories_deleted_count' do
    it 'returns the count of stories deleted by the user' do
      user = create(:user)
      create_list(:story, 2, user: user, is_deleted: true)

      expect(user.stories_deleted_count).to eq(2)
    end
  end

  describe '#to_param' do
    it 'returns the username as the parameter' do
      user = create(:user, username: 'testuser')
      expect(user.to_param).to eq('testuser')
    end
  end

  describe '#enable_invite_by_user!' do
    it 'enables invite privileges and creates a moderation record' do
      user = create(:user, disabled_invite_at: Time.current)
      mod = create(:user)

      expect {
        user.enable_invite_by_user!(mod)
      }.to change { user.disabled_invite_at }.to(nil)
        .and change { Moderation.count }.by(1)

      moderation = Moderation.last
      expect(moderation.moderator_user_id).to eq(mod.id)
      expect(moderation.user_id).to eq(user.id)
      expect(moderation.action).to eq('Enabled invitations')
    end
  end

  describe '#inbox_count' do
    it 'returns the count of unread notifications' do
      user = create(:user)
      create_list(:notification, 3, user: user, read_at: nil)

      expect(user.inbox_count).to eq(3)
    end
  end

  describe '#votes_for_others' do
    it 'returns votes for others\' stories and comments' do
      user = create(:user)
      other_user = create(:user)
      story = create(:story, user: other_user)
      comment = create(:comment, user: other_user)
      create(:vote, user: user, story: story)
      create(:vote, user: user, comment: comment)

      votes = user.votes_for_others
      expect(votes.count).to eq(2)
    end
  end
end