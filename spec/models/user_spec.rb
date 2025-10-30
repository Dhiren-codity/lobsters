require 'rails_helper'

RSpec.describe User do
  describe '#disable_invite_by_user_for_reason!' do
    let(:user) { create(:user) }
    let(:disabler) { create(:user) }
    let(:reason) { "Violation of terms" }

    it 'disables invite privileges and creates a message and moderation record' do
      expect {
        user.disable_invite_by_user_for_reason!(disabler, reason)
      }.to change { user.disabled_invite_at }.from(nil).and(
        change { user.disabled_invite_by_user_id }.to(disabler.id)
      ).and(
        change { user.disabled_invite_reason }.to(reason)
      ).and(
        change { Message.count }.by(1)
      ).and(
        change { Moderation.count }.by(1)
      )

      message = Message.last
      expect(message.subject).to eq("Your invite privileges have been revoked")
      expect(message.body).to include(reason)

      moderation = Moderation.last
      expect(moderation.action).to eq("Disabled invitations")
      expect(moderation.reason).to eq(reason)
    end
  end

  describe '#ban_by_user_for_reason!' do
    let(:user) { create(:user) }
    let(:banner) { create(:user) }
    let(:reason) { "Spamming" }

    it 'bans the user and creates a moderation record' do
      expect {
        user.ban_by_user_for_reason!(banner, reason)
      }.to change { user.banned_at }.from(nil).and(
        change { user.banned_by_user_id }.to(banner.id)
      ).and(
        change { user.banned_reason }.to(reason)
      ).and(
        change { Moderation.count }.by(1)
      )

      moderation = Moderation.last
      expect(moderation.action).to eq("Banned")
      expect(moderation.reason).to eq(reason)
    end
  end

  describe '#can_flag?' do
    let(:user) { create(:user, karma: 100) }
    let(:story) { create(:story) }
    let(:comment) { create(:comment) }

    it 'returns false for new users' do
      allow(user).to receive(:is_new?).and_return(true)
      expect(user.can_flag?(story)).to be false
    end

    it 'returns true for flaggable stories' do
      allow(story).to receive(:is_flaggable?).and_return(true)
      expect(user.can_flag?(story)).to be true
    end

    it 'returns true for flaggable comments if karma is sufficient' do
      allow(comment).to receive(:is_flaggable?).and_return(true)
      expect(user.can_flag?(comment)).to be true
    end

    it 'returns false for non-flaggable comments' do
      allow(comment).to receive(:is_flaggable?).and_return(false)
      expect(user.can_flag?(comment)).to be false
    end
  end

  describe '#can_invite?' do
    let(:user) { create(:user, karma: 100) }

    it 'returns true if user is not banned from inviting and can submit stories' do
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

    it 'returns true if user is not new and has sufficient karma' do
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

    it 'returns true if user can invite and has sufficient karma' do
      allow(user).to receive(:can_invite?).and_return(true)
      allow(user).to receive(:is_moderator?).and_return(false)
      expect(user.can_see_invitation_requests?).to be true
    end

    it 'returns false if user cannot invite' do
      allow(user).to receive(:can_invite?).and_return(false)
      expect(user.can_see_invitation_requests?).to be false
    end
  end

  describe '#can_submit_stories?' do
    let(:user) { create(:user, karma: 10) }

    it 'returns true if user has sufficient karma' do
      expect(user.can_submit_stories?).to be true
    end

    it 'returns false if user does not have sufficient karma' do
      user.karma = -5
      expect(user.can_submit_stories?).to be false
    end
  end

  describe '#check_session_token' do
    let(:user) { create(:user, session_token: nil) }

    it 'rolls a new session token if none exists' do
      expect {
        user.check_session_token
      }.to change { user.session_token }.from(nil)
    end
  end

  describe '#create_mailing_list_token' do
    let(:user) { create(:user, mailing_list_token: nil) }

    it 'creates a new mailing list token if none exists' do
      expect {
        user.create_mailing_list_token
      }.to change { user.mailing_list_token }.from(nil)
    end
  end

  describe '#create_rss_token' do
    let(:user) { create(:user, rss_token: nil) }

    it 'creates a new RSS token if none exists' do
      expect {
        user.create_rss_token
      }.to change { user.rss_token }.from(nil)
    end
  end

  describe '#delete!' do
    let(:user) { create(:user) }

    it 'marks the user as deleted and updates related records' do
      expect {
        user.delete!
      }.to change { user.deleted_at }.from(nil)
    end
  end

  describe '#undelete!' do
    let(:user) { create(:user, deleted_at: Time.current) }

    it 'unmarks the user as deleted' do
      expect {
        user.undelete!
      }.to change { user.deleted_at }.to(nil)
    end
  end

  describe '#disable_2fa!' do
    let(:user) { create(:user, totp_secret: 'secret') }

    it 'disables 2FA by clearing the TOTP secret' do
      expect {
        user.disable_2fa!
      }.to change { user.totp_secret }.to(nil)
    end
  end

  describe '#good_riddance?' do
    let(:user) { create(:user, karma: -1) }

    it 'changes the email if karma is negative or recent activity is high' do
      expect {
        user.good_riddance?
      }.to change { user.email }
    end
  end

  describe '#grant_moderatorship_by_user!' do
    let(:user) { create(:user) }
    let(:moderator) { create(:user) }

    it 'grants moderatorship and creates a moderation record' do
      expect {
        user.grant_moderatorship_by_user!(moderator)
      }.to change { user.is_moderator }.from(false).to(true).and(
        change { Moderation.count }.by(1)
      ).and(
        change { Hat.count }.by(1)
      )
    end
  end

  describe '#initiate_password_reset_for_ip' do
    let(:user) { create(:user) }
    let(:ip) { '127.0.0.1' }

    it 'initiates a password reset and sends an email' do
      expect {
        user.initiate_password_reset_for_ip(ip)
      }.to change { user.password_reset_token }.from(nil)
    end
  end

  describe '#has_2fa?' do
    let(:user) { create(:user, totp_secret: 'secret') }

    it 'returns true if TOTP secret is present' do
      expect(user.has_2fa?).to be true
    end

    it 'returns false if TOTP secret is not present' do
      user.totp_secret = nil
      expect(user.has_2fa?).to be false
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

  describe '#is_banned?' do
    let(:user) { create(:user) }

    it 'returns true if user is banned' do
      user.banned_at = Time.current
      expect(user.is_banned?).to be true
    end

    it 'returns false if user is not banned' do
      expect(user.is_banned?).to be false
    end
  end

  describe '#is_wiped?' do
    let(:user) { create(:user, password_digest: '*') }

    it 'returns true if user is wiped' do
      expect(user.is_wiped?).to be true
    end

    it 'returns false if user is not wiped' do
      user.password_digest = 'digest'
      expect(user.is_wiped?).to be false
    end
  end

  describe '#ids_replied_to' do
    let(:user) { create(:user) }
    let(:comment) { create(:comment, user: user) }

    it 'returns a hash of comment ids the user has replied to' do
      expect(user.ids_replied_to([comment.id])).to eq({ comment.id => true })
    end
  end

  describe '#roll_session_token' do
    let(:user) { create(:user, session_token: nil) }

    it 'rolls a new session token' do
      expect {
        user.roll_session_token
      }.to change { user.session_token }.from(nil)
    end
  end

  describe '#linkified_about' do
    let(:user) { create(:user, about: 'This is **bold** text') }

    it 'returns HTML formatted about text' do
      expect(user.linkified_about).to include('<strong>bold</strong>')
    end
  end

  describe '#mastodon_acct' do
    let(:user) { create(:user, mastodon_username: 'user', mastodon_instance: 'instance') }

    it 'returns the mastodon account string' do
      expect(user.mastodon_acct).to eq('@user@instance')
    end
  end

  describe '#most_common_story_tag' do
    let(:user) { create(:user) }
    let(:tag) { create(:tag) }
    let!(:story) { create(:story, user: user, tags: [tag]) }

    it 'returns the most common story tag' do
      expect(user.most_common_story_tag).to eq(tag)
    end
  end

  describe '#pushover!' do
    let(:user) { create(:user, pushover_user_key: 'key') }
    let(:params) { { message: 'Test' } }

    it 'sends a pushover notification if user key is present' do
      expect(Pushover).to receive(:push).with('key', params)
      user.pushover!(params)
    end

    it 'does not send a pushover notification if user key is not present' do
      user.pushover_user_key = nil
      expect(Pushover).not_to receive(:push)
      user.pushover!(params)
    end
  end

  describe '#recent_threads' do
    let(:user) { create(:user) }
    let(:comment) { create(:comment, user: user) }

    it 'returns recent thread ids' do
      expect(user.recent_threads(1)).to include(comment.thread_id)
    end
  end

  describe '#stories_submitted_count' do
    let(:user) { create(:user) }

    it 'returns the count of stories submitted by the user' do
      expect(user.stories_submitted_count).to eq(0)
    end
  end

  describe '#stories_deleted_count' do
    let(:user) { create(:user) }

    it 'returns the count of stories deleted by the user' do
      expect(user.stories_deleted_count).to eq(0)
    end
  end

  describe '#unban_by_user!' do
    let(:user) { create(:user, banned_at: Time.current) }
    let(:unbanner) { create(:user) }
    let(:reason) { "Mistake" }

    it 'unbans the user and creates a moderation record' do
      expect {
        user.unban_by_user!(unbanner, reason)
      }.to change { user.banned_at }.to(nil).and(
        change { Moderation.count }.by(1)
      )

      moderation = Moderation.last
      expect(moderation.action).to eq("Unbanned")
      expect(moderation.reason).to eq(reason)
    end
  end

  describe '#enable_invite_by_user!' do
    let(:user) { create(:user, disabled_invite_at: Time.current) }
    let(:mod) { create(:user) }

    it 'enables invite privileges and creates a moderation record' do
      expect {
        user.enable_invite_by_user!(mod)
      }.to change { user.disabled_invite_at }.to(nil).and(
        change { Moderation.count }.by(1)
      )

      moderation = Moderation.last
      expect(moderation.action).to eq("Enabled invitations")
    end
  end

  describe '#inbox_count' do
    let(:user) { create(:user) }
    let!(:notification) { create(:notification, user: user, read_at: nil) }

    it 'returns the count of unread notifications' do
      expect(user.inbox_count).to eq(1)
    end
  end

  describe '#votes_for_others' do
    let(:user) { create(:user) }
    let(:story) { create(:story, user: create(:user)) }
    let!(:vote) { create(:vote, user: user, story: story) }

    it 'returns votes for others' do
      expect(user.votes_for_others).to include(vote)
    end
  end
end