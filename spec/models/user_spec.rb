require 'rails_helper'

RSpec.describe User do
  describe '.authenticate_totp' do
    let(:user) { create(:user, totp_secret: 'base32secret3232') }
    let(:totp) { instance_double(ROTP::TOTP) }

    before do
      allow(ROTP::TOTP).to receive(:new).with(user.totp_secret).and_return(totp)
    end

    it 'returns true for a valid TOTP code' do
      allow(totp).to receive(:verify).with('123456').and_return(true)
      expect(user.authenticate_totp('123456')).to be true
    end

    it 'returns false for an invalid TOTP code' do
      allow(totp).to receive(:verify).with('123456').and_return(false)
      expect(user.authenticate_totp('123456')).to be false
    end
  end

  describe '#disable_invite_by_user_for_reason!' do
    let(:user) { create(:user) }
    let(:disabler) { create(:user) }

    it 'disables invite privileges and creates a moderation record' do
      expect {
        user.disable_invite_by_user_for_reason!(disabler, 'Violation of terms')
      }.to change { user.disabled_invite_at }.from(nil).to(be_within(1.second).of(Time.current))
        .and change { user.disabled_invite_by_user_id }.from(nil).to(disabler.id)
        .and change { user.disabled_invite_reason }.from(nil).to('Violation of terms')
        .and change { Moderation.count }.by(1)

      moderation = Moderation.last
      expect(moderation.moderator_user_id).to eq(disabler.id)
      expect(moderation.user_id).to eq(user.id)
      expect(moderation.action).to eq('Disabled invitations')
      expect(moderation.reason).to eq('Violation of terms')
    end
  end

  describe '#ban_by_user_for_reason!' do
    let(:user) { create(:user) }
    let(:banner) { create(:user) }

    it 'bans the user and creates a moderation record' do
      expect {
        user.ban_by_user_for_reason!(banner, 'Spamming')
      }.to change { user.banned_at }.from(nil).to(be_within(1.second).of(Time.current))
        .and change { user.banned_by_user_id }.from(nil).to(banner.id)
        .and change { user.banned_reason }.from(nil).to('Spamming')
        .and change { Moderation.count }.by(1)

      moderation = Moderation.last
      expect(moderation.moderator_user_id).to eq(banner.id)
      expect(moderation.user_id).to eq(user.id)
      expect(moderation.action).to eq('Banned')
      expect(moderation.reason).to eq('Spamming')
    end
  end

  describe '#can_flag?' do
    let(:user) { create(:user, karma: 100) }
    let(:story) { create(:story) }
    let(:comment) { create(:comment) }

    it 'returns true for a flaggable story' do
      allow(story).to receive(:is_flaggable?).and_return(true)
      expect(user.can_flag?(story)).to be true
    end

    it 'returns false for a non-flaggable story' do
      allow(story).to receive(:is_flaggable?).and_return(false)
      expect(user.can_flag?(story)).to be false
    end

    it 'returns true for a flaggable comment' do
      allow(comment).to receive(:is_flaggable?).and_return(true)
      expect(user.can_flag?(comment)).to be true
    end

    it 'returns false for a non-flaggable comment' do
      allow(comment).to receive(:is_flaggable?).and_return(false)
      expect(user.can_flag?(comment)).to be false
    end
  end

  describe '#can_invite?' do
    let(:user) { create(:user, karma: 10) }

    it 'returns true if the user can submit stories and is not banned from inviting' do
      allow(user).to receive(:banned_from_inviting?).and_return(false)
      allow(user).to receive(:can_submit_stories?).and_return(true)
      expect(user.can_invite?).to be true
    end

    it 'returns false if the user is banned from inviting' do
      allow(user).to receive(:banned_from_inviting?).and_return(true)
      expect(user.can_invite?).to be false
    end

    it 'returns false if the user cannot submit stories' do
      allow(user).to receive(:can_submit_stories?).and_return(false)
      expect(user.can_invite?).to be false
    end
  end

  describe '#initiate_password_reset_for_ip' do
    let(:user) { create(:user) }
    let(:ip) { '127.0.0.1' }

    it 'sets a password reset token and sends a password reset email' do
      expect {
        user.initiate_password_reset_for_ip(ip)
      }.to change { user.password_reset_token }.from(nil)

      expect(PasswordResetMailer).to have_received(:password_reset_link).with(user, ip)
    end
  end

  describe '#is_new?' do
    it 'returns true for a user created within the new user period' do
      user = create(:user, created_at: 10.days.ago)
      expect(user.is_new?).to be true
    end

    it 'returns false for a user created outside the new user period' do
      user = create(:user, created_at: 100.days.ago)
      expect(user.is_new?).to be false
    end
  end

  describe '#is_heavy_self_promoter?' do
    let(:user) { create(:user) }

    it 'returns false if the user has not submitted enough stories' do
      allow(user).to receive(:stories_submitted_count).and_return(1)
      expect(user.is_heavy_self_promoter?).to be false
    end

    it 'returns true if the user is a heavy self promoter' do
      allow(user).to receive(:stories_submitted_count).and_return(10)
      allow(user).to receive(:stories).and_return(double(where: double(count: 6)))
      expect(user.is_heavy_self_promoter?).to be true
    end

    it 'returns false if the user is not a heavy self promoter' do
      allow(user).to receive(:stories_submitted_count).and_return(10)
      allow(user).to receive(:stories).and_return(double(where: double(count: 4)))
      expect(user.is_heavy_self_promoter?).to be false
    end
  end
end