require "rails_helper"

describe User do
  it "has a valid username" do
    expect { create(:user, username: nil) }.to raise_error
    expect { create(:user, username: "") }.to raise_error
    expect { create(:user, username: "*") }.to raise_error
    # security controls, usernames are used in queries and filenames
    expect { create(:user, username: "a'b") }.to raise_error
    expect { create(:user, username: "a\"b") }.to raise_error
    expect { create(:user, username: "../b") }.to raise_error

    create(:user, username: "newbie")
    expect { create(:user, username: "newbie") }.to raise_error

    create(:user, username: "underscores_and-dashes")
    invalid_username_variants = ["underscores-and_dashes", "underscores_and_dashes", "underscores-and-dashes"]

    invalid_username_variants.each do |invalid_username|
      subject = build(:user, username: invalid_username)
      expect(subject).to_not be_valid
      expect(subject.errors[:username]).to eq(["is already in use (perhaps swapping _ and -)"])
    end

    create(:user, username: "case_insensitive")
    expect { create(:user, username: "CASE_INSENSITIVE") }.to raise_error
    expect { create(:user, username: "case_Insensitive") }.to raise_error
    expect { create(:user, username: "case-insensITive") }.to raise_error
  end

  it "has a valid email address" do
    create(:user, email: "user@example.com")

    # duplicate
    expect { create(:user, email: "user@example.com") }.to raise_error

    # bad address
    expect { create(:user, email: "user@") }.to raise_error

    # address too long
    expect(build(:user, email: "a" * 95 + "@example.com")).to_not be_valid

    # not a disposable email
    allow(File).to receive(:read).with(FetchEmailBlocklistJob::STORAGE_PATH).and_return("disposable.com")
    expect(build(:user, email: "user@disposable.com")).to_not be_valid
  end

  it "has a limit on the password reset token field" do
    user = build(:user, password_reset_token: "a" * 100)
    user.valid?
    expect(user.errors[:password_reset_token]).to eq(["is too long (maximum is 75 characters)"])
  end

  it "has a limit on the session token field" do
    user = build(:user, session_token: "a" * 100)
    user.valid?
    expect(user.errors[:session_token]).to eq(["is too long (maximum is 75 characters)"])
  end

  it "has a limit on the about field" do
    user = build(:user, about: "a" * 16_777_218)
    user.valid?
    expect(user.errors[:about]).to eq(["is too long (maximum is 16777215 characters)"])
  end

  it "has a limit on the rss token field" do
    user = build(:user, rss_token: "a" * 100)
    user.valid?
    expect(user.errors[:rss_token]).to eq(["is too long (maximum is 75 characters)"])
  end

  it "has a limit on the mailing list token field" do
    user = build(:user, mailing_list_token: "a" * 100)
    user.valid?
    expect(user.errors[:mailing_list_token]).to eq(["is too long (maximum is 75 characters)"])
  end

  it "has a limit on the banned reason field" do
    user = build(:user, banned_reason: "a" * 300)
    user.valid?
    expect(user.errors[:banned_reason]).to eq(["is too long (maximum is 256 characters)"])
  end

  it "has a limit on the disabled invite reason field" do
    user = build(:user, disabled_invite_reason: "a" * 300)
    user.valid?
    expect(user.errors[:disabled_invite_reason]).to eq(["is too long (maximum is 200 characters)"])
  end

  it "has a valid homepage" do
    expect(build(:user, homepage: "https://lobste.rs")).to be_valid
    expect(build(:user, homepage: "https://lobste.rs/w00t")).to be_valid
    expect(build(:user, homepage: "https://lobste.rs/w00t.path")).to be_valid
    expect(build(:user, homepage: "https://lobste.rs/w00t")).to be_valid
    expect(build(:user, homepage: "https://ሙዚቃ.et")).to be_valid
    expect(build(:user, homepage: "http://lobste.rs/ሙዚቃ")).to be_valid
    expect(build(:user, homepage: "http://www.lobste.rs/")).to be_valid
    expect(build(:user, homepage: "gemini://www.lobste.rs/")).to be_valid
    expect(build(:user, homepage: "gopher://www.lobste.rs/")).to be_valid

    expect(build(:user, homepage: "http://")).to_not be_valid
    expect(build(:user, homepage: "http://notld")).to_not be_valid
    expect(build(:user, homepage: "http://notld/w00t.path")).to_not be_valid
    expect(build(:user, homepage: "ftp://invalid.protocol")).to_not be_valid
  end

  it "authenticates properly" do
    u = create(:user, password: "hunter2")

    expect(u.password_digest.length).to be > 20

    expect(u.authenticate("hunter2")).to eq(u)
    expect(u.authenticate("hunteR2")).to be false
  end

  it "gets an error message after registering banned name" do
    expect { create(:user, username: "admin") }
      .to raise_error("Validation failed: Username is not permitted")
  end

  it "shows a user is banned or not" do
    u = create(:user, :banned)
    user = create(:user)
    expect(u.is_banned?).to be true
    expect(user.is_banned?).to be false
  end

  it "shows a user is active or not" do
    u = create(:user, :banned)
    user = create(:user)
    expect(u.is_active?).to be false
    expect(user.is_active?).to be true
  end

  it "shows a user is recent or not" do
    user = create(:user, created_at: Time.current)
    expect(user.is_new?).to be true
    user = create(:user, created_at: (User::NEW_USER_DAYS + 1).days.ago)
    expect(user.is_new?).to be false
  end

  it "unbans a user" do
    u = create(:user, :banned)
    expect(u.unban_by_user!(User.first, "seems ok now")).to be true
  end

  it "tells if a user is a heavy self promoter" do
    u = create(:user)

    expect(u.is_heavy_self_promoter?).to be false

    create(:story, title: "ti1", url: "https://a.com/1", user_id: u.id,
      user_is_author: true)
    # require at least 2 stories to be considered heavy self promoter
    expect(u.is_heavy_self_promoter?).to be false

    create(:story, title: "ti2", url: "https://a.com/2", user_id: u.id,
      user_is_author: true)
    # 100% of 2 stories
    expect(u.is_heavy_self_promoter?).to be true

    create(:story, title: "ti3", url: "https://a.com/3", user_id: u.id,
      user_is_author: false)
    # 66.7% of 3 stories
    expect(u.is_heavy_self_promoter?).to be true

    create(:story, title: "ti4", url: "https://a.com/4", user_id: u.id,
      user_is_author: false)
    # 50% of 4 stories
    expect(u.is_heavy_self_promoter?).to be false
  end

  describe ".username_regex_s" do
    it "returns a regex-like string for usernames" do
      s = User.username_regex_s
      expect(s).to be_a(String)
      expect(s).to start_with("/^")
      expect(s).to end_with("$/")
    end
  end

  describe "#as_json" do
    it "includes karma for non-admin users and computed fields" do
      inviter = create(:user, username: "inviter_user")
      user = create(:user,
        about: "hello",
        homepage: "https://example.com",
        invited_by_user: inviter,
        github_username: "ghuser",
        mastodon_username: "mastouser",
        mastodon_instance: "example.social",
        is_admin: false,
        is_moderator: false)

      allow(Markdowner).to receive(:to_html).with("hello").and_return("<p>hello</p>")

      json = user.as_json

      expect(json[:username]).to eq(user.username)
      expect(json[:karma]).to eq(user.karma)
      expect(json[:about]).to eq("<p>hello</p>")
      expect(json[:homepage]).to eq("https://example.com")
      expect(json[:avatar_url]).to include("/avatars/#{user.username}-100.png")
      expect(json[:invited_by_user]).to eq("inviter_user")
      expect(json[:github_username]).to eq("ghuser")
      expect(json[:mastodon_username]).to eq("mastouser")
      expect(json[:is_admin]).to eq(false)
      expect(json[:is_moderator]).to eq(false)
      expect(json[:created_at]).to be_within(5.seconds).of(user.created_at)
    end

    it "excludes karma for admin users" do
      user = create(:user, is_admin: true)
      json = user.as_json
      expect(json).not_to have_key(:karma)
      expect(json[:is_admin]).to eq(true)
    end }
  end

  describe "#authenticate_totp" do
    it "verifies a valid TOTP code" do
      secret = ROTP::Base32.random
      user = create(:user, totp_secret: secret)
      totp = ROTP::TOTP.new(secret)
      code = totp.now
      expect(user.authenticate_totp(code)).to be_truthy
    end

    it "rejects an invalid TOTP code" do
      user = create(:user, totp_secret: ROTP::Base32.random)
      expect(user.authenticate_totp("000000")).to be_falsey
    end
  end

  describe "#avatar_path and #avatar_url" do
    it "returns the expected asset paths" do
      user = create(:user, username: "alice")
      expect(user.avatar_path(50)).to include("/avatars/alice-50.png")
      expect(user.avatar_url(75)).to include("/avatars/alice-75.png")
    end
  end

  describe "#disable_invite_by_user_for_reason!" do
    it "disables inviting, creates a message and a moderation" do
      mod = create(:user)
      user = create(:user)
      expect {
        expect(user.disable_invite_by_user_for_reason!(mod, "abuse")).to be true
      }.to change { Message.count }.by(1).and change { Moderation.count }.by(1)

      user.reload
      expect(user.disabled_invite_at).to be_present
      expect(user.disabled_invite_by_user_id).to eq(mod.id)
      expect(user.disabled_invite_reason).to eq("abuse")

      msg = Message.order(:id).last
      expect(msg.author_user_id).to eq(mod.id)
      expect(msg.recipient_user_id).to eq(user.id)
      expect(msg.subject).to match(/revoked/i)

      m = Moderation.order(:id).last
      expect(m.user_id).to eq(user.id)
      expect(m.moderator_user_id).to eq(mod.id)
      expect(m.action).to eq("Disabled invitations")
      expect(m.reason).to eq("abuse")
    end
  end

  describe "#enable_invite_by_user!" do
    it "re-enables inviting and creates a moderation" do
      mod = create(:user)
      user = create(:user, disabled_invite_at: Time.current, disabled_invite_by_user: mod, disabled_invite_reason: "old")
      expect {
        expect(user.enable_invite_by_user!(mod)).to be true
      }.to change { Moderation.count }.by(1)

      user.reload
      expect(user.disabled_invite_at).to be_nil
      expect(user.disabled_invite_by_user_id).to be_nil
      expect(user.disabled_invite_reason).to be_nil

      m = Moderation.order(:id).last
      expect(m.user_id).to eq(user.id)
      expect(m.moderator_user_id).to eq(mod.id)
      expect(m.action).to eq("Enabled invitations")
    end
  end

  describe "#banned_from_inviting?" do
    it "reflects disabled invite status" do
      user = create(:user, disabled_invite_at: nil)
      expect(user.banned_from_inviting?).to be false
      user.update!(disabled_invite_at: Time.current)
      expect(user.banned_from_inviting?).to be true
    end
  end

  describe "#ban_by_user_for_reason!" do
    it "bans and deletes user, sends notification, and records moderation" do
      banner = create(:user)
      user = create(:user, karma: 10) # avoid good_riddance email reset on negative karma

      allow(BanNotificationMailer).to receive(:notify).and_return(double(deliver_now: true))
      flag_checker = instance_double(FlaggedCommenters, check_list_for: false)
      allow(FlaggedCommenters).to receive(:new).with("90d").and_return(flag_checker)

      expect {
        expect(user.ban_by_user_for_reason!(banner, "spam")).to be true
      }.to change { Moderation.count }.by(1)

      user.reload
      expect(user.banned_at).to be_present
      expect(user.banned_by_user_id).to eq(banner.id)
      expect(user.banned_reason).to eq("spam")
      expect(user.deleted_at).to be_present

      m = Moderation.order(:id).last
      expect(m.user_id).to eq(user.id)
      expect(m.moderator_user_id).to eq(banner.id)
      expect(m.action).to eq("Banned")
      expect(m.reason).to eq("spam")

      expect(BanNotificationMailer).to have_received(:notify).with(user, banner, "spam")
    end
  end

  describe "#can_invite?" do
    it "is true when not banned from inviting and can submit stories" do
      user = create(:user, karma: User::MIN_KARMA_TO_SUBMIT_STORIES)
      expect(user.can_invite?).to be true
    end

    it "is false when banned from inviting" do
      user = create(:user, disabled_invite_at: Time.current, karma: 100)
      expect(user.can_invite?).to be false
    end
  end

  describe "#can_offer_suggestions?" do
    it "requires not-new user and sufficient karma" do
      old_user = create(:user, karma: User::MIN_KARMA_TO_SUGGEST, created_at: (User::NEW_USER_DAYS + 1).days.ago)
      expect(old_user.can_offer_suggestions?).to be true

      new_user = create(:user, karma: 100, created_at: Time.current)
      expect(new_user.can_offer_suggestions?).to be false

      low_karma_user = create(:user, karma: User::MIN_KARMA_TO_SUGGEST - 1, created_at: (User::NEW_USER_DAYS + 1).days.ago)
      expect(low_karma_user.can_offer_suggestions?).to be false
    end
  end

  describe "#can_see_invitation_requests?" do
    it "allows moderators even with low karma" do
      user = create(:user, is_moderator: true, karma: -100)
      expect(user.can_see_invitation_requests?).to be true
    end

    it "allows non-moderators with sufficient karma" do
      user = create(:user, is_moderator: false, karma: User::MIN_KARMA_FOR_INVITATION_REQUESTS)
      expect(user.can_see_invitation_requests?).to be true
    end

    it "disallows users who cannot invite" do
      user = create(:user, disabled_invite_at: Time.current, karma: 999)
      expect(user.can_see_invitation_requests?).to be false
    end
  end

  describe "#can_submit_stories?" do
    it "returns true when karma meets threshold" do
      user = create(:user, karma: User::MIN_KARMA_TO_SUBMIT_STORIES)
      expect(user.can_submit_stories?).to be true
    end

    it "returns false when karma is below threshold" do
      user = create(:user, karma: User::MIN_KARMA_TO_SUBMIT_STORIES - 1)
      expect(user.can_submit_stories?).to be false
    end
  end

  describe "#high_karma?" do
    it "returns true when karma >= threshold" do
      user = create(:user, karma: User::HIGH_KARMA_THRESHOLD)
      expect(user.high_karma?).to be true
    end

    it "returns false when karma < threshold" do
      user = create(:user, karma: User::HIGH_KARMA_THRESHOLD - 1)
      expect(user.high_karma?).to be false
    end
  end

  describe "session and tokens" do
    it "rolls session token before save when blank and generates other tokens" do
      allow(Utils).to receive(:random_str) { |n| "X" * n }

      user = create(:user, session_token: "")
      user.reload

      expect(user.session_token).to eq("X" * 60)
      expect(user.rss_token).to eq("X" * 60)
      expect(user.mailing_list_token).to eq("X" * 10)
    end

    it "roll_session_token sets a random 60-char string" do
      user = create(:user)
      allow(Utils).to receive(:random_str).with(60).and_return("Y" * 60)
      user.roll_session_token
      expect(user.session_token).to eq("Y" * 60)
    end
  end

  describe "2FA helpers" do
    it "has_2fa? and disable_2fa! work" do
      user = create(:user, totp_secret: "abc123")
      expect(user.has_2fa?).to be true
      user.disable_2fa!
      user.reload
      expect(user.has_2fa?).to be false
    end
  end

  describe "#is_wiped?" do
    it "returns true when password_digest is '*'" do
      user = create(:user, password_digest: "*")
      expect(user.is_wiped?).to be true
    end

    it "returns false otherwise" do
      user = create(:user)
      expect(user.is_wiped?).to be false
    end
  end

  describe "#mastodon_acct" do
    it "returns acct string when both username and instance present" do
      user = create(:user, mastodon_username: "alice", mastodon_instance: "mastodon.social")
      expect(user.mastodon_acct).to eq("@alice@mastodon.social")
    end

    it "raises when data is incomplete" do
      user = create(:user, mastodon_username: nil, mastodon_instance: "mastodon.social")
      expect { user.mastodon_acct }.to raise_error(RuntimeError)
    end
  end

  describe "#pushover!" do
    it "sends a push when pushover_user_key present" do
      user = create(:user, pushover_user_key: "user-key-1")
      expect(Pushover).to receive(:push).with("user-key-1", hash_including(title: "Hello"))
      user.pushover!(title: "Hello", message: "World")
    end

    it "does nothing when pushover_user_key blank" do
      user = create(:user, pushover_user_key: nil)
      expect(Pushover).not_to receive(:push)
      user.pushover!(title: "Hello")
    end
  end

  describe "#to_param" do
    it "returns the username" do
      user = create(:user, username: "testuser")
      expect(user.to_param).to eq("testuser")
    end
  end

  describe "#inbox_count" do
    it "counts only unread notifications" do
      user = create(:user)
      create(:notification, user: user, read_at: nil)
      create(:notification, user: user, read_at: Time.current)
      expect(user.inbox_count).to eq(1)
    end
  end

  describe "#grant_moderatorship_by_user!" do
    it "grants moderator, creates moderation and a Sysop hat" do
      actor = create(:user)
      user = create(:user, is_moderator: false)

      expect {
        expect(user.grant_moderatorship_by_user!(actor)).to be true
      }.to change { Moderation.count }.by(1).and change { Hat.count }.by(1)

      user.reload
      expect(user.is_moderator).to be true

      m = Moderation.order(:id).last
      expect(m.user_id).to eq(user.id)
      expect(m.moderator_user_id).to eq(actor.id)
      expect(m.action).to eq("Granted moderator status")

      h = Hat.order(:id).last
      expect(h.user_id).to eq(user.id)
      expect(h.granted_by_user_id).to eq(actor.id)
      expect(h.hat).to eq("Sysop")
    end
  end

  describe "#initiate_password_reset_for_ip" do
    it "sets a token and sends email" do
      user = create(:user)
      mailer_double = double(deliver_now: true)
      expect(PasswordResetMailer).to receive(:password_reset_link).with(user, "127.0.0.1").and_return(mailer_double)

      expect {
        user.initiate_password_reset_for_ip("127.0.0.1")
      }.to change { user.reload.password_reset_token }.from(nil)

      expect(user.password_reset_token).to match(/\A\d{10}-[A-Za-z0-9]{30}\z/)
    end
  end
end
