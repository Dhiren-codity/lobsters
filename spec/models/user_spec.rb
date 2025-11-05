require 'rails_helper'

RSpec.describe User do
  describe '#as_json' do
    it 'returns the correct JSON representation for a non-admin user' do
      user = create(:user, is_admin: false, karma: 100, homepage: 'https://example.com')
      json = user.as_json

      expect(json[:username]).to eq(user.username)
      expect(json[:created_at]).to eq(user.created_at)
      expect(json[:is_admin]).to eq(false)
      expect(json[:is_moderator]).to eq(user.is_moderator)
      expect(json[:karma]).to eq(100)
      expect(json[:homepage]).to eq('https://example.com')
    end

    it 'returns the correct JSON representation for an admin user' do
      user = create(:user, is_admin: true)
      json = user.as_json

      expect(json[:username]).to eq(user.username)
      expect(json[:created_at]).to eq(user.created_at)
      expect(json[:is_admin]).to eq(true)
      expect(json[:is_moderator]).to eq(user.is_moderator)
      expect(json).not_to have_key(:karma)
    end
  end

  describe '#authenticate_totp' do
    it 'returns true for a valid TOTP code' do
      user = create(:user, totp_secret: 'base32secret3232')
      totp = ROTP::TOTP.new(user.totp_secret)
      code = totp.now

      expect(user.authenticate_totp(code)).to be true
    end

    it 'returns false for an invalid TOTP code' do
      user = create(:user, totp_secret: 'base32secret3232')
      expect(user.authenticate_totp('123456')).to be false
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
    it 'returns false for a new user' do
      user = create(:user, created_at: 1.day.ago)
      story = create(:story)
      expect(user.can_flag?(story)).to be false
    end

    it 'returns true for a user with sufficient karma' do
      user = create(:user, karma: 100)
      story = create(:story, is_flaggable: true)
      expect(user.can_flag?(story)).to be true
    end
  end

  describe '#can_invite?' do
    it 'returns true if the user can invite' do
      user = create(:user, karma: 10, disabled_invite_at: nil)
      expect(user.can_invite?).to be true
    end

    it 'returns false if the user is banned from inviting' do
      user = create(:user, karma: 10, disabled_invite_at: Time.current)
      expect(user.can_invite?).to be false
    end
  end

  describe '#can_offer_suggestions?' do
    it 'returns true if the user can offer suggestions' do
      user = create(:user, karma: 20, created_at: 100.days.ago)
      expect(user.can_offer_suggestions?).to be true
    end

    it 'returns false if the user is new' do
      user = create(:user, karma: 20, created_at: 1.day.ago)
      expect(user.can_offer_suggestions?).to be false
    end
  end

  describe '#can_see_invitation_requests?' do
    it 'returns true if the user can see invitation requests' do
      user = create(:user, karma: 60, is_moderator: true)
      expect(user.can_see_invitation_requests?).to be true
    end

    it 'returns false if the user cannot invite' do
      user = create(:user, karma: 5, disabled_invite_at: Time.current)
      expect(user.can_see_invitation_requests?).to be false
    end
  end

  describe '#can_submit_stories?' do
    it 'returns true if the user can submit stories' do
      user = create(:user, karma: 0)
      expect(user.can_submit_stories?).to be true
    end

    it 'returns false if the user has insufficient karma' do
      user = create(:user, karma: -5)
      expect(user.can_submit_stories?).to be false
    end
  end

  describe '#check_session_token' do
    it 'generates a session token if none exists' do
      user = create(:user, session_token: nil)
      user.check_session_token
      expect(user.session_token).not_to be_nil
    end
  end

  describe '#create_mailing_list_token' do
    it 'generates a mailing list token if none exists' do
      user = create(:user, mailing_list_token: nil)
      user.create_mailing_list_token
      expect(user.mailing_list_token).not_to be_nil
    end
  end

  describe '#create_rss_token' do
    it 'generates an RSS token if none exists' do
      user = create(:user, rss_token: nil)
      user.create_rss_token
      expect(user.rss_token).not_to be_nil
    end
  end

  describe '#delete!' do
    it 'marks the user as deleted' do
      user = create(:user)
      user.delete!
      expect(user.deleted_at).not_to be_nil
    end
  end

  describe '#undelete!' do
    it 'restores a deleted user' do
      user = create(:user, deleted_at: Time.current)
      user.undelete!
      expect(user.deleted_at).to be_nil
    end
  end

  describe '#disable_2fa!' do
    it 'disables two-factor authentication' do
      user = create(:user, totp_secret: 'secret')
      user.disable_2fa!
      expect(user.totp_secret).to be_nil
    end
  end

  describe '#good_riddance?' do
    it 'anonymizes the email for users with negative karma' do
      user = create(:user, karma: -1, email: 'user@example.com')
      user.good_riddance?
      expect(user.email).to eq("#{user.username}@lobsters.example")
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

      expect(ActionMailer::Base.deliveries.last.to).to include(user.email)
    end
  end

  describe '#has_2fa?' do
    it 'returns true if the user has two-factor authentication enabled' do
      user = create(:user, totp_secret: 'secret')
      expect(user.has_2fa?).to be true
    end

    it 'returns false if the user does not have two-factor authentication enabled' do
      user = create(:user, totp_secret: nil)
      expect(user.has_2fa?).to be false
    end
  end

  describe '#is_active?' do
    it 'returns true if the user is active' do
      user = create(:user, deleted_at: nil, banned_at: nil)
      expect(user.is_active?).to be true
    end

    it 'returns false if the user is deleted' do
      user = create(:user, deleted_at: Time.current)
      expect(user.is_active?).to be false
    end

    it 'returns false if the user is banned' do
      user = create(:user, banned_at: Time.current)
      expect(user.is_active?).to be false
    end
  end

  describe '#is_banned?' do
    it 'returns true if the user is banned' do
      user = create(:user, banned_at: Time.current)
      expect(user.is_banned?).to be true
    end

    it 'returns false if the user is not banned' do
      user = create(:user, banned_at: nil)
      expect(user.is_banned?).to be false
    end
  end

  describe '#is_wiped?' do
    it 'returns true if the user is wiped' do
      user = create(:user, password_digest: '*')
      expect(user.is_wiped?).to be true
    end

    it 'returns false if the user is not wiped' do
      user = create(:user, password_digest: 'password')
      expect(user.is_wiped?).to be false
    end
  end

  describe '#ids_replied_to' do
    it 'returns a hash of comment IDs the user has replied to' do
      user = create(:user)
      comment1 = create(:comment, user: user)
      comment2 = create(:comment, user: user)
      reply = create(:comment, parent_comment_id: comment1.id, user: user)

      result = user.ids_replied_to([comment1.id, comment2.id])
      expect(result[comment1.id]).to be true
      expect(result[comment2.id]).to be false
    end
  end

  describe '#roll_session_token' do
    it 'generates a new session token' do
      user = create(:user, session_token: 'old_token')
      user.roll_session_token
      expect(user.session_token).not_to eq('old_token')
    end
  end

  describe '#is_heavy_self_promoter?' do
    it 'returns true if the user is a heavy self promoter' do
      user = create(:user)
      create_list(:story, 2, user: user, user_is_author: true)

      expect(user.is_heavy_self_promoter?).to be true
    end

    it 'returns false if the user is not a heavy self promoter' do
      user = create(:user)
      create_list(:story, 2, user: user, user_is_author: false)

      expect(user.is_heavy_self_promoter?).to be false
    end
  end

  describe '#linkified_about' do
    it 'returns the linkified about text' do
      user = create(:user, about: 'Check out [this link](https://example.com)')
      expect(user.linkified_about).to include('<a href="https://example.com">this link</a>')
    end
  end

  describe '#mastodon_acct' do
    it 'returns the mastodon account string' do
      user = create(:user, mastodon_username: 'user', mastodon_instance: 'mastodon.social')
      expect(user.mastodon_acct).to eq('@user@mastodon.social')
    end
  end

  describe '#most_common_story_tag' do
    it 'returns the most common story tag' do
      user = create(:user)
      tag1 = create(:tag)
      tag2 = create(:tag)
      create(:story, user: user, tags: [tag1])
      create(:story, user: user, tags: [tag1, tag2])

      expect(user.most_common_story_tag).to eq(tag1)
    end
  end

  describe '#pushover!' do
    it 'sends a pushover notification if the user has a pushover user key' do
      user = create(:user, pushover_user_key: 'user_key')
      params = { message: 'Test message' }

      expect(Pushover).to receive(:push).with('user_key', params)
      user.pushover!(params)
    end

    it 'does not send a pushover notification if the user does not have a pushover user key' do
      user = create(:user, pushover_user_key: nil)
      params = { message: 'Test message' }

      expect(Pushover).not_to receive(:push)
      user.pushover!(params)
    end
  end

  describe '#recent_threads' do
    it 'returns recent thread IDs' do
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

  describe '#unban_by_user!' do
    it 'unbans the user and creates a moderation record' do
      user = create(:user, banned_at: Time.current, banned_by_user_id: 1, banned_reason: 'Spamming')
      unbanner = create(:user)

      expect {
        user.unban_by_user!(unbanner, 'Reformed')
      }.to change { user.banned_at }.to(nil)
        .and change { user.banned_by_user_id }.to(nil)
        .and change { user.banned_reason }.to(nil)
        .and change { Moderation.count }.by(1)

      moderation = Moderation.last
      expect(moderation.moderator_user_id).to eq(unbanner.id)
      expect(moderation.user_id).to eq(user.id)
      expect(moderation.action).to eq('Unbanned')
      expect(moderation.reason).to eq('Reformed')
    end
  end

  describe '#enable_invite_by_user!' do
    it 'enables invite privileges and creates a moderation record' do
      user = create(:user, disabled_invite_at: Time.current, disabled_invite_by_user_id: 1, disabled_invite_reason: 'Violation')
      mod = create(:user)

      expect {
        user.enable_invite_by_user!(mod)
      }.to change { user.disabled_invite_at }.to(nil)
        .and change { user.disabled_invite_by_user_id }.to(nil)
        .and change { user.disabled_invite_reason }.to(nil)
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
    it 'returns votes for others' do
      user = create(:user)
      other_user = create(:user)
      story = create(:story, user: other_user)
      vote = create(:vote, user: user, story: story)

      expect(user.votes_for_others).to include(vote)
    end
  end
end