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
    it "returns a regex-like string anchored at start and end" do
      s = User.username_regex_s
      expect(s).to start_with("/^")
      expect(s).to end_with("$/")
    end
  end

  describe "#as_json" do
    it "includes expected fields and derived fields for non-admin" do
      inviter = create(:user)
      user = create(:user, about: "hi", homepage: "https://lobste.rs", invited_by_user: inviter)
      allow(Markdowner).to receive(:to_html).with("hi").and_return("<p>hi</p>")

      json = user.as_json

      expect(json[:username]).to eq(user.username)
      expect(json[:is_admin]).to eq(user.is_admin)
      expect(json[:is_moderator]).to eq(user.is_moderator)
      expect(json).to have_key(:karma)
      expect(json[:about]).to eq("<p>hi</p>")
      expect(json[:avatar_url]).to include("/avatars/#{user.username}-100.png")
      expect(json[:invited_by_user]).to eq(inviter.username)
      expect(json[:homepage]).to eq("https://lobste.rs")
    end

    it "omits karma for admins and includes optional provider usernames only when present" do
      user = create(:user, is_admin: true, github_username: nil, mastodon_username: nil)
      allow(Markdowner).to receive(:to_html).and_return("ok")

      json = user.as_json
      expect(json).not_to have_key(:karma)

      user.update!(github_username: "octo", mastodon_username: "mastouser")
      json2 = user.as_json
      expect(json2[:github_username]).to eq("octo")
      expect(json2[:mastodon_username]).to eq("mastouser")
    end
  end

  describe "#authenticate_totp" do
    it "verifies with the TOTP provider" do
      user = build(:user, totp_secret: "secret")
      fake_totp = instance_double(ROTP::TOTP)
      allow(ROTP::TOTP).to receive(:new).with("secret").and_return(fake_totp)
      allow(fake_totp).to receive(:verify).with("123456").and_return(true)
      allow(fake_totp).to receive(:verify).with("000000").and_return(false)

      expect(user.authenticate_totp("123456")).to be_truthy
      expect(user.authenticate_totp("000000")).to be_falsey
    end
  end

  describe "#avatar_path" do
    it "returns a path containing the username and size" do
      user = build(:user, username: "alice")
      path = user.avatar_path(80)
      expect(path).to include("/avatars/alice-80.png")
    end
  end

  describe "#avatar_url" do
    it "returns a url containing the username and size" do
      user = build(:user, username: "bob")
      url = user.avatar_url(120)
      expect(url).to include("/avatars/bob-120.png")
    end
  end

  describe "#disable_invite_by_user_for_reason!" do
    it "disables invites, sends a message, and records moderation" do
      mod = create(:user)
      user = create(:user)

      expect(user.disable_invite_by_user_for_reason!(mod, "spammy")).to eq(true)
      user.reload

      expect(user.disabled_invite_at).to be_present
      expect(user.disabled_invite_by_user_id).to eq(mod.id)
      expect(user.disabled_invite_reason).to eq("spammy")

      msg = Message.where(author_user_id: mod.id, recipient_user_id: user.id).order(:id).last
      expect(msg).to be_present
      expect(msg.subject).to eq("Your invite privileges have been revoked")
      expect(msg.body).to include("spammy")

      m = Moderation.where(user_id: user.id, moderator_user_id: mod.id, action: "Disabled invitations").first
      expect(m).to be_present
      expect(m.reason).to eq("spammy")
    end
  end

  describe "#enable_invite_by_user!" do
    it "re-enables invites and records moderation" do
      mod = create(:user)
      user = create(:user, disabled_invite_at: Time.current, disabled_invite_by_user_id: mod.id, disabled_invite_reason: "prev")

      expect(user.enable_invite_by_user!(mod)).to eq(true)
      user.reload

      expect(user.disabled_invite_at).to be_nil
      expect(user.disabled_invite_by_user_id).to be_nil
      expect(user.disabled_invite_reason).to be_nil

      m = Moderation.where(user_id: user.id, moderator_user_id: mod.id, action: "Enabled invitations").first
      expect(m).to be_present
    end
  end

  describe "#ban_by_user_for_reason!" do
    it "bans the user, soft-deletes them, sends notification, and records moderation" do
      banner = create(:user)
      user = create(:user)
      mail_double = double(deliver_now: true)
      allow(BanNotificationMailer).to receive(:notify).with(user, banner, "bad").and_return(mail_double)

      expect(user.ban_by_user_for_reason!(banner, "bad")).to eq(true)
      user.reload

      expect(user.banned_at).to be_present
      expect(user.banned_by_user_id).to eq(banner.id)
      expect(user.banned_reason).to eq("bad")
      expect(user.deleted_at).to be_present
      expect(BanNotificationMailer).to have_received(:notify).with(user, banner, "bad")

      m = Moderation.where(user_id: user.id, moderator_user_id: banner.id, action: "Banned").first
      expect(m).to be_present
      expect(m.reason).to eq("bad")
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

  describe "permission predicates" do
    let(:user) { create(:user, created_at: (User::NEW_USER_DAYS + 1).days.ago, karma: 0) }

    describe "#can_submit_stories?" do
      it "requires karma >= threshold" do
        expect(build(:user, karma: -5).can_submit_stories?).to be false
        expect(build(:user, karma: -4).can_submit_stories?).to be true
      end
    end

    describe "#high_karma?" do
      it "is true at threshold and above" do
        expect(build(:user, karma: 99).high_karma?).to be false
        expect(build(:user, karma: 100).high_karma?).to be true
      end
    end

    describe "#can_invite?" do
      it "requires not banned from inviting and ability to submit" do
        u = build(:user, karma: -5, disabled_invite_at: nil)
        expect(u.can_invite?).to be false

        u2 = build(:user, karma: 0, disabled_invite_at: Time.current)
        expect(u2.can_invite?).to be false

        u3 = build(:user, karma: 0, disabled_invite_at: nil)
        expect(u3.can_invite?).to be true
      end
    end

    describe "#can_offer_suggestions?" do
      it "is false for new users and true for older users with enough karma" do
        new_user = create(:user, created_at: Time.current, karma: 100)
        expect(new_user.can_offer_suggestions?).to be false

        low_karma = create(:user, created_at: (User::NEW_USER_DAYS + 1).days.ago, karma: 9)
        expect(low_karma.can_offer_suggestions?).to be false

        ok = create(:user, created_at: (User::NEW_USER_DAYS + 1).days.ago, karma: 10)
        expect(ok.can_offer_suggestions?).to be true
      end
    end

    describe "#can_see_invitation_requests?" do
      it "requires can_invite? and either mod status or sufficient karma" do
        cannot_invite = build(:user, karma: -5)
        expect(cannot_invite.can_see_invitation_requests?).to be false

        inviter_low_karma = build(:user, karma: 0, is_moderator: false)
        expect(inviter_low_karma.can_see_invitation_requests?).to be false

        inviter_high_karma = build(:user, karma: User::MIN_KARMA_FOR_INVITATION_REQUESTS, is_moderator: false)
        expect(inviter_high_karma.can_see_invitation_requests?).to be true

        moderator = build(:user, karma: -5, is_moderator: true)
        expect(moderator.can_see_invitation_requests?).to be false # cannot invite

        moderator_inviter = build(:user, karma: 0, is_moderator: true)
        expect(moderator_inviter.can_see_invitation_requests?).to be true
      end
    end

    describe "#can_flag?" do
      it "disallows new users" do
        new_user = create(:user, created_at: Time.current, karma: 100)
        story = create(:story)
        allow(story).to receive(:is_flaggable?).and_return(true)
        expect(new_user.can_flag?(story)).to be false
      end

      it "allows flagging a flaggable story or unvoting a currently flagged story" do
        u = create(:user, created_at: (User::NEW_USER_DAYS + 1).days.ago, karma: 0)
        story = create(:story)
        allow(story).to receive(:is_flaggable?).and_return(true)
        allow(story).to receive(:current_flagged?).and_return(false)
        expect(u.can_flag?(story)).to be true

        story2 = create(:story)
        allow(story2).to receive(:is_flaggable?).and_return(false)
        allow(story2).to receive(:current_flagged?).and_return(true)
        expect(u.can_flag?(story2)).to be true
      end

      it "requires sufficient karma to flag a flaggable comment" do
        story = create(:story)
        comment = create(:comment, story: story)
        allow(comment).to receive(:is_flaggable?).and_return(true)

        low = create(:user, created_at: (User::NEW_USER_DAYS + 1).days.ago, karma: User::MIN_KARMA_TO_FLAG - 1)
        high = create(:user, created_at: (User::NEW_USER_DAYS + 1).days.ago, karma: User::MIN_KARMA_TO_FLAG)

        expect(low.can_flag?(comment)).to be false
        expect(high.can_flag?(comment)).to be true
      end

      it "returns false for non-flaggable objects" do
        u = create(:user, created_at: (User::NEW_USER_DAYS + 1).days.ago, karma: 0)
        story = create(:story)
        allow(story).to receive(:is_flaggable?).and_return(false)
        allow(story).to receive(:current_flagged?).and_return(false)
        expect(u.can_flag?(story)).to be false
      end
    end
  end

  describe "#check_session_token" do
    it "generates a session token when blank" do
      user = build(:user, session_token: nil)
      allow(Utils).to receive(:random_str).with(60).and_return("a" * 60)
      user.check_session_token
      expect(user.session_token).to eq("a" * 60)
    end

    it "does not change a present session token" do
      user = build(:user, session_token: "present")
      user.check_session_token
      expect(user.session_token).to eq("present")
    end
  end

  describe "#create_mailing_list_token" do
    it "creates a token when blank" do
      user = build(:user, mailing_list_token: nil)
      allow(Utils).to receive(:random_str).with(10).and_return("tok10")
      user.create_mailing_list_token
      expect(user.mailing_list_token).to eq("tok10")
    end

    it "does not override existing token" do
      user = build(:user, mailing_list_token: "exists")
      user.create_mailing_list_token
      expect(user.mailing_list_token).to eq("exists")
    end
  end

  describe "#create_rss_token" do
    it "creates a token when blank" do
      user = build(:user, rss_token: nil)
      allow(Utils).to receive(:random_str).with(60).and_return("r" * 60)
      user.create_rss_token
      expect(user.rss_token).to eq("r" * 60)
    end

    it "does not override existing token" do
      user = build(:user, rss_token: "exists")
      user.create_rss_token
      expect(user.rss_token).to eq("exists")
    end
  end

  describe "#ids_replied_to" do
    it "returns a hash of parent ids that the user has replied to" do
      story = create(:story)
      other = create(:user)
      user = create(:user)

      parent1 = create(:comment, user: other, story: story)
      parent2 = create(:comment, user: other, story: story)
      parent3 = create(:comment, user: other, story: story)

      create(:comment, user: user, story: story, parent_comment: parent1)
      create(:comment, user: user, story: story, parent_comment: parent3)

      result = user.ids_replied_to([parent1.id, parent2.id, parent3.id])

      expect(result[parent1.id]).to be true
      expect(result[parent2.id]).to be false
      expect(result[parent3.id]).to be true
    end
  end

  describe "#roll_session_token" do:
    it "sets a random session token" do
      user = build(:user)
      allow(Utils).to receive(:random_str).with(60).and_return("x" * 60)
      user.roll_session_token
      expect(user.session_token).to eq("x" * 60)
    end
  end

  describe "#linkified_about" do
    it "delegates to Markdowner" do
      user = build(:user, about: "hello")
      allow(Markdowner).to receive(:to_html).with("hello").and_return("<p>hello</p>")
      expect(user.linkified_about).to eq("<p>hello</p>")
    end
  end

  describe "#mastodon_acct" do
    it "returns an acct string when both parts are present" do
      user = build(:user, mastodon_username: "alice", mastodon_instance: "fosstodon.org")
      expect(user.mastodon_acct).to eq("@alice@fosstodon.org")
    end

    it "raises when missing information" do
      user = build(:user, mastodon_username: nil, mastodon_instance: "fosstodon.org")
      expect { user.mastodon_acct }.to raise_error(RuntimeError)
    end
  end

  describe "#pushover!" do
    it "pushes when a user key is present" do
      user = build(:user, settings: {pushover_user_key: "key"})
      expect(Pushover).to receive(:push).with("key", title: "hi")
      user.pushover!(title: "hi")
    end

    it "does nothing when no user key" do
      user = build(:user, settings: {pushover_user_key: nil})
      expect(Pushover).not_to receive(:push)
      user.pushover!(title: "hi")
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

  describe "#to_param" do
    it "returns the username" do
      user = build(:user, username: "paramuser")
      expect(user.to_param).to eq("paramuser")
    end
  end

  describe "#has_2fa?" do
    it "reflects presence of totp_secret" do
      expect(build(:user, totp_secret: nil).has_2fa?).to be false
      expect(build(:user, totp_secret: "s").has_2fa?).to be true
    end
  end

  describe "#disable_2fa!" do
    it "clears the totp_secret" do
      user = create(:user, totp_secret: "abc")
      user.disable_2fa!
      user.reload
      expect(user.totp_secret).to be_nil
      expect(user.has_2fa?).to be false
    end
  end

  describe "#is_wiped?" do
    it "is true when password_digest is '*'" do
      user = build(:user, password_digest: "*")
      expect(user.is_wiped?).to be true
      expect(build(:user).is_wiped?).to be false
    end
  end

  describe "#votes_for_others" do
    it "returns votes on others' content and excludes self-votes, ordered newest first" do
      voter = create(:user)
      other = create(:user)
      story_self = create(:story, user: voter)
      story_other = create(:story, user: other)

      vote1 = create(:vote, user: voter, story: story_other, vote: 1)
      vote2 = create(:vote, user: voter, story: story_self, vote: 1) # self-vote, should be excluded

      comment_by_other = create(:comment, user: other, story: story_other)
      vote3 = create(:vote, user: voter, comment: comment_by_other, vote: 1)

      result_ids = voter.votes_for_others.pluck(:id)
      expect(result_ids).to eq([vote3.id, vote1.id])
      expect(result_ids).not_to include(vote2.id)
    end
  end
end
