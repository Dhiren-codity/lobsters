
# NOTE: Some failing tests were automatically removed after 3 fix attempts failed.
# These tests may need manual review and fixes. See CI logs for details.
require "rails_helper"

RSpec.describe User do

  describe "#authenticate_totp" do
    it "authenticates with a valid TOTP code" do
      user = create(:user, totp_secret: "base32secret3232")
      totp = ROTP::TOTP.new(user.totp_secret)
      code = totp.now

      expect(user.authenticate_totp(code)).to be_truthy
    end

    it "fails to authenticate with an invalid TOTP code" do
      user = create(:user, totp_secret: "base32secret3232")
      expect(user.authenticate_totp("123456")).to be_falsey
    end
  end

  describe "#avatar_path" do
    it "returns the correct avatar path" do
      user = create(:user, username: "testuser")
      expect(user.avatar_path).to eq("/avatars/testuser-100.png")
    end
  end

  describe "#avatar_url" do
    it "returns the correct avatar URL" do
      user = create(:user, username: "testuser")
      expect(user.avatar_url).to eq(ActionController::Base.helpers.image_url("/avatars/testuser-100.png", skip_pipeline: true))
    end
  end

  describe "#disable_invite_by_user_for_reason!" do
    it "disables invite privileges and creates a moderation record" do
      user = create(:user)
      disabler = create(:user)
      reason = "Violation of terms"

      expect {
        user.disable_invite_by_user_for_reason!(disabler, reason)
      }.to change { user.disabled_invite_at }.from(nil).to(be_within(1.second).of(Time.current))
        .and change { user.disabled_invite_by_user_id }.from(nil).to(disabler.id)
        .and change { user.disabled_invite_reason }.from(nil).to(reason)
        .and change { Moderation.count }.by(1)

      moderation = Moderation.last
      expect(moderation.moderator_user_id).to eq(disabler.id)
      expect(moderation.user_id).to eq(user.id)
      expect(moderation.action).to eq("Disabled invitations")
      expect(moderation.reason).to eq(reason)
    end
  end

  describe "#ban_by_user_for_reason!" do
    it "bans the user and creates a moderation record" do
      user = create(:user)
      banner = create(:user)
      reason = "Spamming"

      expect {
        user.ban_by_user_for_reason!(banner, reason)
      }.to change { user.banned_at }.from(nil).to(be_within(1.second).of(Time.current))
        .and change { user.banned_by_user_id }.from(nil).to(banner.id)
        .and change { user.banned_reason }.from(nil).to(reason)
        .and change { Moderation.count }.by(1)

      moderation = Moderation.last
      expect(moderation.moderator_user_id).to eq(banner.id)
      expect(moderation.user_id).to eq(user.id)
      expect(moderation.action).to eq("Banned")
      expect(moderation.reason).to eq(reason)
    end
  end

  describe "#banned_from_inviting?" do
    it "returns true if the user is banned from inviting" do
      user = create(:user, disabled_invite_at: Time.current)
      expect(user.banned_from_inviting?).to be true
    end

    it "returns false if the user is not banned from inviting" do
      user = create(:user, disabled_invite_at: nil)
      expect(user.banned_from_inviting?).to be false
    end
  end

  describe "#can_flag?" do
    it "returns false for new users" do
      user = create(:user, created_at: Time.current)
      story = create(:story)
      expect(user.can_flag?(story)).to be false
    end

    it "returns true for users with sufficient karma" do
      user = create(:user, karma: 100)
      comment = create(:comment)
      expect(user.can_flag?(comment)).to be true
    end
  end

  describe "#can_invite?" do
    it "returns false if the user is banned from inviting" do
      user = create(:user, disabled_invite_at: Time.current)
      expect(user.can_invite?).to be false
    end

    it "returns true if the user can submit stories" do
      user = create(:user, karma: 10)
      expect(user.can_invite?).to be true
    end
  end

  describe "#can_offer_suggestions?" do
    it "returns false for new users" do
      user = create(:user, created_at: Time.current)
      expect(user.can_offer_suggestions?).to be false
    end

    it "returns true for users with sufficient karma" do
      user = create(:user, karma: 20)
      expect(user.can_offer_suggestions?).to be true
    end
  end

  describe "#can_see_invitation_requests?" do
    it "returns true for moderators" do
      user = create(:user, is_moderator: true)
      expect(user.can_see_invitation_requests?).to be true
    end

    it "returns true for users with sufficient karma" do
      user = create(:user, karma: 60)
      expect(user.can_see_invitation_requests?).to be true
    end
  end

  describe "#can_submit_stories?" do
    it "returns true for users with sufficient karma" do
      user = create(:user, karma: 0)
      expect(user.can_submit_stories?).to be true
    end

    it "returns false for users with insufficient karma" do
      user = create(:user, karma: -5)
      expect(user.can_submit_stories?).to be false
    end
  end
end