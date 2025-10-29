require 'rails_helper'

RSpec.describe User do
  describe "#disable_invite_by_user_for_reason!" do
    let(:user) { create(:user) }
    let(:disabler) { create(:user) }
    let(:reason) { "Violation of terms" }

    it "disables invite privileges and creates a moderation record" do
      expect {
        user.disable_invite_by_user_for_reason!(disabler, reason)
      }.to change { user.disabled_invite_at }.from(nil).and change { user.disabled_invite_by_user_id }.to(disabler.id)

      expect(user.disabled_invite_reason).to eq(reason)
      expect(user.invitations).to be_empty
      expect(Moderation.last.action).to eq("Disabled invitations")
    end
  end

  describe "#ban_by_user_for_reason!" do
    let(:user) { create(:user) }
    let(:banner) { create(:user) }
    let(:reason) { "Spamming" }

    it "bans the user and creates a moderation record" do
      expect {
        user.ban_by_user_for_reason!(banner, reason)
      }.to change { user.banned_at }.from(nil).and change { user.banned_by_user_id }.to(banner.id)

      expect(user.banned_reason).to eq(reason)
      expect(user.deleted_at).not_to be_nil
      expect(Moderation.last.action).to eq("Banned")
    end
  end

  describe "#can_flag?" do
    let(:user) { create(:user, karma: 100) }
    let(:story) { create(:story) }
    let(:comment) { create(:comment) }

    it "returns true for flaggable story" do
      allow(story).to receive(:is_flaggable?).and_return(true)
      expect(user.can_flag?(story)).to be true
    end

    it "returns false for non-flaggable story" do
      allow(story).to receive(:is_flaggable?).and_return(false)
      expect(user.can_flag?(story)).to be false
    end

    it "returns true for flaggable comment" do
      allow(comment).to receive(:is_flaggable?).and_return(true)
      expect(user.can_flag?(comment)).to be true
    end

    it "returns false for non-flaggable comment" do
      allow(comment).to receive(:is_flaggable?).and_return(false)
      expect(user.can_flag?(comment)).to be false
    end
  end

  describe "#can_invite?" do
    let(:user) { create(:user, karma: 10) }

    it "returns true if user can submit stories and is not banned from inviting" do
      allow(user).to receive(:banned_from_inviting?).and_return(false)
      allow(user).to receive(:can_submit_stories?).and_return(true)
      expect(user.can_invite?).to be true
    end

    it "returns false if user is banned from inviting" do
      allow(user).to receive(:banned_from_inviting?).and_return(true)
      expect(user.can_invite?).to be false
    end
  end

  describe "#can_offer_suggestions?" do
    let(:user) { create(:user, karma: 15) }

    it "returns true if user is not new and has enough karma" do
      allow(user).to receive(:is_new?).and_return(false)
      expect(user.can_offer_suggestions?).to be true
    end

    it "returns false if user is new" do
      allow(user).to receive(:is_new?).and_return(true)
      expect(user.can_offer_suggestions?).to be false
    end
  end

  describe "#can_see_invitation_requests?" do
    let(:user) { create(:user, karma: 60, is_moderator: false) }

    it "returns true if user can invite and is a moderator" do
      allow(user).to receive(:can_invite?).and_return(true)
      user.is_moderator = true
      expect(user.can_see_invitation_requests?).to be true
    end

    it "returns true if user can invite and has enough karma" do
      allow(user).to receive(:can_invite?).and_return(true)
      expect(user.can_see_invitation_requests?).to be true
    end

    it "returns false if user cannot invite" do
      allow(user).to receive(:can_invite?).and_return(false)
      expect(user.can_see_invitation_requests?).to be false
    end
  end

  describe "#can_submit_stories?" do
    let(:user) { create(:user, karma: 5) }

    it "returns true if user has enough karma" do
      user.karma = 10
      expect(user.can_submit_stories?).to be true
    end

    it "returns false if user does not have enough karma" do
      expect(user.can_submit_stories?).to be false
    end
  end

  describe "#disable_2fa!" do
    let(:user) { create(:user, totp_secret: "some_secret") }

    it "disables 2FA by clearing the totp_secret" do
      user.disable_2fa!
      expect(user.totp_secret).to be_nil
    end
  end

  describe "#enable_invite_by_user!" do
    let(:user) { create(:user, disabled_invite_at: Time.current) }
    let(:mod) { create(:user) }

    it "enables invite privileges and creates a moderation record" do
      expect {
        user.enable_invite_by_user!(mod)
      }.to change { user.disabled_invite_at }.to(nil)

      expect(user.disabled_invite_by_user_id).to be_nil
      expect(user.disabled_invite_reason).to be_nil
      expect(Moderation.last.action).to eq("Enabled invitations")
    end
  end

  describe "#initiate_password_reset_for_ip" do
    let(:user) { create(:user) }
    let(:ip) { "127.0.0.1" }

    it "sets a password reset token and sends an email" do
      expect(PasswordResetMailer).to receive_message_chain(:password_reset_link, :deliver_now)
      user.initiate_password_reset_for_ip(ip)
      expect(user.password_reset_token).not_to be_nil
    end
  end

  describe "#refresh_counts!" do
    let(:user) { create(:user) }

    it "updates the keystore with the correct counts" do
      expect(Keystore).to receive(:put).with("user:#{user.id}:stories_submitted", user.stories.count)
      expect(Keystore).to receive(:put).with("user:#{user.id}:comments_posted", user.comments.active.count)
      expect(Keystore).to receive(:put).with("user:#{user.id}:comments_deleted", user.comments.deleted.count)
      user.refresh_counts!
    end
  end

  describe "#undelete!" do
    let(:user) { create(:user, deleted_at: Time.current) }

    it "restores a deleted user" do
      user.undelete!
      expect(user.deleted_at).to be_nil
    end
  end
end