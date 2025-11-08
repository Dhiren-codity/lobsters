require 'rails_helper'

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
    it "returns a regex string anchored with ^ and $" do
      s = User.username_regex_s
      expect(s).to be_a(String)
      expect(s).to start_with("/^")
      expect(s).to end_with("$/")
    end
  end

  describe ".slash operator" do
    it "finds a user by username" do
      user = create(:user, username: "finder")
      expect(User./("finder")).to eq(user)
    end

    it "raises for missing user" do
      expect { User./("nope") }.to raise_error(ActiveRecord::RecordNotFound)
    end
  end

  describe "#as_json" do
    it "includes public attributes and computed fields for regular user" do
      inviter = create(:user, username: "inviter")
      user = create(:user,
        invited_by_user_id: inviter.id,
        about: "Hello",
        homepage: "https://lobste.rs",
        github_username: "octocat",
        mastodon_username: "alice",
        mastodon_instance: "example.social",
        karma: 123)

      allow(Markdowner).to receive(:to_html).with("Hello").and_return("<p>Hello</p>")

      json = user.as_json

      expect(json[:about]).to eq("<p>Hello</p>")
      expect(json[:avatar_url]).to include("/avatars/#{user.username}-100.png")
      expect(json[:invited_by_user]).to eq("inviter")
      expect(json[:github_username]).to eq("octocat")
      expect(json[:mastodon_username]).to eq("alice")
      expect(json).to include(:homepage)
      expect(json).to include(:karma)
      expect(json[:is_admin]).to eq(false)
      expect(json[:is_moderator]).to eq(false)
    end

    it "omits karma for admin users" do
      admin = create(:user, is_admin: true, karma: 999)
      json = admin.as_json
      expect(json).not_to have_key(:karma)
      expect(json[:is_admin]).to eq(true)
    end
  end

  describe "#authenticate_totp" do
    it "returns true for a valid TOTP and false for invalid" do
      secret = ROTP::Base32.random_base32
      user = create(:user, settings: { "totp_secret" => secret })
      code = ROTP::TOTP.new(secret).now
      expect(user.authenticate_totp(code)).to be_truthy
      expect(user.authenticate_totp("000000")).to be_falsey
    end
  end

  describe "#avatar_path and #avatar_url" do
    it "builds paths with requested size" do
      user = create(:user, username: "picard")
      expect(user.avatar_path(42)).to include("/avatars/picard-42.png")
      expect(user.avatar_url(42)).to include("/avatars/picard-42.png")
    end
  end

  describe "#banned_from_inviting?" do
    it "returns false when not disabled and true when disabled" do
      u1 = create(:user, disabled_invite_at: nil)
      u2 = create(:user, disabled_invite_at: Time.current)
      expect(u1.banned_from_inviting?).to eq(false)
      expect(u2.banned_from_inviting?).to eq(true)
    end
  end

  describe "#can_submit_stories?" do
    it "allows submitting when karma is at threshold and above" do
      expect(create(:user, karma: User::MIN_KARMA_TO_SUBMIT_STORIES).can_submit_stories?).to eq(true)
      expect(create(:user, karma: User::MIN_KARMA_TO_SUBMIT_STORIES + 1).can_submit_stories?).to eq(true)
    end

    it "disallows submitting below threshold" do
      expect(create(:user, karma: User::MIN_KARMA_TO_SUBMIT_STORIES - 1).can_submit_stories?).to eq(false)
    end
  end

  describe "#high_karma?" do
    it "reflects the threshold" do
      expect(create(:user, karma: User::HIGH_KARMA_THRESHOLD - 1).high_karma?).to eq(false)
      expect(create(:user, karma: User::HIGH_KARMA_THRESHOLD).high_karma?).to eq(true)
      expect(create(:user, karma: User::HIGH_KARMA_THRESHOLD + 1).high_karma?).to eq(true)
    end
  end

  describe "#can_invite?" do
    it "returns true when not banned from inviting and can submit stories" do
      user = create(:user, disabled_invite_at: nil, karma: 0)
      expect(user.can_invite?).to eq(true)
    end

    it "returns false when banned from inviting" do
      user = create(:user, disabled_invite_at: Time.current, karma: 100)
      expect(user.can_invite?).to eq(false)
    end

    it "returns false when cannot submit stories" do
      user = create(:user, karma: User::MIN_KARMA_TO_SUBMIT_STORIES - 1)
      expect(user.can_invite?).to eq(false)
    end
  end

  describe "#can_offer_suggestions?" do
    it "requires not new and sufficient karma" do
      old_enough = create(:user, created_at: (User::NEW_USER_DAYS + 1).days.ago, karma: User::MIN_KARMA_TO_SUGGEST)
      expect(old_enough.can_offer_suggestions?).to eq(true)

      too_new = create(:user, created_at: Time.current, karma: 100)
      expect(too_new.can_offer_suggestions?).to eq(false)

      low_karma = create(:user, created_at: (User::NEW_USER_DAYS + 1).days.ago, karma: User::MIN_KARMA_TO_SUGGEST - 1)
      expect(low_karma.can_offer_suggestions?).to eq(false)
    end
  end

  describe "#can_see_invitation_requests?" do
    it "is true for moderators regardless of karma if they can invite" do
      user = create(:user, is_moderator: true, karma: -4)
      expect(user.can_invite?).to eq(true)
      expect(user.can_see_invitation_requests?).to eq(true)
    end

    it "is true for non-moderators with sufficient karma if they can invite" do
      user = create(:user, is_moderator: false, karma: User::MIN_KARMA_FOR_INVITATION_REQUESTS)
      expect(user.can_invite?).to eq(true)
      expect(user.can_see_invitation_requests?).to eq(true)
    end

    it "is false if the user cannot invite" do
      user = create(:user, disabled_invite_at: Time.current, karma: 10_000)
      expect(user.can_see_invitation_requests?).to eq(false)
    end
  end

  describe "session and tokens creation" do
    it "rolls a session token on save if blank" do
      user = build(:user, session_token: nil)
      expect(user.session_token).to be_nil
      user.save!
      expect(user.session_token).to be_present
      expect(user.session_token.length).to be >= 40
    end

    it "creates mailing_list_token and rss_token on create when blank" do
      user = build(:user, mailing_list_token: nil, rss_token: nil)
      user.save!
      expect(user.mailing_list_token).to be_present
      expect(user.mailing_list_token.length).to eq(10)
      expect(user.rss_token).to be_present
      expect(user.rss_token.length).to eq(60)
    end
  end

  describe "#disable_invite_by_user_for_reason! and #enable_invite_by_user!" do
    it "disables then enables invites, creating moderation entries and a message" do
      mod = create(:user)
      user = create(:user)

      expect {
        expect(user.disable_invite_by_user_for_reason!(mod, "abuse")).to eq(true)
      }.to change { Moderation.count }.by(1)
       .and change { Message.count }.by(1)

      user.reload
      expect(user.disabled_invite_at).to be_present
      expect(user.disabled_invite_by_user_id).to eq(mod.id)
      expect(user.disabled_invite_reason).to eq("abuse")

      msg = Message.order(:id).last
      expect(msg.author_user_id).to eq(mod.id)
      expect(msg.recipient_user_id).to eq(user.id)
      expect(msg.subject).to eq("Your invite privileges have been revoked")
      expect(msg.deleted_by_author).to eq(true)

      expect {
        expect(user.enable_invite_by_user!(mod)).to eq(true)
      }.to change { Moderation.count }.by(1)

      user.reload
      expect(user.disabled_invite_at).to be_nil
      expect(user.disabled_invite_by_user_id).to be_nil
      expect(user.disabled_invite_reason).to be_nil

      moderation = Moderation.order(:id).last
      expect(moderation.action).to eq("Enabled invitations")
      expect(moderation.user_id).to eq(user.id)
      expect(moderation.moderator_user_id).to eq(mod.id)
    end
  end

  describe "#ban_by_user_for_reason!" do
    it "bans, deletes, and creates a moderation; emails the user" do
      banner = create(:user)
      user = create(:user, email: "u@example.com")
      mail_double = double(deliver_now: true)
      expect(BanNotificationMailer).to receive(:notify).with(user, banner, "spam").and_return(mail_double)

      expect {
        expect(user.ban_by_user_for_reason!(banner, "spam")).to eq(true)
      }.to change { Moderation.count }.by(1)

      user.reload
      expect(user.is_banned?).to eq(true)
      expect(user.deleted_at).to be_present

      m = Moderation.order(:id).last
      expect(m.user_id).to eq(user.id)
      expect(m.moderator_user_id).to eq(banner.id)
      expect(m.action).to eq("Banned")
      expect(m.reason).to eq("spam")
    end
  end

  describe "#has_2fa? and #disable_2fa!" do
    it "toggles 2FA presence" do
      user = create(:user, settings: { "totp_secret" => "secret" })
      expect(user.has_2fa?).to eq(true)
      user.disable_2fa!
      user.reload
      expect(user.has_2fa?).to eq(false)
    end
  end

  describe "#mastodon_acct" do
    it "returns acct when both parts present" do
      user = create(:user, settings: { "mastodon_username" => "bob", "mastodon_instance" => "example.social" })
      expect(user.mastodon_acct).to eq("@bob@example.social")
    end

    it "raises when missing parts" do
      user = create(:user, settings: { "mastodon_username" => nil, "mastodon_instance" => "example.social" })
      expect { user.mastodon_acct }.to raise_error(RuntimeError)
    end
  end

  describe "#linkified_about" do
    it "uses Markdowner" do
      user = create(:user, about: "Hi")
      allow(Markdowner).to receive(:to_html).with("Hi").and_return("<p>Hi</p>")
      expect(user.linkified_about).to eq("<p>Hi</p>")
    end
  end

  describe "#to_param" do
    it "returns the username" do
      user = create(:user, username: "paramuser")
      expect(user.to_param).to eq("paramuser")
    end
  end

  describe "#inbox_count" do
    it "returns count of unread notifications" do
      user = create(:user)
      create(:notification, user: user, read_at: nil)
      create(:notification, user: user, read_at: nil)
      create(:notification, user: user, read_at: Time.current)
      expect(user.inbox_count).to eq(2)
    end
  end

  describe "#pushover!" do
    it "pushes when user key present" do
      user = create(:user, settings: { "pushover_user_key" => "key123" })
      params = { title: "Hello" }
      expect(Pushover).to receive(:push).with("key123", params)
      user.pushover!(params)
    end

    it "does nothing when user key missing" do
      user = create(:user, settings: { "pushover_user_key" => nil })
      expect(Pushover).not_to receive(:push)
      user.pushover!({ title: "Hello" })
    end
  end

  describe "keystore-backed counters" do
    it "reads stories/comments counts from Keystore" do
      user = create(:user)
      Keystore.put("user:#{user.id}:stories_submitted", 7)
      Keystore.put("user:#{user.id}:stories_deleted", 3)
      Keystore.put("user:#{user.id}:comments_posted", 9)
      Keystore.put("user:#{user.id}:comments_deleted", 2)

      expect(user.stories_submitted_count).to eq(7)
      expect(user.stories_deleted_count).to eq(3)
      expect(user.comments_posted_count).to eq(9)
      expect(user.comments_deleted_count).to eq(2)
    end
  end

  describe "#fetched_avatar" do
    it "returns body when Sponge fetch succeeds" do
      user = create(:user, email: "user@example.com")
      sponge_double = instance_double(Sponge, timeout: nil)
      allow(Sponge).to receive(:new).and_return(sponge_double)
      allow(sponge_double).to receive(:timeout=).with(3)
      allow(sponge_double).to receive(:fetch).and_return(double(body: "PNGDATA"))
      expect(user.fetched_avatar(80)).to eq("PNGDATA")
    end

    it "returns nil when fetch raises" do
      user = create(:user, email: "user@example.com")
      sponge_double = instance_double(Sponge, timeout: nil)
      allow(Sponge).to receive(:new).and_return(sponge_double)
      allow(sponge_double).to receive(:timeout=).with(3)
      allow(sponge_double).to receive(:fetch).and_raise(StandardError.new("boom"))
      expect(user.fetched_avatar(80)).to be_nil
    end
  end

  describe "#initiate_password_reset_for_ip" do
    it "sets a token and sends a mail" do
      user = create(:user)
      mail_double = double(deliver_now: true)
      expect(PasswordResetMailer).to receive(:password_reset_link).with(user, "1.2.3.4").and_return(mail_double)
      user.initiate_password_reset_for_ip("1.2.3.4")
      expect(user.reload.password_reset_token).to match(/\A\d{10}-[a-zA-Z0-9]{30}\z/)
    end
  end
end
