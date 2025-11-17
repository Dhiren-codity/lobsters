# WARNING: This test file may contain syntax errors
# Generated after 3 attempts with validation errors
# Last error: ruby: /tmp/tmpyle77mar.rb:640: syntax error, unexpected local variable or method, expecting `end' or dummy end (SyntaxError)
    it "clears disabled invite fields and l...
        ^~~~~~
# Please review and fix any issues before running

# typed: false

require "rails_helper"
require 'spec_helper'

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

  describe "scopes" do
    it "returns only active users for .active" do
      active = create(:user, banned_at: nil, deleted_at: nil)
      banned = create(:user, banned_at: Time.current)
      deleted = create(:user, deleted_at: Time.current)
      expect(User.active).to include(active)
      expect(User.active).to_not include(banned)
      expect(User.active).to_not include(deleted)
    end

    it "returns moderators by is_moderator flag" do
      mod = create(:user, is_moderator: true)
      non_mod = create(:user, is_moderator: false)
      expect(User.moderators).to include(mod)
      expect(User.moderators).to_not include(non_mod)
    end
  end

  describe ".username_regex_s" do
    it "returns a regex string anchored at start and end" do
      s = User.username_regex_s
      expect(s).to start_with("/^")
      expect(s).to end_with("$/")
      expect(s).to include("[A-Za-z0-9][A-Za-z0-9_-]{0,24}")
    end
  end

  describe "#as_json" do
    let(:inviter) { create(:user) }

    before do
      allow(Markdowner).to receive(:to_html).and_return("<p>about</p>")
    end

    it "includes non-admin fields including karma and optional usernames" do
      user = create(:user, invited_by_user: inviter, github_username: "octocat",
        mastodon_username: "mastouser", mastodon_instance: "fosstodon.org")
      allow(user).to receive(:avatar_url).and_return("http://example.com/avatar.png")

      h = user.as_json
      expect(h["username"]).to eq(user.username)
      expect(h["is_admin"]).to eq(user.is_admin)
      expect(h["is_moderator"]).to eq(user.is_moderator)
      expect(h["karma"]).to eq(user.karma)
      expect(h[:about]).to eq("<p>about</p>")
      expect(h[:avatar_url]).to eq("http://example.com/avatar.png")
      expect(h[:invited_by_user]).to eq(inviter.username)
      expect(h[:github_username]).to eq("octocat")
      expect(h[:mastodon_username]).to eq("mastouser")
    end

    it "omits karma for admin users" do
      admin = create(:user, is_admin: true, invited_by_user: inviter)
      allow(admin).to receive(:avatar_url).and_return("http://example.com/a.png")
      h = admin.as_json
      expect(h).to_not have_key("karma")
      expect(h[:invited_by_user]).to eq(inviter.username)
    end
  end

  describe "#authenticate_totp" do
    let(:user) { create(:user, totp_secret: "SECRET") }

    it "delegates to ROTP TOTP verify" do
      totp = instance_double(ROTP::TOTP)
      expect(ROTP::TOTP).to receive(:new).with("SECRET").and_return(totp)
      expect(totp).to receive(:verify).with("123456").and_return(true)
      expect(user.authenticate_totp("123456")).to be true
    end

    it "returns falsey for invalid code" do
      totp = instance_double(ROTP::TOTP)
      allow(ROTP::TOTP).to receive(:new).and_return(totp)
      allow(totp).to receive(:verify).with("000000").and_return(nil)
      expect(user.authenticate_totp("000000")).to be_nil
    end
  end

  describe "#avatar_path and #avatar_url" do
    let(:user) { create(:user, username: "alice") }

    it "builds a path using helpers" do
      expect(ActionController::Base.helpers).to receive(:image_path).with("/avatars/alice-42.png", skip_pipeline: true).and_return("/avatars/alice-42.png")
      expect(user.avatar_path(42)).to eq("/avatars/alice-42.png")
    end

    it "builds a url using helpers" do
      expect(ActionController::Base.helpers).to receive(:image_url).with("/avatars/alice-42.png", skip_pipeline: true).and_return("http://assets/avatars/alice-42.png")
      expect(user.avatar_url(42)).to eq("http://assets/avatars/alice-42.png")
    end
  end

  describe "#disable_invite_by_user_for_reason!" do
    let(:disabler) { create(:user) }
    let(:user) { create(:user) }

    it "disables invitations, sends a message, and logs a moderation" do
      result = user.disable_invite_by_user_for_reason!(disabler, "Too many bad invites")
      expect(result).to be true
      user.reload
      expect(user.disabled_invite_at).to be_present
      expect(user.disabled_invite_by_user_id).to eq(disabler.id)
      expect(user.disabled_invite_reason).to eq("Too many bad invites")

      msg = Message.order(:id).last
      expect(msg.author_user_id).to eq(disabler.id)
      expect(msg.recipient_user_id).to eq(user.id)
      expect(msg.subject).to eq("Your invite privileges have been revoked")
      expect(msg.body).to include("Too many bad invites")
      expect(msg.deleted_by_author).to be true

      mod = Moderation.order(:id).last
      expect(mod.moderator_user_id).to eq(disabler.id)
      expect(mod.user_id).to eq(user.id)
      expect(mod.action).to eq("Disabled invitations")
      expect(mod.reason).to eq("Too many bad invites")
    end
  end

  describe "#ban_by_user_for_reason!" do
    let(:banner) { create(:user) }

    it "bans the user, emails them, deletes them, and logs moderation" do
      user = create(:user)
      mail = double(deliver_now: true)
      expect(BanNotificationMailer).to receive(:notify).with(user, banner, "spam").and_return(mail)

      result = user.ban_by_user_for_reason!(banner, "spam")
      expect(result).to be true
      user.reload
      expect(user.banned_at).to be_present
      expect(user.banned_by_user_id).to eq(banner.id)
      expect(user.banned_reason).to eq("spam")
      expect(user.deleted_at).to be_present

      mod = Moderation.order(:id).last
      expect(mod.moderator_user_id).to eq(banner.id)
      expect(mod.user_id).to eq(user.id)
      expect(mod.action).to eq("Banned")
      expect(mod.reason).to eq("spam")
    end

    it "does not email if already deleted" do
      user = create(:user, deleted_at: 1.minute.ago)
      expect(BanNotificationMailer).to_not receive(:notify)
      user.ban_by_user_for_reason!(banner, "duplicate")
      expect(user.reload.banned_at).to be_present
    end
  end

  describe "#banned_from_inviting?" do
    it "reflects disabled_invite_at presence" do
      user = create(:user, disabled_invite_at: nil)
      expect(user.banned_from_inviting?).to be false
      user.update!(disabled_invite_at: Time.current)
      expect(user.banned_from_inviting?).to be true
    end
  end

  describe "capabilities" do
    describe "#can_invite?" do
      it "is false when invite is disabled" do
        user = create(:user, disabled_invite_at: Time.current, karma: 100)
        expect(user.can_invite?).to be false
      end

      it "is false when karma below submit threshold" do
        user = create(:user, disabled_invite_at: nil, karma: User::MIN_KARMA_TO_SUBMIT_STORIES - 1)
        expect(user.can_invite?).to be false
      end

      it "is true when not banned and sufficient karma" do
        user = create(:user, disabled_invite_at: nil, karma: User::MIN_KARMA_TO_SUBMIT_STORIES)
        expect(user.can_invite?).to be true
      end
    end

    describe "#can_offer_suggestions?" do
      it "requires not new and minimal karma" do
        old = create(:user, created_at: (User::NEW_USER_DAYS + 1).days.ago, karma: User::MIN_KARMA_TO_SUGGEST)
        expect(old.can_offer_suggestions?).to be true

        low = create(:user, created_at: (User::NEW_USER_DAYS + 1).days.ago, karma: User::MIN_KARMA_TO_SUGGEST - 1)
        expect(low.can_offer_suggestions?).to be false

        new_user = create(:user, created_at: Time.current, karma: 1000)
        expect(new_user.can_offer_suggestions?).to be false
      end
    end

    describe "#can_see_invitation_requests?" do
      it "allows moderators regardless of karma if they can invite" do
        user = create(:user, is_moderator: true, disabled_invite_at: nil, karma: User::MIN_KARMA_TO_SUBMIT_STORIES)
        expect(user.can_see_invitation_requests?).to be true
      end

      it "requires karma for non-moderators" do
        low = create(:user, is_moderator: false, disabled_invite_at: nil,
          karma: User::MIN_KARMA_FOR_INVITATION_REQUESTS - 1,
          created_at: (User::NEW_USER_DAYS + 1).days.ago)
        expect(low.can_see_invitation_requests?).to be false

        high = create(:user, is_moderator: false, disabled_invite_at: nil,
          karma: User::MIN_KARMA_FOR_INVITATION_REQUESTS,
          created_at: (User::NEW_USER_DAYS + 1).days.ago)
        expect(high.can_see_invitation_requests?).to be true
      end
    end

    describe "#can_submit_stories?" do
      it "obeys submit threshold" do
        low = create(:user, karma: User::MIN_KARMA_TO_SUBMIT_STORIES - 1)
        ok = create(:user, karma: User::MIN_KARMA_TO_SUBMIT_STORIES)
        expect(low.can_submit_stories?).to be false
        expect(ok.can_submit_stories?).to be true
      end
    end

    describe "#high_karma?" do
      it "is true for karma >= threshold" do
        a = create(:user, karma: User::HIGH_KARMA_THRESHOLD - 1)
        b = create(:user, karma: User::HIGH_KARMA_THRESHOLD)
        expect(a.high_karma?).to be false
        expect(b.high_karma?).to be true
      end
    end

    describe "#can_flag?" do
      let(:user) { create(:user, created_at: (User::NEW_USER_DAYS + 1).days.ago, karma: 100) }

      it "allows flagging a flaggable story" do
        story = create(:story)
        allow(story).to receive(:is_flaggable?).and_return(true)
        expect(user.can_flag?(story)).to be true
      end

      it "allows unvoting a currently flagged story" do
        story = create(:story)
        allow(story).to receive(:is_flaggable?).and_return(false)
        allow(story).to receive(:current_flagged?).and_return(true)
        expect(user.can_flag?(story)).to be true
      end

      it "requires karma for comments" do
        comment = create(:comment)
        allow(comment).to receive(:is_flaggable?).and_return(true)

        low = create(:user, created_at: (User::NEW_USER_DAYS + 1).days.ago, karma: User::MIN_KARMA_TO_FLAG - 1)
        high = create(:user, created_at: (User::NEW_USER_DAYS + 1).days.ago, karma: User::MIN_KARMA_TO_FLAG)

        expect(low.can_flag?(comment)).to be false
        expect(high.can_flag?(comment)).to be true
      end

      it "returns false for new users" do
        new_user = create(:user, created_at: Time.current, karma: 10_000)
        story = create(:story)
        allow(story).to receive(:is_flaggable?).and_return(true)
        expect(new_user.can_flag?(story)).to be false
      end
    end
  end

  describe "token creation callbacks" do
    it "creates rss and mailing list tokens on create" do
      allow(Utils).to receive(:random_str).with(60).and_return("r" * 60)
      allow(Utils).to receive(:random_str).with(10).and_return("m" * 10)

      user = create(:user)
      expect(user.rss_token).to eq("r" * 60)
      expect(user.mailing_list_token).to eq("m" * 10)
      expect(user.session_token).to be_present
      expect(user.session_token.length).to be > 0
    end
  end

  describe "keystore-backed counters" do
    it "returns posted and deleted comment counts as integers" do
      user = create(:user)
      allow(Keystore).to receive(:value_for).and_return(nil)
      allow(Keystore).to receive(:value_for).with("user:#{user.id}:comments_posted").and_return("5")
      allow(Keystore).to receive(:value_for).with("user:#{user.id}:comments_deleted").and_return("2")

      expect(user.comments_posted_count).to eq(5)
      expect(user.comments_deleted_count).to eq(2)
    end

    it "refresh_counts! writes current counts to keystore" do
      user = create(:user)
      create(:story, user: user)
      create(:story, user: user)
      create(:comment, user: user, is_deleted: false)
      create(:comment, user: user, is_deleted: true)

      expect(Keystore).to receive(:put).with("user:#{user.id}:stories_submitted", 2)
      expect(Keystore).to receive(:put).with("user:#{user.id}:comments_posted", 1)
      expect(Keystore).to receive(:put).with("user:#{user.id}:comments_deleted", 1)
      user.refresh_counts!
    end
  end

  describe "#fetched_avatar" do
    let(:user) { create(:user, email: "user@example.com") }

    it "returns image body when fetched successfully" do
      s = instance_double("Sponge")
      response = double(body: "image-bytes")
      expect(Sponge).to receive(:new).and_return(s)
      expect(s).to receive(:timeout=).with(3)
      expect(s).to receive(:fetch).and_return(response)
      expect(user.fetched_avatar(120)).to eq("image-bytes")
    end

    it "returns nil when fetch errors" do
      s = instance_double("Sponge")
      expect(Sponge).to receive(:new).and_return(s)
      expect(s).to receive(:timeout=).with(3)
      expect(s).to receive(:fetch).and_raise(StandardError.new("network"))
      expect(user.fetched_avatar(80)).to be_nil
    end
  end

  describe "#undelete! and #disable_2fa!" do
    it "restores deleted users" do
      user = create(:user, deleted_at: 1.day.ago)
      user.undelete!
      expect(user.deleted_at).to be_nil
    end

    it "disables 2FA" do
      user = create(:user, totp_secret: "abc")
      user.disable_2fa!
      expect(user.reload.totp_secret).to be_nil
    end
  end

  describe "#good_riddance?" do
    it "overwrites email for negative karma users" do
      user = create(:user, username: "bob", email: "bob@example.com", karma: -1)
      user.good_riddance?
      expect(user.email).to eq("bob@lobsters.example")
    end

    it "does not overwrite email for good standing users" do
      user = create(:user, username: "carol", email: "carol@example.com", karma: 10)
      allow_any_instance_of(FlaggedCommenters).to receive(:check_list_for).and_return(false)
      user.good_riddance?
      expect(user.email).to eq("carol@example.com")
    end
  end

  describe "#grant_moderatorship_by_user!" do
    it "grants moderator status, logs moderation, and gives Sysop hat" do
      granter = create(:user)
      user = create(:user, is_moderator: false)
      result = user.grant_moderatorship_by_user!(granter)
      expect(result).to be true
      expect(user.reload.is_moderator).to be true

      mod = Moderation.order(:id).last
      expect(mod.moderator_user_id).to eq(granter.id)
      expect(mod.user_id).to eq(user.id)
      expect(mod.action).to eq("Granted moderator status")

      hat = Hat.order(:id).last
      expect(hat.user_id).to eq(user.id)
      expect(hat.granted_by_user_id).to eq(granter.id)
      expect(hat.hat).to eq("Sysop")
    end
  end

  describe "#initiate_password_reset_for_ip" do
    it "sets a reset token and sends an email" do
      user = create(:user)
      mail = double(deliver_now: true)
      expect(PasswordResetMailer).to receive(:password_reset_link).with(user, "1.2.3.4").and_return(mail)
      user.initiate_password_reset_for_ip("1.2.3.4")
      expect(user.password_reset_token).to match(/\A\d+-[A-Za-z0-9]{30}\z/)
    end
  end

  describe "#has_2fa?" do
    it "reflects presence of totp_secret" do
      user = create(:user, totp_secret: nil)
      expect(user.has_2fa?).to be false
      user.update!(totp_secret: "xyz")
      expect(user.has_2fa?).to be true
    end
  end

  describe "#is_wiped?" do
    it "is true when password_digest is '*'" do
      user = create(:user)
      user.update_column(:password_digest, "*")
      expect(user.is_wiped?).to be true
    end
  end

  describe "#roll_session_token" do
    it "changes the session_token" do
      user = create(:user)
      old = user.session_token
      allow(Utils).to receive(:random_str).with(60).and_return("z" * 60)
      user.roll_session_token
      expect(user.session_token).to eq("z" * 60)
      expect(user.session_token).to_not eq(old)
    end
  end

  describe "#linkified_about" do
    it "uses Markdowner to convert about" do
      user = create(:user, about: "hello")
      expect(Markdowner).to receive(:to_html).with("hello").and_return("<p>hello</p>")
      expect(user.linkified_about).to eq("<p>hello</p>")
    end
  end

  describe "#mastodon_acct" do
    it "raises when fields are missing" do
      user = create(:user, mastodon_username: nil, mastodon_instance: "example.social")
      expect { user.mastodon_acct }.to raise_error(RuntimeError)
    end

    it "returns the acct when fields present" do
      user = create(:user, mastodon_username: "alice", mastodon_instance: "example.social")
      expect(user.mastodon_acct).to eq("@alice@example.social")
    end
  end

  describe "#most_common_story_tag" do
    it "returns the tag used most often by the user" do
      user = create(:user)
      t1 = create(:tag)
      t2 = create(:tag)
      create(:story, user: user, tags: [t1])
      create(:story, user: user, tags: [t1])
      create(:story, user: user, tags: [t2])
      expect(user.most_common_story_tag).to eq(t1)
    end
  end

  describe "#pushover!" do
    it "sends when key present" do
      user = create(:user, pushover_user_key: "KEY123")
      params = { title: "Hello" }
      expect(Pushover).to receive(:push).with("KEY123", params)
      user.pushover!(params)
    end

    it "does nothing when key missing" do
      user = create(:user, pushover_user_key: nil)
      expect(Pushover).to_not receive(:push)
      user.pushover!(title: "Nothing")
    end
  end

  describe "#to_param" do
    it "returns the username" do
      user = create(:user, username: "paramuser")
      expect(user.to_param).to eq("paramuser")
    end
  end

  describe "#enable_invite_by_user!" do" do
    it "clears disabled invite fields and logs moderation" do
      mod = create(:user)
      user = create(:user, disabled_invite_at: 1.day.ago, disabled_invite_by_user: mod, disabled_invite_reason: "bad")

      expect(user.enable_invite_by_user!(mod)).to be true
      user.reload
      expect(user.disabled_invite_at).to be_nil
      expect(user.disabled_invite_by_user_id).to be_nil
      expect(user.disabled_invite_reason).to be_nil

      m = Moderation.order(:id).last
      expect(m.moderator_user_id).to eq(mod.id)
      expect(m.user_id).to eq(user.id)
      expect(m.action).to eq("Enabled invitations")
    end
  end

  describe "#inbox_count" do
    it "counts unread notifications" do
      user = create(:user)
      create(:notification, user: user, read_at: nil)
      create(:notification, user: user, read_at: nil)
      create(:notification, user: user, read_at: Time.current)
      expect(user.inbox_count).to eq(2)
    end
  end

  describe "#votes_for_others" do
    it "returns only votes on others' stories or comments" do
      voter = create(:user)
      other = create(:user)
      own_story = create(:story, user: voter)
      other_story = create(:story, user: other)
      own_comment = create(:comment, user: voter, story: other_story)
      other_comment = create(:comment, user: other, story: own_story)

      v1 = create(:vote, user: voter, story: other_story, comment: nil)
      v2 = create(:vote, user: voter, story: own_story, comment: nil)
      v3 = create(:vote, user: voter, story: other_story, comment: other_comment)
      v4 = create(:vote, user: voter, story: other_story, comment: own_comment)

      result = voter.votes_for_others.to_a
      expect(result).to include(v1)
      expect(result).to include(v3)
      expect(result).to_not include(v2)
      expect(result).to_not include(v4)
      expect(result).to eq(result.sort_by { |v| -v.id })
    end
  end
end
