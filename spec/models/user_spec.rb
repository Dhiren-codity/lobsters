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
    it "returns a regex-like string with anchors" do
      str = described_class.username_regex_s
      expect(str).to start_with("/^")
      expect(str).to end_with("$/")
      expect(str).to include("[A-Za-z0-9")
    end
  end

  describe ". / (operator)" do
    it "finds by username" do
      user = create(:user, username: "alice")
      expect(described_class./("alice")).to eq(user)
    end

    it "raises when not found" do
      expect { described_class./("does-not-exist") }.to raise_error(ActiveRecord::RecordNotFound)
    end
  end

  describe "#as_json" do
    it "includes public fields, linkified about, avatar_url, inviter, and karma for non-admins" do
      inviter = create(:user, username: "inviter")
      user = create(:user, about: "hello", invited_by_user: inviter, karma: 42, is_admin: false)
      allow(Markdowner).to receive(:to_html).with("hello").and_return("<p>hello</p>")

      h = user.as_json

      expect(h["username"]).to eq(user.username)
      expect(h["created_at"]).to be_present
      expect(h["is_admin"]).to eq(false)
      expect(h["is_moderator"]).to eq(false)
      expect(h["karma"]).to eq(42)
      expect((h[:avatar_url] || h["avatar_url"]).to_s).to include("/avatars/#{user.username}-100.png")
      expect(h[:about] || h["about"]).to eq("<p>hello</p>")
      expect(h[:invited_by_user] || h["invited_by_user"]).to eq("inviter")
    end

    it "omits karma for admins and conditionally includes oauth usernames" do
      user = create(:user,
        about: "x",
        is_admin: true,
        github_username: "octocat",
        mastodon_username: "mastouser",
        mastodon_instance: "fosstodon.org")

      allow(Markdowner).to receive(:to_html).and_return("x")

      h = user.as_json

      expect(h["karma"]).to be_nil
      expect(h[:github_username] || h["github_username"]).to eq("octocat")
      expect(h[:mastodon_username] || h["mastodon_username"]).to eq("mastouser")
    end
  end

  describe "#authenticate_totp" do
    it "verifies the correct TOTP code" do
      secret = ROTP::Base32.random_base32
      user = create(:user, totp_secret: secret)
      totp = ROTP::TOTP.new(secret)
      expect(user.authenticate_totp(totp.now)).to be_truthy
      expect(user.authenticate_totp("000000")).to be_falsey
    end
  end

  describe "#avatar_path" do
    it "returns the expected path" do
      user = create(:user, username: "bob")
      expect(user.avatar_path(80)).to include("/avatars/bob-80.png")
    end
  end

  describe "#avatar_url" do
    it "returns the expected url" do
      user = create(:user, username: "carol")
      expect(user.avatar_url(120)).to include("/avatars/carol-120.png")
    end
  end

  describe "#disable_invite_by_user_for_reason!" do
    it "disables invites, sends message, and creates moderation" do
      disabler = create(:user)
      user = create(:user)
      reason = "invites misused"

      expect {
        expect(user.disable_invite_by_user_for_reason!(disabler, reason)).to be true
      }.to change { Moderation.count }.by(1)
         .and change { Message.count }.by(1)

      user.reload
      expect(user.disabled_invite_at).to be_present
      expect(user.disabled_invite_by_user_id).to eq(disabler.id)
      expect(user.disabled_invite_reason).to eq(reason)

      msg = Message.order(:id).last
      expect(msg.author_user_id).to eq(disabler.id)
      expect(msg.recipient_user_id).to eq(user.id)
      expect(msg.deleted_by_author).to be true
      expect(msg.subject).to include("invite privileges")
      expect(msg.body).to include(reason)

      mod = Moderation.order(:id).last
      expect(mod.moderator_user_id).to eq(disabler.id)
      expect(mod.user_id).to eq(user.id)
      expect(mod.action).to eq("Disabled invitations")
      expect(mod.reason).to eq(reason)
    end
  end

  describe "#ban_by_user_for_reason!" do
    it "bans, deletes, notifies, and creates moderation" do
      banner = create(:user)
      user = create(:user)

      mailer_double = double(deliver_now: true)
      expect(BanNotificationMailer).to receive(:notify).with(user, banner, "bad acts").and_return(mailer_double)

      expect {
        expect(user.ban_by_user_for_reason!(banner, "bad acts")).to be true
      }.to change { Moderation.count }.by(1)

      user.reload
      expect(user.banned_at).to be_present
      expect(user.deleted_at).to be_present
      expect(user.banned_by_user_id).to eq(banner.id)

      mod = Moderation.order(:id).last
      expect(mod.action).to eq("Banned")
      expect(mod.moderator_user_id).to eq(banner.id)
      expect(mod.user_id).to eq(user.id)
      expect(mod.reason).to eq("bad acts")
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

  describe "#can_flag?" do
    let(:mature_user) { create(:user, created_at: (User::NEW_USER_DAYS + 1).days.ago, karma: 100) }

    it "returns false for new users" do
      new_user = create(:user, created_at: Time.current, karma: 100)
      story = build(:story)
      allow(story).to receive(:is_flaggable?).and_return(true)
      expect(new_user.can_flag?(story)).to be false
    end

    it "allows flagging flaggable stories" do
      story = build(:story)
      allow(story).to receive(:is_flaggable?).and_return(true)
      expect(mature_user.can_flag?(story)).to be true
    end

    it "allows unvoting if story currently flagged" do
      story = build(:story)
      allow(story).to receive(:is_flaggable?).and_return(false)
      allow(story).to receive(:current_flagged?).and_return(true)
      expect(mature_user.can_flag?(story)).to be true
    end

    it "requires sufficient karma to flag comments" do
      comment = build(:comment)
      allow(comment).to receive(:is_flaggable?).and_return(true)

      low = create(:user, created_at: (User::NEW_USER_DAYS + 1).days.ago, karma: User::MIN_KARMA_TO_FLAG - 1)
      high = create(:user, created_at: (User::NEW_USER_DAYS + 1).days.ago, karma: User::MIN_KARMA_TO_FLAG)

      expect(low.can_flag?(comment)).to be false
      expect(high.can_flag?(comment)).to be true
    end
  end

  describe "#can_invite?" do
    it "requires not banned from inviting and sufficient karma to submit stories" do
      user = create(:user, karma: User::MIN_KARMA_TO_SUBMIT_STORIES, disabled_invite_at: nil)
      expect(user.can_invite?).to be true

      user.update!(karma: User::MIN_KARMA_TO_SUBMIT_STORIES - 1)
      expect(user.can_invite?).to be false

      user.update!(karma: 10, disabled_invite_at: Time.current)
      expect(user.can_invite?).to be false
    end
  end

  describe "#can_offer_suggestions?" do
    it "requires non-new user and minimum karma" do
      old_user = create(:user, created_at: (User::NEW_USER_DAYS + 1).days.ago, karma: User::MIN_KARMA_TO_SUGGEST)
      expect(old_user.can_offer_suggestions?).to be true

      low_karma = create(:user, created_at: (User::NEW_USER_DAYS + 1).days.ago, karma: User::MIN_KARMA_TO_SUGGEST - 1)
      expect(low_karma.can_offer_suggestions?).to be false

      new_user = create(:user, created_at: Time.current, karma: 999)
      expect(new_user.can_offer_suggestions?).to be false
    end
  end

  describe "#can_see_invitation_requests?" do
    it "is true for moderators with invite ability" do
      user = create(:user, is_moderator: true, disabled_invite_at: nil, karma: 100)
      expect(user.can_see_invitation_requests?).to be true
    end

    it "is true for sufficiently high karma users who can invite" do
      user = create(:user, disabled_invite_at: nil, karma: User::MIN_KARMA_FOR_INVITATION_REQUESTS)
      expect(user.can_see_invitation_requests?).to be true
    end

    it "is false if cannot invite" do
      user = create(:user, disabled_invite_at: Time.current, karma: 1000)
      expect(user.can_see_invitation_requests?).to be false
    end
  end

  describe "#can_submit_stories?" do
    it "respects the minimum karma threshold" do
      user = create(:user, karma: User::MIN_KARMA_TO_SUBMIT_STORIES)
      expect(user.can_submit_stories?).to be true

      user.update!(karma: User::MIN_KARMA_TO_SUBMIT_STORIES - 1)
      expect(user.can_submit_stories?).to be false
    end
  end

  describe "#high_karma?" do
    it "returns true when karma >= threshold" do
      u = create(:user, karma: User::HIGH_KARMA_THRESHOLD)
      expect(u.high_karma?).to be true
    end

    it "returns false when karma < threshold" do
      u = create(:user, karma: User::HIGH_KARMA_THRESHOLD - 1)
      expect(u.high_karma?).to be false
    end
  end

  describe "session and tokens" do
    it "rolls session_token before save if blank" do
      user = build(:user, session_token: nil)
      expect(user.session_token).to be_nil
      user.save!
      expect(user.session_token).to be_present
      expect(user.session_token.length).to be >= 32
    end

    it "generates rss and mailing list tokens on create if blank" do
      user = create(:user, mailing_list_token: nil, rss_token: nil)
      expect(user.mailing_list_token).to be_present
      expect(user.mailing_list_token.length).to eq(10)
      expect(user.rss_token).to be_present
      expect(user.rss_token.length).to eq(60)
    end
  end

  describe "counts via Keystore" do
    it "returns comments posted and deleted counts" do
      user = create(:user)
      Keystore.put("user:#{user.id}:comments_posted", 7)
      Keystore.put("user:#{user.id}:comments_deleted", 3)
      expect(user.comments_posted_count).to eq(7)
      expect(user.comments_deleted_count).to eq(3)
    end

    it "refresh_counts! stores current counts" do
      user = create(:user)
      create(:story, user: user)
      create(:comment, user: user, is_deleted: false)
      create(:comment, user: user, is_deleted: true)

      user.refresh_counts!

      expect(Keystore.value_for("user:#{user.id}:stories_submitted").to_i).to eq(1)
      expect(Keystore.value_for("user:#{user.id}:comments_posted").to_i).to eq(1)
      expect(Keystore.value_for("user:#{user.id}:comments_deleted").to_i).to eq(1)
    end
  end

  describe "#fetched_avatar" do:
    it "returns body when fetch succeeds" do
      user = create(:user, email: "user@example.com")
      sponge = double("Sponge")
      allow(Sponge).to receive(:new).and_return(sponge)
      allow(sponge).to receive(:timeout=)
      allow(sponge).to receive(:fetch).and_return(double(body: "imagebytes"))
      expect(user.fetched_avatar(80)).to eq("imagebytes")
    end

    it "returns nil on fetch error" do
      user = create(:user, email: "user@example.com")
      sponge = double("Sponge")
      allow(Sponge).to receive(:new).and_return(sponge)
      allow(sponge).to receive(:timeout=)
      allow(sponge).to receive(:fetch).and_raise(StandardError)
      expect(user.fetched_avatar(80)).to be_nil
    end
  end

  describe "#delete! and #undelete!" do
    it "marks deleted_at, deletes messages, masks email in some cases, and can undelete" do
      other = create(:user)
      user = create(:user, karma: -1) # will trigger good_riddance? to mask email
      original_session = user.session_token

      sent = create(:message, author_user_id: user.id, recipient_user_id: other.id, subject: "s", body: "b")
      received = create(:message, author_user_id: other.id, recipient_user_id: user.id, subject: "s2", body: "b2")
      inv = create(:invitation, user: user, used_at: nil)

      user.delete!
      user.reload

      expect(user.deleted_at).to be_present
      expect(user.session_token).to be_present
      expect(user.session_token).not_to eq(original_session)
      expect(user.email).to eq("#{user.username}@lobsters.example")

      sent.reload
      received.reload
      expect(sent.deleted_by_author).to be true
      expect(received.deleted_by_recipient).to be true
      expect(inv.reload.used_at).to be_present

      user.undelete!
      expect(user.reload.deleted_at).to be_nil
    end
  end

  describe "#disable_2fa! and #has_2fa?" do
    it "disables 2fa and reports presence" do
      user = create(:user, totp_secret: "secret")
      expect(user.has_2fa?).to be true
      user.disable_2fa!
      expect(user.reload.has_2fa?).to be false
    end
  end

  describe "#good_riddance?" do
    it "masks email when karma is negative" do
      user = create(:user, karma: -5, email: "real@example.com")
      user.good_riddance?
      expect(user.email).to eq("#{user.username}@lobsters.example")
    end
  end

  describe "#grant_moderatorship_by_user!" do
    it "grants mod, creates moderation and a Sysop hat" do
      grantor = create(:user)
      user = create(:user)
      expect {
        expect(user.grant_moderatorship_by_user!(grantor)).to be true
      }.to change { Moderation.count }.by(1)
       .and change { Hat.count }.by(1)
      expect(user.reload.is_moderator).to be true
      hat = Hat.order(:id).last
      expect(hat.user_id).to eq(user.id)
      expect(hat.hat).to eq("Sysop")
    end
  end

  describe "#initiate_password_reset_for_ip" do
    it "sets a token and sends email" do
      user = create(:user)
      mailer = double(deliver_now: true)
      expect(PasswordResetMailer).to receive(:password_reset_link).with(user, "1.2.3.4").and_return(mailer)
      user.initiate_password_reset_for_ip("1.2.3.4")
      expect(user.reload.password_reset_token).to match(/\A\d{10}-[A-Za-z0-9]+\z/)
    end
  end

  describe "#is_wiped?" do
    it "is true when password_digest is '*'" do
      user = create(:user)
      user.update_column(:password_digest, "*")
      expect(user.is_wiped?).to be true
    end
  end

  describe "#ids_replied_to" do
    it "marks ids that user replied to" do
      user = create(:user)
      story = create(:story, user: user)
      parent1 = create(:comment, story: story)
      parent2 = create(:comment, story: story)
      parent3 = create(:comment, story: story)

      create(:comment, story: story, user: user, parent_comment_id: parent1.id)
      create(:comment, story: story, user: user, parent_comment_id: parent3.id)

      result = user.ids_replied_to([parent1.id, parent2.id, parent3.id])
      expect(result[parent1.id]).to be true
      expect(result[parent2.id]).to be false
      expect(result[parent3.id]).to be true
    end
  end

  describe "#roll_session_token" do
    it "sets a random session_token" do
      user = create(:user)
      user.session_token = nil
      user.roll_session_token
      expect(user.session_token).to be_present
      expect(user.session_token.length).to eq(60)
    end
  end

  describe "#linkified_about" do
    it "uses Markdowner to render about" do
      user = create(:user, about: "hello")
      expect(Markdowner).to receive(:to_html).with("hello").and_return("<p>hello</p>")
      expect(user.linkified_about).to eq("<p>hello</p>")
    end
  end

  describe "#mastodon_acct" do
    it "builds acct when both username and instance are present" do
      user = create(:user, mastodon_username: "alice", mastodon_instance: "fosstodon.org")
      expect(user.mastodon_acct).to eq("@alice@fosstodon.org")
    end

    it "raises when info is incomplete" do
      user = create(:user, mastodon_username: "alice", mastodon_instance: nil)
      expect { user.mastodon_acct }.to raise_error(RuntimeError)
    end
  end

  describe "#pushover!" do
    it "pushes when user key present" do
      user = create(:user, pushover_user_key: "key123")
      expect(Pushover).to receive(:push).with("key123", title: "t", message: "m")
      user.pushover!(title: "t", message: "m")
    end

    it "does nothing without user key" do
      user = create(:user, pushover_user_key: nil)
      expect(Pushover).not_to receive(:push)
      user.pushover!(title: "t", message: "m")
    end
  end

  describe "#stories_submitted_count and #stories_deleted_count" do
    it "reads values from Keystore" do
      user = create(:user)
      Keystore.put("user:#{user.id}:stories_submitted", 12)
      Keystore.put("user:#{user.id}:stories_deleted", 4)
      expect(user.stories_submitted_count).to eq(12)
      expect(user.stories_deleted_count).to eq(4)
    end
  end

  describe "#to_param" do
    it "returns username" do
      user = create(:user, username: "paramuser")
      expect(user.to_param).to eq("paramuser")
    end
  end

  describe "#enable_invite_by_user!" do
    it "clears disabled invite fields and records moderation" do
      mod = create(:user)
      user = create(:user, disabled_invite_at: Time.current, disabled_invite_by_user_id: mod.id, disabled_invite_reason: "r")
      expect {
        expect(user.enable_invite_by_user!(mod)).to be true
      }.to change { Moderation.count }.by(1)
      user.reload
      expect(user.disabled_invite_at).to be_nil
      expect(user.disabled_invite_by_user_id).to be_nil
      expect(user.disabled_invite_reason).to be_nil
      expect(Moderation.order(:id).last.action).to eq("Enabled invitations")
    end
  end

  describe "#inbox_count" do
    it "counts unread notifications" do
      user = create(:user)
      create(:notification, user: user, read_at: nil)
      create(:notification, user: user, read_at: Time.current)
      expect(user.inbox_count).to eq(1)
    end
  end

  describe "#votes_for_others" do
    it "returns only votes on others' content ordered by id desc" do
      a = create(:user)
      b = create(:user)
      story_a = create(:story, user: a)
      story_b = create(:story, user: b)
      comment_a = create(:comment, user: a, story: story_a)
      comment_b = create(:comment, user: b, story: story_b)

      v1 = create(:vote, user: a, story: story_a, vote: 1)   # own story, exclude
      v2 = create(:vote, user: a, story: story_b, vote: 1)   # other's story, include
      v3 = create(:vote, user: a, comment: comment_b, vote: 1) # other's comment, include
      v4 = create(:vote, user: a, comment: comment_a, vote: 1) # own comment, exclude

      result = a.votes_for_others.to_a
      expect(result).to match_array([v2, v3])
      expect(result.map(&:id)).to eq([v3.id, v2.id].sort.reverse) # ensure desc order by id
    end
  end

  describe ".active" do
    it "returns only users without banned_at and deleted_at" do
      active_user = create(:user, banned_at: nil, deleted_at: nil)
      banned_user = create(:user, banned_at: Time.current)
      deleted_user = create(:user, deleted_at: Time.current)
      expect(User.active).to include(active_user)
      expect(User.active).not_to include(banned_user)
      expect(User.active).not_to include(deleted_user)
    end
  end

  describe ".moderators" do
    it "includes users flagged as moderators" do
      mod = create(:user, is_moderator: true)
      regular = create(:user, is_moderator: false)
      expect(User.moderators).to include(mod)
      expect(User.moderators).not_to include(regular)
    end
  end
end
