require 'rails_helper'

# typed: false

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
    it "returns a regex string representation with anchors" do
      s = User.username_regex_s
      expect(s).to start_with("/^")
      expect(s).to end_with("$/")
    end
  end

  describe "#as_json" do
    it "includes karma for non-admin and computed fields" do
      inviter = create(:user)
      user = create(:user, invited_by_user: inviter, about: "about text", github_username: "octocat", homepage: "https://lobste.rs")
      allow(Markdowner).to receive(:to_html).with("about text").and_return("<p>about text</p>")

      result = user.as_json

      expect(result).to include("username", "created_at", "is_admin", "is_moderator", "karma", "homepage")
      expect(result[:about]).to eq("<p>about text</p>")
      expect(result[:avatar_url]).to include("/avatars/#{user.username}-100.png")
      expect(result[:invited_by_user]).to eq(inviter.username)
      expect(result[:github_username]).to eq("octocat")
      expect(result).not_to have_key(:mastodon_username)
    end

    it "excludes karma for admin users" do
      admin = create(:user, is_admin: true, about: "x")
      allow(Markdowner).to receive(:to_html).with("x").and_return("HTML")

      result = admin.as_json
      expect(result).to include("username", "created_at", "is_admin", "is_moderator", "homepage")
      expect(result).not_to have_key("karma")
      expect(result[:about]).to eq("HTML")
    end

    it "includes mastodon username only when present" do
      u = create(:user, mastodon_username: "alice", mastodon_instance: "example.social", about: "")
      allow(Markdowner).to receive(:to_html).with("").and_return("")
      res = u.as_json
      expect(res[:mastodon_username]).to eq("alice")

      u2 = create(:user, about: "")
      allow(Markdowner).to receive(:to_html).with("").and_return("")
      res2 = u2.as_json
      expect(res2).not_to have_key(:mastodon_username)
    end
  end

  describe "#authenticate_totp" do
    it "verifies a correct TOTP and rejects an incorrect one" do
      secret = ROTP::Base32.random_base32
      user = create(:user, totp_secret: secret)
      totp = ROTP::TOTP.new(secret)

      expect(user.authenticate_totp(totp.now)).to be_truthy
      expect(user.authenticate_totp("000000")).to be_falsey
    end
  end

  describe "#avatar_path and #avatar_url" do
    it "returns deterministic avatar path and url for sizes" do
      user = build(:user, username: "alice")
      expect(user.avatar_path(80)).to eq("/avatars/alice-80.png")
      expect(user.avatar_url(80)).to include("/avatars/alice-80.png")
    end
  end

  describe "#disable_invite_by_user_for_reason!" do
    it "disables invites, sends a message, and logs a moderation" do
      user = create(:user)
      mod = create(:user)
      reason = "abuse of invites"

      expect {
        user.disable_invite_by_user_for_reason!(mod, reason)
      }.to change { Message.count }.by(1).and change { Moderation.count }.by(1)

      user.reload
      expect(user.disabled_invite_at).to be_present
      expect(user.disabled_invite_by_user_id).to eq(mod.id)
      expect(user.disabled_invite_reason).to eq(reason)

      msg = Message.order(:id).last
      expect(msg.deleted_by_author).to be true
      expect(msg.author_user_id).to eq(mod.id)
      expect(msg.recipient_user_id).to eq(user.id)
      expect(msg.subject).to include("invite privileges")
      expect(msg.body).to include(reason)

      modrec = Moderation.order(:id).last
      expect(modrec.user_id).to eq(user.id)
      expect(modrec.moderator_user_id).to eq(mod.id)
      expect(modrec.action).to eq("Disabled invitations")
      expect(modrec.reason).to eq(reason)
    end
  end

  describe "#ban_by_user_for_reason!" do>
    it "bans user, sends notification, deletes account, and logs moderation" do
      banner = create(:user)
      user = create(:user)

      mailer_double = double(deliver_now: true)
      expect(BanNotificationMailer).to receive(:notify).with(user, banner, "bad behavior").and_return(mailer_double)

      expect {
        user.ban_by_user_for_reason!(banner, "bad behavior")
      }.to change { Moderation.count }.by(1)

      user.reload
      expect(user.banned_at).to be_present
      expect(user.banned_by_user_id).to eq(banner.id)
      expect(user.banned_reason).to eq("bad behavior")
      expect(user.deleted_at).to be_present

      mod = Moderation.order(:id).last
      expect(mod.user_id).to eq(user.id)
      expect(mod.moderator_user_id).to eq(banner.id)
      expect(mod.action).to eq("Banned")
      expect(mod.reason).to eq("bad behavior")
    end
  end

  describe "#banned_from_inviting?" do
    it "reflects disabled invite state" do
      u = create(:user)
      expect(u.banned_from_inviting?).to be false
      u.update!(disabled_invite_at: Time.current)
      expect(u.banned_from_inviting?).to be true
    end
  end

  describe "#can_invite?" do
    it "requires not banned from inviting and sufficient karma" do
      u = create(:user, karma: -5)
      expect(u.can_invite?).to be false

      u.update!(karma: -4)
      expect(u.can_invite?).to be true

      u.update!(disabled_invite_at: Time.current)
      expect(u.can_invite?).to be false
    end
  end

  describe "#can_offer_suggestions?" do
    it "requires not new user and minimum karma" do
      u = create(:user, created_at: (User::NEW_USER_DAYS + 1).days.ago, karma: 9)
      expect(u.can_offer_suggestions?).to be false
      u.update!(karma: 10)
      expect(u.can_offer_suggestions?).to be true
    end
  end

  describe "#can_see_invitation_requests?" do
    it "requires ability to invite and either moderator or sufficient karma" do
      u = create(:user, karma: -10)
      expect(u.can_see_invitation_requests?).to be false

      u.update!(karma: 0)
      expect(u.can_invite?).to be true
      expect(u.can_see_invitation_requests?).to be false

      u.update!(karma: User::MIN_KARMA_FOR_INVITATION_REQUESTS)
      expect(u.can_see_invitation_requests?).to be true

      mod = create(:user, is_moderator: true, karma: 0)
      expect(mod.can_invite?).to be true
      expect(mod.can_see_invitation_requests?).to be true
    end
  end

  describe "#can_submit_stories?" do
    it "gates by karma threshold" do
      u = create(:user, karma: -5)
      expect(u.can_submit_stories?).to be false
      u.update!(karma: -4)
      expect(u.can_submit_stories?).to be true
    end
  end

  describe "#high_karma?" do
    it "detects high karma users" do
      u = create(:user, karma: User::HIGH_KARMA_THRESHOLD - 1)
      expect(u.high_karma?).to be false
      u.update!(karma: User::HIGH_KARMA_THRESHOLD)
      expect(u.high_karma?).to be true
    end
  end

  describe "session and tokens on create" do
    it "generates session, rss and mailing list tokens" do
      u = build(:user, session_token: nil, rss_token: nil, mailing_list_token: nil)
      u.save!
      expect(u.session_token).to be_present
      expect(u.session_token.length).to be >= 40
      expect(u.rss_token).to be_present
      expect(u.rss_token.length).to eq(60)
      expect(u.mailing_list_token).to be_present
      expect(u.mailing_list_token.length).to eq(10)
    end
  end

  describe "#comments_posted_count and #comments_deleted_count" do
    it "reads from keystore" do
      u = create(:user)
      Keystore.put("user:#{u.id}:comments_posted", 7)
      Keystore.put("user:#{u.id}:comments_deleted", 2)
      expect(u.comments_posted_count).to eq(7)
      expect(u.comments_deleted_count).to eq(2)
    end
  end

  describe "#stories_submitted_count and #stories_deleted_count" do
    it "reads from keystore" do
      u = create(:user)
      Keystore.put("user:#{u.id}:stories_submitted", 5)
      Keystore.put("user:#{u.id}:stories_deleted", 3)
      expect(u.stories_submitted_count).to eq(5)
      expect(u.stories_deleted_count).to eq(3)
    end
  end

  describe "#refresh_counts!" do
    it "updates keystore counts based on associations" do
      u = create(:user)
      create_list(:story, 2, user: u, is_deleted: false)
      create(:comment, user: u, is_deleted: false)
      create(:comment, user: u, is_deleted: false)
      create(:comment, user: u, is_deleted: true)

      u.refresh_counts!

      expect(Keystore.value_for("user:#{u.id}:stories_submitted").to_i).to eq(2)
      expect(Keystore.value_for("user:#{u.id}:comments_posted").to_i).to eq(2)
      expect(Keystore.value_for("user:#{u.id}:comments_deleted").to_i).to eq(1)
    end
  end

  describe "#delete! and #undelete!" do
    it "marks messages deleted, rolls session, and sets deleted_at; and undelete removes deleted_at" do
      u = create(:user)
      old_session = u.session_token.dup
      other = create(:user)

      sent = create(:message, author: u, recipient: other, deleted_by_author: false)
      recv = create(:message, author: other, recipient: u, deleted_by_recipient: false)

      u.delete!
      u.reload
      expect(u.deleted_at).to be_present
      expect(u.session_token).to be_present
      expect(u.session_token).not_to eq(old_session)

      sent.reload
      recv.reload
      expect(sent.deleted_by_author).to be true
      expect(recv.deleted_by_recipient).to be true

      u.undelete!
      u.reload
      expect(u.deleted_at).to be_nil
    end

    it "applies good_riddance? email policy when negative karma" do
      u = create(:user, karma: -1)
      u.delete!
      u.reload
      expect(u.email).to eq("#{u.username}@lobsters.example")
    end
  end

  describe "#disable_2fa!" do
    it "clears the TOTP secret" do
      u = create(:user, totp_secret: ROTP::Base32.random_base32)
      expect(u.has_2fa?).to be true
      u.disable_2fa!
      u.reload
      expect(u.has_2fa?).to be false
      expect(u.totp_secret).to be_nil
    end
  end

  describe "#grant_moderatorship_by_user!" do
    it "grants mod, creates moderation and a Sysop hat" do
      u = create(:user, is_moderator: false)
      granter = create(:user)

      expect {
        u.grant_moderatorship_by_user!(granter)
      }.to change { Moderation.count }.by(1).and change { Hat.count }.by(1)

      u.reload
      expect(u.is_moderator).to be true

      mod = Moderation.order(:id).last
      expect(mod.user_id).to eq(u.id)
      expect(mod.moderator_user_id).to eq(granter.id)
      expect(mod.action).to eq("Granted moderator status")

      hat = Hat.order(:id).last
      expect(hat.user_id).to eq(u.id)
      expect(hat.granted_by_user_id).to eq(granter.id)
      expect(hat.hat).to eq("Sysop")
    end
  end

  describe "#initiate_password_reset_for_ip" do
    it "sets a reset token and sends a reset email" do
      u = create(:user)
      mailer_double = double(deliver_now: true)
      expect(PasswordResetMailer).to receive(:password_reset_link).with(u, "127.0.0.1").and_return(mailer_double)

      u.initiate_password_reset_for_ip("127.0.0.1")
      u.reload
      expect(u.password_reset_token).to be_present
      expect(u.password_reset_token).to match(/\A\d+-[A-Za-z0-9]+\z/)
    end
  end

  describe "#has_2fa?" do
    it "reflects presence of TOTP secret" do
      u = create(:user, totp_secret: nil)
      expect(u.has_2fa?).to be false
      u.update!(totp_secret: ROTP::Base32.random_base32)
      expect(u.has_2fa?).to be true
    end
  end

  describe "#is_wiped?" do
    it "detects wiped users" do
      u = create(:user)
      expect(u.is_wiped?).to be false
      u.update_column(:password_digest, "*")
      expect(u.is_wiped?).to be true
    end
  end

  describe "#linkified_about" do
    it "delegates to Markdowner" do
      u = create(:user, about: "Hello")
      expect(Markdowner).to receive(:to_html).with("Hello").and_return("<p>Hello</p>")
      expect(u.linkified_about).to eq("<p>Hello</p>")
    end
  end

  describe "#mastodon_acct" do
    it "returns acct string when both present" do
      u = create(:user, mastodon_username: "alice", mastodon_instance: "example.com")
      expect(u.mastodon_acct).to eq("@alice@example.com")
    end

    it "raises when missing data" do
      u1 = create(:user, mastodon_username: nil, mastodon_instance: "example.com")
      expect { u1.mastodon_acct }.to raise_error(RuntimeError)
      u2 = create(:user, mastodon_username: "alice", mastodon_instance: nil)
      expect { u2.mastodon_acct }.to raise_error(RuntimeError)
    end
  end

  describe "#pushover!" do
    it "sends push when key present and does nothing when missing" do
      u = create(:user, pushover_user_key: "key123")
      expect(Pushover).to receive(:push).with("key123", title: "Hi")
      u.pushover!(title: "Hi")

      u2 = create(:user, pushover_user_key: nil)
      expect(Pushover).not_to receive(:push)
      u2.pushover!(message: "ignored")
    end
  end

  describe "#to_param" do
    it "returns the username" do
      u = create(:user, username: "bob")
      expect(u.to_param).to eq("bob")
    end
  end

  describe "#inbox_count" do
    it "counts unread notifications" do
      u = create(:user)
      create_list(:notification, 2, user: u, read_at: nil)
      create(:notification, user: u, read_at: Time.current)
      expect(u.inbox_count).to eq(2)
    end
  end

  describe "#roll_session_token" do
    it "sets a new random token" do
      u = create(:user)
      old = u.session_token
      u.roll_session_token
      expect(u.session_token).to be_present
      expect(u.session_token).not_to eq(old)
      expect(u.session_token.length).to eq(60)
    end
  end

  describe "#fetched_avatar" do
    it "returns body when fetched successfully and nil on failure" do
      u = create(:user, email: "user@example.com")
      sponge = double
      expect(Sponge).to receive(:new).and_return(sponge)
      expect(sponge).to receive(:timeout=).with(3)
      expect(sponge).to receive(:fetch).and_return(double(body: "PNGDATA"))

      expect(u.fetched_avatar(64)).to eq("PNGDATA")
    end

    it "returns nil when fetch raises" do
      u = create(:user, email: "user@example.com")
      sponge = double
      expect(Sponge).to receive(:new).and_return(sponge)
      expect(sponge).to receive(:timeout=).with(3)
      expect(sponge).to receive(:fetch).and_raise(StandardError)

      expect(u.fetched_avatar(64)).to be_nil
    end
  end

  describe "#most_common_story_tag" do
    it "returns the most frequent tag on user's stories" do
      u = create(:user)
      t1 = create(:tag)
      t2 = create(:tag)
      create(:story, user: u, is_deleted: false, tags: [t1])
      create(:story, user: u, is_deleted: false, tags: [t1])
      create(:story, user: u, is_deleted: false, tags: [t2])

      expect(u.most_common_story_tag).to eq(t1)
    end
  end
end
