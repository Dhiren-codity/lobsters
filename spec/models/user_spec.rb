require 'rails_helper'

RSpec.describe User do
  describe '#disable_invite_by_user_for_reason!' do
    let(:user) { create(:user) }
    let(:disabler) { create(:user) }
    let(:reason) { "Violation of terms" }

    it 'disables invite privileges and creates a moderation record' do
      expect {
        user.disable_invite_by_user_for_reason!(disabler, reason)
      }.to change { user.disabled_invite_at }.from(nil).and change { user.disabled_invite_by_user_id }.to(disabler.id)

      expect(user.disabled_invite_reason).to eq(reason)
      expect(user.invitations).to be_empty
      expect(Moderation.last.action).to eq("Disabled invitations")
    end
  end

  describe '#ban_by_user_for_reason!' do
    let(:user) { create(:user) }
    let(:banner) { create(:user) }
    let(:reason) { "Spamming" }

    it 'bans the user and creates a moderation record' do
      expect {
        user.ban_by_user_for_reason!(banner, reason)
      }.to change { user.banned_at }.from(nil).and change { user.banned_by_user_id }.to(banner.id)

      expect(user.banned_reason).to eq(reason)
      expect(user.deleted_at).not_to be_nil
      expect(Moderation.last.action).to eq("Banned")
    end
  end

  describe '#can_flag?' do
    let(:user) { create(:user, karma: 100) }
    let(:story) { create(:story) }
    let(:comment) { create(:comment) }

    it 'returns true for flaggable story' do
      allow(story).to receive(:is_flaggable?).and_return(true)
      expect(user.can_flag?(story)).to be true
    end

    it 'returns false for non-flaggable story' do
      allow(story).to receive(:is_flaggable?).and_return(false)
      expect(user.can_flag?(story)).to be false
    end

    it 'returns true for flaggable comment' do
      allow(comment).to receive(:is_flaggable?).and_return(true)
      expect(user.can_flag?(comment)).to be true
    end

    it 'returns false for non-flaggable comment' do
      allow(comment).to receive(:is_flaggable?).and_return(false)
      expect(user.can_flag?(comment)).to be false
    end
  end

  describe '#can_invite?' do
    let(:user) { create(:user, karma: 100) }

    it 'returns true if user can submit stories and is not banned from inviting' do
      allow(user).to receive(:banned_from_inviting?).and_return(false)
      allow(user).to receive(:can_submit_stories?).and_return(true)
      expect(user.can_invite?).to be true
    end

    it 'returns false if user is banned from inviting' do
      allow(user).to receive(:banned_from_inviting?).and_return(true)
      expect(user.can_invite?).to be false
    end
  end

  describe '#can_offer_suggestions?' do
    let(:user) { create(:user, karma: 100) }

    it 'returns true if user is not new and has enough karma' do
      allow(user).to receive(:is_new?).and_return(false)
      expect(user.can_offer_suggestions?).to be true
    end

    it 'returns false if user is new' do
      allow(user).to receive(:is_new?).and_return(true)
      expect(user.can_offer_suggestions?).to be false
    end
  end

  describe '#can_see_invitation_requests?' do
    let(:user) { create(:user, karma: 100) }

    it 'returns true if user can invite and is a moderator' do
      allow(user).to receive(:can_invite?).and_return(true)
      allow(user).to receive(:is_moderator?).and_return(true)
      expect(user.can_see_invitation_requests?).to be true
    end

    it 'returns false if user cannot invite' do
      allow(user).to receive(:can_invite?).and_return(false)
      expect(user.can_see_invitation_requests?).to be false
    end
  end

  describe '#can_submit_stories?' do
    let(:user) { create(:user, karma: 10) }

    it 'returns true if user has enough karma' do
      expect(user.can_submit_stories?).to be true
    end

    it 'returns false if user does not have enough karma' do
      user.karma = -5
      expect(user.can_submit_stories?).to be false
    end
  end

  describe '#disable_2fa!' do
    let(:user) { create(:user, totp_secret: 'some_secret') }

    it 'disables 2FA by clearing the totp_secret' do
      user.disable_2fa!
      expect(user.totp_secret).to be_nil
    end
  end

  describe '#enable_invite_by_user!' do
    let(:user) { create(:user, disabled_invite_at: Time.current) }
    let(:mod) { create(:user) }

    it 'enables invite privileges and creates a moderation record' do
      expect {
        user.enable_invite_by_user!(mod)
      }.to change { user.disabled_invite_at }.to(nil)

      expect(user.disabled_invite_by_user_id).to be_nil
      expect(user.disabled_invite_reason).to be_nil
      expect(Moderation.last.action).to eq("Enabled invitations")
    end
  end

  describe '#initiate_password_reset_for_ip' do
    let(:user) { create(:user) }
    let(:ip) { '127.0.0.1' }

    it 'sets a password reset token and sends an email' do
      expect(PasswordResetMailer).to receive(:password_reset_link).with(user, ip).and_call_original
      user.initiate_password_reset_for_ip(ip)
      expect(user.password_reset_token).not_to be_nil
    end
  end

  describe '#is_active?' do
    let(:user) { create(:user) }

    it 'returns true if user is not deleted or banned' do
      expect(user.is_active?).to be true
    end

    it 'returns false if user is deleted' do
      user.deleted_at = Time.current
      expect(user.is_active?).to be false
    end

    it 'returns false if user is banned' do
      user.banned_at = Time.current
      expect(user.is_active?).to be false
    end
  end

  describe '#is_wiped?' do
    let(:user) { create(:user, password_digest: '*') }

    it 'returns true if password_digest is "*"' do
      expect(user.is_wiped?).to be true
    end

    it 'returns false if password_digest is not "*"' do
      user.password_digest = 'some_digest'
      expect(user.is_wiped?).to be false
    end
  end

  describe '#mastodon_acct' do
    let(:user) { create(:user, mastodon_username: 'user', mastodon_instance: 'instance') }

    it 'returns the mastodon account string' do
      expect(user.mastodon_acct).to eq('@user@instance')
    end

    it 'raises an error if mastodon_username or mastodon_instance is missing' do
      user.mastodon_username = nil
      expect { user.mastodon_acct }.to raise_error(RuntimeError)
    end
  end

  describe '#most_common_story_tag' do
    let(:user) { create(:user) }
    let(:tag) { create(:tag) }
    let!(:story) { create(:story, user: user, tags: [tag]) }

    it 'returns the most common tag for user stories' do
      expect(user.most_common_story_tag).to eq(tag)
    end
  end

  describe '#pushover!' do
    let(:user) { create(:user, pushover_user_key: 'key') }
    let(:params) { { message: 'Test' } }

    it 'sends a pushover notification if user has a pushover key' do
      expect(Pushover).to receive(:push).with('key', params)
      user.pushover!(params)
    end

    it 'does not send a notification if user does not have a pushover key' do
      user.pushover_user_key = nil
      expect(Pushover).not_to receive(:push)
      user.pushover!(params)
    end
  end

  describe '#recent_threads' do
    let(:user) { create(:user) }
    let(:comment) { create(:comment, user: user) }

    it 'returns recent thread ids for user comments' do
      thread_ids = user.recent_threads(5)
      expect(thread_ids).to include(comment.thread_id)
    end
  end

  describe '#unban_by_user!' do
    let(:user) { create(:user, banned_at: Time.current) }
    let(:unbanner) { create(:user) }
    let(:reason) { "Mistake" }

    it 'unbans the user and creates a moderation record' do
      expect {
        user.unban_by_user!(unbanner, reason)
      }.to change { user.banned_at }.to(nil)

      expect(user.banned_by_user_id).to be_nil
      expect(user.banned_reason).to be_nil
      expect(Moderation.last.action).to eq("Unbanned")
    end
  end

  describe '#votes_for_others' do
    let(:user) { create(:user) }
    let(:other_user) { create(:user) }
    let(:story) { create(:story, user: other_user) }
    let!(:vote) { create(:vote, user: user, story: story) }

    it 'returns votes for others' do
      expect(user.votes_for_others).to include(vote)
    end
  end
end