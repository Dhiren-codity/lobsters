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
    expect(build(:user, homepage: "gopher://www.lobste.rs/")).to be valid

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

  # NEW TESTS BELOW

  context "associations" do
    it { should have_many(:stories) }
    it { should have_many(:comments) }
    it { should have_many(:sent_messages).class_name("Message").with_foreign_key("author_user_id") }
    it { should have_many(:received_messages).class_name("Message").with_foreign_key("recipient_user_id") }
    it { should have_many(:tag_filters).dependent(:destroy) }
    it { should have_many(:tag_filter_tags).through(:tag_filters) }
    it { should belong_to(:invited_by_user).class_name("User").optional }
    it { should belong_to(:banned_by_user).class_name("User").optional }
    it { should belong_to(:disabled_invite_by_user).class_name("User").optional }
    it { should have_many(:invitations) }
    it { should have_many(:mod_notes) }
    it { should have_many(:moderations) }
    it { should have_many(:votes) }
    it { should have_many(:voted_stories).through(:votes) }
    it { should have_many(:upvoted_stories).through(:votes) }
    it { should have_many(:hats) }
    it { should have_many(:wearable_hats).class_name("Hat") }
    it { should have_many(:notifications) }
    it { should have_many(:hidings).class_name("HiddenStory").dependent(:destroy) }
  end

  context "validations" do
    it { should validate_inclusion_of(:prefers_color_scheme).in_array(%w[system light dark]) }
    it { should validate_inclusion_of(:prefers_contrast).in_array(%w[system normal high]) }
    it { should validate_presence_of(:password).on(:create) }
    it { should validate_inclusion_of(:show_email).in_array([true, false]) }
    it { should validate_inclusion_of(:is_admin).in_array([true, false]) }
    it { should validate_inclusion_of(:is_moderator).in_array([true, false]) }
    it { should validate_inclusion_of(:pushover_mentions).in_array([true, false]) }
    it { should validate_presence_of(:karma) }
  end

  describe ".active" do
    it "returns only users that are not banned and not deleted" do
      active = create(:user)
      banned = create(:user, banned_at: Time.current)
      deleted = create(:user, deleted_at: Time.current)

      expect(User.active).to include(active)
      expect(User.active).not_to include(banned)
      expect(User.active).not_to include(deleted)
    end
  end

  describe ".moderators" do
    it "includes is_moderator users and users with qualifying moderation records" do
      stub_const("Moderation::BAD_DOFFING_ENTRIES", ["bad"])

      real_mod = create(:user, is_moderator: true)
      mod_via_history = create(:user, is_moderator: false)
      ignored_due_to_bad_token = create(:user, is_moderator: false)
      normal_user = create(:user, is_moderator: false)

      Moderation.create!(moderator_user_id: mod_via_history.id, user_id: normal_user.id, action: "x", token: "good")
      Moderation.create!(moderator_user_id: ignored_due_to_bad_token.id, user_id: normal_user.id, action: "x", token: "bad")

      result = User.moderators
      expect(result).to include(real_mod, mod_via_history)
      expect(result).not_to include(ignored_due_to_bad_token, normal_user)
    end
  end

  describe ".username_regex_s" do
    it "returns the expected VALID_USERNAME regex string" do
      expect(User.username_regex_s).to eq("/^[A-Za-z0-9][A-Za-z0-9_-]{0,24}$/")
    end
  end

  describe ".\/ (finder by username)" do
    it "finds a user by username" do
      u = create(:user, username: "findme")
      expect(User./("findme")).to eq(u)
    end

    it "raises when user does not exist" do
      expect { User./("nope") }.to raise_error(ActiveRecord::RecordNotFound)
    end
  end

  describe "#as_json" do
    it "exposes expected fields for non-admin including karma and optional usernames" do
      inviter = create(:user, username: "inviter")
      u = create(:user, invited_by_user: inviter, about: "about", homepage: "https://lobste.rs",
                 github_username: "ghuser", mastodon_username: "masto", mastodon_instance: "social.example")

      allow(u).to receive(:linkified_about).and_return("<p>about</p>")
      allow(u).to receive(:avatar_url).and_return("http://test.host/avatars/u-100.png")

      h = u.as_json
      expect(h[:username]).to eq(u.username)
      expect(h[:is_admin]).to eq(false)
      expect(h[:karma]).to eq(u.karma)
      expect(h[:homepage]).to eq(u.homepage)
      expect(h[:about]).to eq("<p>about</p>")
      expect(h[:avatar_url]).to eq("http://test.host/avatars/u-100.png")
      expect(h[:invited_by_user]).to eq("inviter")
      expect(h[:github_username]).to eq("ghuser")
      expect(h[:mastodon_username]).to eq("masto")
    end

    it "omits karma for admins" do
      u = create(:user, is_admin: true)
      h = u.as_json
      expect(h.key?(:karma)).to be false
    end

    it "omits optional usernames if blank" do
      u = create(:user, github_username: nil, mastodon_username: nil)
      h = u.as_json
      expect(h.key?(:github_username)).to be false
      expect(h.key?(:mastodon_username)).to be false
    end
  end

  describe "#authenticate_totp" do
    it "verifies valid and invalid TOTP codes" do
      secret = ROTP::Base32.random_base32
      u = create(:user, totp_secret: secret)
      totp = ROTP::TOTP.new(secret)
      expect(u.authenticate_totp(totp.now)).to be_truthy
      expect(u.authenticate_totp("000000")).to be_falsey
    end
  end

  describe "#avatar_path and #avatar_url" do
    it "returns paths including username and size" do
      u = create(:user, username: "alice")
      expect(u.avatar_path(50)).to include("/avatars/alice-50.png")
      expect(u.avatar_url(80)).to include("/avatars/alice-80.png")
    end
  end

  describe "#disable_invite_by_user_for_reason!" do
    it "disables invites, sends message, and records moderation" do
      disabler = create(:user)
      target = create(:user)
      reason = "Abuse of invites"

      expect {
        expect(target.disable_invite_by_user_for_reason!(disabler, reason)).to be true
      }.to change { Message.count }.by(1)
       .and change { Moderation.count }.by(1)

      target.reload
      expect(target.disabled_invite_at).to be_present
      expect(target.disabled_invite_by_user_id).to eq(disabler.id)
      expect(target.disabled_invite_reason).to eq(reason)

      msg = Message.order(:id).last
      expect(msg.author_user_id).to eq(disabler.id)
      expect(msg.recipient_user_id).to eq(target.id)
      expect(msg.subject).to include("revoked")
      expect(msg.deleted_by_author).to be true

      mod = Moderation.order(:id).last
      expect(mod.moderator_user_id).to eq(disabler.id)
      expect(mod.user_id).to eq(target.id)
      expect(mod.action).to eq("Disabled invitations")
      expect(mod.reason).to eq(reason)
    end
  end

  describe "#enable_invite_by_user!" do
    it "re-enables invites and records moderation" do
      mod = create(:user)
      target = create(:user, disabled_invite_at: Time.current, disabled_invite_by_user: mod, disabled_invite_reason: "bad")

      expect {
        expect(target.enable_invite_by_user!(mod)).to be true
      }.to change { Moderation.count }.by(1)

      target.reload
      expect(target.disabled_invite_at).to be_nil
      expect(target.disabled_invite_by_user_id).to be_nil
      expect(target.disabled_invite_reason).to be_nil

      m = Moderation.order(:id).last
      expect(m.moderator_user_id).to eq(mod.id)
      expect(m.user_id).to eq(target.id)
      expect(m.action).to eq("Enabled invitations")
    end
  end

  describe "#ban_by_user_for_reason!" do
    it "bans and deletes the user, sends notification, and records moderation" do
      banner = create(:user)
      target = create(:user, session_token: "oldtoken")
      mail = double(deliver_now: true)
      expect(BanNotificationMailer).to receive(:notify).with(target, banner, "spam").and_return(mail)

      expect {
        expect(target.ban_by_user_for_reason!(banner, "spam")).to be true
      }.to change { Moderation.count }.by(1)

      target.reload
      expect(target.banned_at).to be_present
      expect(target.banned_by_user_id).to eq(banner.id)
      expect(target.banned_reason).to eq("spam")
      expect(target.deleted_at).to be_present
      expect(target.session_token).not_to eq("oldtoken")

      m = Moderation.order(:id).last
      expect(m.moderator_user_id).to eq(banner.id)
      expect(m.user_id).to eq(target.id)
      expect(m.action).to eq("Banned")
      expect(m.reason).to eq("spam")
    end
  end

  describe "#banned_from_inviting?" do
    it "reflects disabled invite status" do
      u = create(:user)
      expect(u.banned_from_inviting?).to be false
      u.update!(disabled_invite_at: Time.current)
      expect(u.banned_from_inviting?).to be true
    end
  end

  describe "#can_invite?" do
    it "returns true when not banned from inviting and can submit stories" do
      u = create(:user, karma: 0)
      expect(u.can_invite?).to be true
    end

    it "returns false when banned from inviting" do
      u = create(:user, disabled_invite_at: Time.current)
      expect(u.can_invite?).to be false
    end

    it "returns false when cannot submit stories" do
      u = create(:user, karma: User::MIN_KARMA_TO_SUBMIT_STORIES - 1)
      expect(u.can_invite?).to be false
    end
  end

  describe "#can_offer_suggestions?" do
    it "requires not new and minimum karma" do
      old_user = create(:user, created_at: (User::NEW_USER_DAYS + 1).days.ago, karma: User::MIN_KARMA_TO_SUGGEST)
      expect(old_user.can_offer_suggestions?).to be true

      low_karma = create(:user, created_at: (User::NEW_USER_DAYS + 1).days.ago, karma: User::MIN_KARMA_TO_SUGGEST - 1)
      expect(low_karma.can_offer_suggestions?).to be false

      new_user = create(:user, created_at: Time.current, karma: 1000)
      expect(new_user.can_offer_suggestions?).to be false
    end
  end

  describe "#can_see_invitation_requests?" do
    it "is true for moderators who can invite" do
      u = create(:user, is_moderator: true, karma: 0)
      expect(u.can_see_invitation_requests?).to be true
    end

    it "is true for non-mods with sufficient karma who can invite" do
      u = create(:user, karma: User::MIN_KARMA_FOR_INVITATION_REQUESTS)
      expect(u.can_see_invitation_requests?).to be true
    end

    it "is false when cannot invite" do
      u = create(:user, karma: User::MIN_KARMA_FOR_INVITATION_REQUESTS, disabled_invite_at: Time.current)
      expect(u.can_see_invitation_requests?).to be false
    end

    it "is false for non-mods below karma threshold" do
      u = create(:user, karma: User::MIN_KARMA_FOR_INVITATION_REQUESTS - 1)
      expect(u.can_see_invitation_requests?).to be false
    end
  end

  describe "#can_submit_stories?" do
    it "respects karma threshold" do
      u1 = create(:user, karma: User::MIN_KARMA_TO_SUBMIT_STORIES)
      u2 = create(:user, karma: User::MIN_KARMA_TO_SUBMIT_STORIES - 1)
      expect(u1.can_submit_stories?).to be true
      expect(u2.can_submit_stories?).to be false
    end
  end

  describe "#high_karma?" do
    it "returns true when karma >= HIGH_KARMA_THRESHOLD" do
      user = create(:user, karma: User::HIGH_KARMA_THRESHOLD)
      expect(user.high_karma?).to be true
    end

    it "returns false when karma < HIGH_KARMA_THRESHOLD" do
      user = create(:user, karma: User::HIGH_KARMA_THRESHOLD - 1)
      expect(user.high_karma?).to be false
    end
  end

  describe "#check_session_token" do
    it "rolls session token if blank before save" do
      u = build(:user, session_token: nil)
      expect(u.session_token).to be_nil
      u.save!
      expect(u.session_token).to be_present
    end

    it "does not change existing session token" do
      u = build(:user, session_token: "fixed")
      u.save!
      expect(u.session_token).to eq("fixed")
    end
  end

  describe "token creation callbacks" do
    it "generates rss_token and mailing_list_token on create if blank" do
      u = build(:user, rss_token: nil, mailing_list_token: nil)
      u.valid?
      expect(u.rss_token).to be_present
      expect(u.rss_token.length).to eq(60)
      expect(u.mailing_list_token).to be_present
      expect(u.mailing_list_token.length).to eq(10)
    end
  end

  describe "#comments_posted_count and #comments_deleted_count" do
    it "reads counts from Keystore" do
      u = create(:user)
      Keystore.put("user:#{u.id}:comments_posted", 5)
      Keystore.put("user:#{u.id}:comments_deleted", 2)
      expect(u.comments_posted_count).to eq(5)
      expect(u.comments_deleted_count).to eq(2)
    end
  end

  describe "#refresh_counts!" do
    it "stores story and comment counts in Keystore" do
      u = create(:user)
      create_list(:story, 2, user: u)
      create_list(:comment, 3, user: u, is_deleted: false)
      create_list(:comment, 4, user: u, is_deleted: true)

      u.refresh_counts!
      expect(Keystore.value_for("user:#{u.id}:stories_submitted")).to eq(2)
      expect(Keystore.value_for("user:#{u.id}:comments_posted")).to eq(3)
      expect(Keystore.value_for("user:#{u.id}:comments_deleted")).to eq(4)
    end
  end

  describe "#undelete!" do
    it "clears deleted_at" do
      u = create(:user, deleted_at: Time.current)
      u.undelete!
      expect(u.deleted_at).to be_nil
    end
  end

  describe "#disable_2fa!" do
    it "clears totp_secret and saves" do
      u = create(:user, totp_secret: "SECRET")
      u.disable_2fa!
      expect(u.totp_secret).to be_nil
      expect(u.reload.totp_secret).to be_nil
    end
  end

  describe "#good_riddance?" do
    it "does nothing for banned users" do
      u = create(:user, :banned, email: "a@b.com", karma: -1)
      u.good_riddance?
      expect(u.email).to eq("a@b.com")
    end

    it "changes email when karma negative" do
      u = create(:user, username: "xuser", email: "x@x.com", karma: -1)
      u.good_riddance?
      expect(u.email).to eq("xuser@lobsters.example")
    end
  end

  describe "#grant_moderatorship_by_user!" do
    it "promotes user, records moderation, and grants Sysop hat" do
      giver = create(:user)
      target = create(:user)

      expect {
        expect(target.grant_moderatorship_by_user!(giver)).to be true
      }.to change { Moderation.count }.by(1)
       .and change { Hat.count }.by(1)

      target.reload
      expect(target.is_moderator).to be true
      mod = Moderation.order(:id).last
      expect(mod.moderator_user_id).to eq(giver.id)
      expect(mod.user_id).to eq(target.id)
      expect(mod.action).to eq("Granted moderator status")

      hat = Hat.order(:id).last
      expect(hat.user_id).to eq(target.id)
      expect(hat.granted_by_user_id).to eq(giver.id)
      expect(hat.hat).to eq("Sysop")
    end
  end

  describe "#initiate_password_reset_for_ip" do
    it "sets token and sends mail" do
      u = create(:user)
      mail = double(deliver_now: true)
      expect(PasswordResetMailer).to receive(:password_reset_link).with(u, "1.2.3.4").and_return(mail)
      u.initiate_password_reset_for_ip("1.2.3.4")
      expect(u.password_reset_token).to be_present
      expect(u.password_reset_token).to match(/^\d{10}-[A-Za-z0-9]{30}$/)
    end
  end

  describe "#has_2fa?" do
    it "reflects presence of totp_secret" do
      expect(create(:user, totp_secret: nil).has_2fa?).to be false
      expect(create(:user, totp_secret: "x").has_2fa?).to be true
    end
  end

  describe "#is_wiped?" do
    it "is true when password_digest is '*'" do
      u = create(:user)
      u.update_column(:password_digest, "*")
      expect(u.is_wiped?).to be true
    end
  end

  describe "#ids_replied_to" do
    it "returns a hash of parent comment ids the user replied to" do
      user = create(:user)
      other = create(:user)
      story = create(:story, user: other)

      parent1 = create(:comment, story: story, user: other)
      parent2 = create(:comment, story: story, user: other)
      parent3 = create(:comment, story: story, user: other)

      create(:comment, story: story, user: user, parent_comment_id: parent1.id)
      create(:comment, story: story, user: user, parent_comment_id: parent2.id)

      result = user.ids_replied_to([parent1.id, parent2.id, parent3.id])
      expect(result[parent1.id]).to be true
      expect(result[parent2.id]).to be true
      expect(result[parent3.id]).to be false
    end
  end

  describe "#roll_session_token" do:
    it "generates a 60-character token" do
      u = build(:user)
      u.roll_session_token
      expect(u.session_token).to be_present
      expect(u.session_token.length).to eq(60)
    end
  end

  describe "#linkified_about" do
    it "delegates to Markdowner" do
      u = create(:user, about: "hi")
      expect(Markdowner).to receive(:to_html).with("hi").and_return("<p>hi</p>")
      expect(u.linkified_about).to eq("<p>hi</p>")
    end
  end

  describe "#mastodon_acct" do
    it "returns the full acct when both parts present" do
      u = create(:user, mastodon_username: "alice", mastodon_instance: "mastodon.example")
      expect(u.mastodon_acct).to eq("@alice@mastodon.example")
    end

    it "raises when missing parts" do
      u = create(:user, mastodon_username: nil, mastodon_instance: nil)
      expect { u.mastodon_acct }.to raise_error(RuntimeError)
    end
  end

  describe "#pushover!" do
    it "sends push when user key present" do
      u = create(:user, settings: { "pushover_user_key" => "key" })
      expect(Pushover).to receive(:push).with("key", { title: "Hi" })
      u.pushover!(title: "Hi")
    end

    it "does not send push when user key blank" do
      u = create(:user, settings: { "pushover_user_key" => nil })
      expect(Pushover).not_to receive(:push)
      u.pushover!(title: "Hi")
    end
  end

  describe "#stories_submitted_count and #stories_deleted_count" do
    it "reads story counts from Keystore" do
      u = create(:user)
      Keystore.put("user:#{u.id}:stories_submitted", 7)
      Keystore.put("user:#{u.id}:stories_deleted", 3)
      expect(u.stories_submitted_count).to eq(7)
      expect(u.stories_deleted_count).to eq(3)
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

  describe "#votes_for_others" do
    it "returns votes not on the user's own content" do
      u = create(:user)
      other = create(:user)

      # vote on other's story
      s_other = create(:story, user: other)
      v1 = create(:vote, user: u, story: s_other, comment: nil)

      # vote on own story
      s_own = create(:story, user: u)
      create(:vote, user: u, story: s_own, comment: nil)

      # vote on other's comment
      s = create(:story, user: other)
      c_other = create(:comment, story: s, user: other)
      v2 = create(:vote, user: u, story: s, comment: c_other)

      # vote on own comment
      c_own = create(:comment, story: s_own, user: u)
      create(:vote, user: u, story: s_own, comment: c_own)

      ids = u.votes_for_others.pluck(:id)
      expect(ids).to include(v1.id, v2.id)
      expect(ids.size).to eq(2)
    end
  end

  describe "#can_flag?" do
    it "returns false for new users" do
      new_user = create(:user, created_at: Time.current)
      story = build(:story)
      allow(story).to receive(:is_flaggable?).and_return(true)
      expect(new_user.can_flag?(story)).to be false
    end

    it "allows flagging of flaggable stories" do
      u = create(:user, created_at: (User::NEW_USER_DAYS + 1).days.ago)
      story = build(:story)
      allow(story).to receive(:is_flaggable?).and_return(true)
      expect(u.can_flag?(story)).to be true
    end

    it "allows unvoting of currently flagged stories" do
      u = create(:user, created_at: (User::NEW_USER_DAYS + 1).days.ago)
      story = build(:story)
      allow(story).to receive(:is_flaggable?).and_return(false)
      allow(story).to receive(:current_flagged?).and_return(true)
      expect(u.can_flag?(story)).to be true
    end

    it "requires karma threshold for flagging comments" do
      low = create(:user, created_at: (User::NEW_USER_DAYS + 1).days.ago, karma: User::MIN_KARMA_TO_FLAG - 1)
      high = create(:user, created_at: (User::NEW_USER_DAYS + 1).days.ago, karma: User::MIN_KARMA_TO_FLAG)
      comment = build(:comment)
      allow(comment).to receive(:is_flaggable?).and_return(true)
      expect(low.can_flag?(comment)).to be false
      expect(high.can_flag?(comment)).to be true
    end
  end
end
