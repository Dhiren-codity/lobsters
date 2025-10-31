require 'rails_helper'

RSpec.describe User do
  describe '#as_json' do
    it 'returns the correct JSON representation for a non-admin user' do
      user = create(:user, is_admin: false, github_username: 'gh_user', mastodon_username: 'mastodon_user')
      json = user.as_json

      expect(json[:username]).to eq(user.username)
      expect(json[:created_at]).to eq(user.created_at)
      expect(json[:is_admin]).to eq(false)
      expect(json[:karma]).to eq(user.karma)
      expect(json[:homepage]).to eq(user.homepage)
      expect(json[:about]).to eq(user.linkified_about)
      expect(json[:avatar_url]).to eq(user.avatar_url)
      expect(json[:invited_by_user]).to eq(User.where(id: user.invited_by_user_id).pick(:username))
      expect(json[:github_username]).to eq('gh_user')
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
      expect(user.avatar_path(100)).to eq('/avatars/testuser-100.png')
    end
  end

  describe '#avatar_url' do
    it 'returns the correct avatar URL' do
      user = create(:user, username: 'testuser')
      expect(user.avatar_url(100)).to eq(ActionController::Base.helpers.image_url('/avatars/testuser-100.png'))
    end
  end

  describe '#disable_invite_by_user_for_reason!' do
    it 'disables invite privileges and logs the action' do
      user = create(:user)
      disabler = create(:user)
      reason = 'Violation of terms'

      expect {
        user.disable_invite_by_user_for_reason!(disabler, reason)
      }.to change { user.disabled_invite_at }.from(nil).to(be_within(1.second).of(Time.current))

      expect(user.disabled_invite_by_user_id).to eq(disabler.id)
      expect(user.disabled_invite_reason).to eq(reason)
      expect(user.invitations).to be_empty
    end
  end

  describe '#ban_by_user_for_reason!' do
    it 'bans the user and logs the action' do
      user = create(:user)
      banner = create(:user)
      reason = 'Spamming'

      expect {
        user.ban_by_user_for_reason!(banner, reason)
      }.to change { user.banned_at }.from(nil).to(be_within(1.second).of(Time.current))

      expect(user.banned_by_user_id).to eq(banner.id)
      expect(user.banned_reason).to eq(reason)
      expect(user.deleted_at).to be_present
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
      comment = create(:comment, is_flaggable: true)
      expect(user.can_flag?(comment)).to be true
    end
  end

  describe '#can_invite?' do
    it 'returns true if the user can invite' do
      user = create(:user, karma: 10)
      expect(user.can_invite?).to be true
    end

    it 'returns false if the user is banned from inviting' do
      user = create(:user, disabled_invite_at: Time.current)
      expect(user.can_invite?).to be false
    end
  end

  describe '#can_offer_suggestions?' do
    it 'returns true if the user can offer suggestions' do
      user = create(:user, karma: 20)
      expect(user.can_offer_suggestions?).to be true
    end

    it 'returns false if the user is new' do
      user = create(:user, created_at: Time.current)
      expect(user.can_offer_suggestions?).to be false
    end
  end

  describe '#can_see_invitation_requests?' do
    it 'returns true if the user can see invitation requests' do
      user = create(:user, karma: 60)
      expect(user.can_see_invitation_requests?).to be true
    end

    it 'returns false if the user cannot invite' do
      user = create(:user, disabled_invite_at: Time.current)
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
      expect(user.session_token).to be_present
    end
  end
end