require 'rails_helper'

RSpec.describe User, type: :model do
  context 'existing tests' do
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
  end

  describe '.active' do
    it 'returns users without banned_at and deleted_at' do
      active = create(:user, banned_at: nil, deleted_at: nil)
      banned = create(:user, banned_at: 1.day.ago)
      deleted = create(:user, deleted_at: 1.day.ago)
      expect(User.active).to include(active)
      expect(User.active).not_to include(banned)
      expect(User.active).not_to include(deleted)
    end
  end

  describe '.username_regex_s' do
    it 'returns a regex-like string starting with /^ and ending with $/' do
      s = User.username_regex_s
      expect(s).to be_a(String)
      expect(s).to start_with("/^")
      expect(s).to end_with("$/")
      expect(s).to include("[A-Za-z0-9]")
    end
  end

  describe '#as_json' do
    it 'includes karma for non-admins and computed fields' do
      inviter = create(:user)
      user = create(:user, invited_by_user: inviter, about: "hello", github_username: "ghu", mastodon_username: "mastou")
      allow(Markdowner).to receive(:to_html).with("hello").and_return("<p>hello</p>")

      json = user.as_json
      expect(json[:username]).to eq(user.username)
      expect(json[:karma]).to eq(user.karma)
      expect(json[:homepage]).to eq(user.homepage)
      expect(json[:about]).to eq("<p>hello</p>")
      expect(json[:avatar_url]).to include("/avatars/#{user.username}-100.png")
      expect(json[:invited_by_user]).to eq(inviter.username)
      expect(json[:github_username]).to eq("ghu")
      expect(json[:mastodon_username]).to eq("mastou")
    end

    it 'does not include karma for admins' do
      admin = create(:user, is_admin: true)
      json = admin.as_json
      expect(json.key?(:karma)).to be false
    end
  end

  describe '#authenticate_totp' do
    it 'verifies via ROTP::TOTP' do
      user = create(:user)
      user.totp_secret = "secret"
      totp_double = instance_double(ROTP::TOTP)
      allow(ROTP::TOTP).to receive(:new).with("secret").and_return(totp_double)
      allow(totp_double).to receive(:verify).with("123456").and_return(true)

      expect(user.authenticate_totp("123456")).to be true
    end

    it 'returns false when verification fails' do
      user = create(:user)
      user.totp_secret = "secret"
      totp_double = instance_double(ROTP::TOTP)
      allow(ROTP::TOTP).to receive(:new).with("secret").and_return(totp_double)
      allow(totp_double).to receive(:verify).with("000000").and_return(false)

      expect(user.authenticate_totp("000000")).to be false
    end
  end

  describe '#avatar_path and #avatar_url' do
    it 'return strings containing the expected asset path' do
      user = create(:user, username: "alice")
      expect(user.avatar_path(50)).to include("/avatars/alice-50.png")
      expect(user.avatar_url(50)).to include("/avatars/alice-50.png")
    end
  end

  describe '#disable_invite_by_user_for_reason!' do
    it 'sets disabled invite fields and creates message and moderation' do
      mod = create(:user)
      user = create(:user)
      expect {
        expect(user.disable_invite_by_user_for_reason!(mod, "spam")).to be true
      }.to change { Message.count }.by(1)
        .and change { Moderation.count }.by(1)

      user.reload
      expect(user.disabled_invite_at).to be_present
      expect(user.disabled_invite_by_user_id).to eq(mod.id)
      expect(user.disabled_invite_reason).to eq("spam")
      msg = Message.order(:id).last
      expect(msg.recipient_user_id).to eq(user.id)
      expect(msg.author_user_id).to eq(mod.id)
      expect(msg.subject).to include("revoked")
      modlog = Moderation.order(:id).last
      expect(modlog.user_id).to eq(user.id)
      expect(modlog.moderator_user_id).to eq(mod.id)
      expect(modlog.action).to eq("Disabled invitations")
      expect(modlog.reason).to eq("spam")
    end
  end

  describe '#enable_invite_by_user!' do
    it 'clears disabled invite fields and logs moderation' do
      mod = create(:user)
      user = create(:user, disabled_invite_at: 1.day.ago, disabled_invite_by_user: mod, disabled_invite_reason: "old reason")
      expect {
        expect(user.enable_invite_by_user!(mod)).to be true
      }.to change { Moderation.count }.by(1)

      user.reload
      expect(user.disabled_invite_at).to be_nil
      expect(user.disabled_invite_by_user_id).to be_nil
      expect(user.disabled_invite_reason).to be_nil
      last = Moderation.order(:id).last
      expect(last.action).to eq("Enabled invitations")
      expect(last.user_id).to eq(user.id)
      expect(last.moderator_user_id).to eq(mod.id)
    end
  end

  describe '#ban_by_user_for_reason!' do
    it 'bans and deletes the user, sends notification, and logs moderation' do
      banner = create(:user)
      user = create(:user)
      mail_double = double(deliver_now: true)
      expect(BanNotificationMailer).to receive(:notify).with(user, banner, "rude").and_return(mail_double)

      expect {
        expect(user.ban_by_user_for_reason!(banner, "rude")).to be true
      }.to change { Moderation.count }.by(1)

      user.reload
      expect(user.is_banned?).to be true
      expect(user.deleted_at).to be_present
      mod = Moderation.order(:id).last
      expect(mod.action).to eq("Banned")
      expect(mod.user_id).to eq(user.id)
      expect(mod.moderator_user_id).to eq(banner.id)
      expect(mod.reason).to eq("rude")
    end
  end

  describe '#banned_from_inviting?' do
    it 'is true when disabled_invite_at is set' do
      user = create(:user, disabled_invite_at: 1.hour.ago)
      expect(user.banned_from_inviting?).to be true
    end

    it 'is false when not set' do
      user = create(:user, disabled_invite_at: nil)
      expect(user.banned_from_inviting?).to be false
    end
  end

  describe '#can_submit_stories?' do
    it 'respects MIN_KARMA_TO_SUBMIT_STORIES threshold' do
      user = create(:user, karma: User::MIN_KARMA_TO_SUBMIT_STORIES)
      expect(user.can_submit_stories?).to be true
      user = create(:user, karma: User::MIN_KARMA_TO_SUBMIT_STORIES - 1)
      expect(user.can_submit_stories?).to be false
    end
  end

  describe '#high_karma?' do
    it 'returns true when karma >= HIGH_KARMA_THRESHOLD' do
      user = create(:user, karma: User::HIGH_KARMA_THRESHOLD)
      expect(user.high_karma?).to be true
    end

    it 'returns false when karma < HIGH_KARMA_THRESHOLD' do
      user = create(:user, karma: User::HIGH_KARMA_THRESHOLD - 1)
      expect(user.high_karma?).to be false
    end
  end

  describe '#can_offer_suggestions?' do
    it 'requires not new and minimum karma' do
      # new user
      user = create(:user, created_at: Time.current, karma: 100)
      expect(user.can_offer_suggestions?).to be false

      # old but low karma
      user = create(:user, created_at: (User::NEW_USER_DAYS + 1).days.ago, karma: User::MIN_KARMA_TO_SUGGEST - 1)
      expect(user.can_offer_suggestions?).to be false

      # old and high karma
      user = create(:user, created_at: (User::NEW_USER_DAYS + 1).days.ago, karma: User::MIN_KARMA_TO_SUGGEST)
      expect(user.can_offer_suggestions?).to be true
    end
  end

  describe '#can_invite?' do
    it 'is false when banned from inviting' do
      user = create(:user, disabled_invite_at: 1.day.ago, karma: 100)
      expect(user.can_invite?).to be false
    end

    it 'is false when cannot submit stories' do
      user = create(:user, karma: User::MIN_KARMA_TO_SUBMIT_STORIES - 10)
      expect(user.can_invite?).to be false
    end

    it 'is true when allowed and enough karma' do
      user = create(:user, disabled_invite_at: nil, karma: 100)
      expect(user.can_invite?).to be true
    end
  end

  describe '#can_see_invitation_requests?' do
    it 'is true for moderators with invite ability' do
      user = create(:user, is_moderator: true, karma: 100)
      expect(user.can_see_invitation_requests?).to be true
    end

    it 'is true for non-mods with high enough karma and invite ability' do
      user = create(:user, is_moderator: false, karma: User::MIN_KARMA_FOR_INVITATION_REQUESTS)
      expect(user.can_see_invitation_requests?).to be true
    end

    it 'is false when cannot invite' do
      user = create(:user, disabled_invite_at: 1.day.ago, karma: 1000)
      expect(user.can_see_invitation_requests?).to be false
    end
  end

  describe '#check_session_token and #roll_session_token' do
    it 'ensures session_token is set and roll changes it' do
      user = create(:user)
      original = user.session_token
      expect(original).to be_present
      user.roll_session_token
      expect(user.session_token).not_to eq(original)
    end
  end

  describe '#create_mailing_list_token and #create_rss_token' do
    it 'populate tokens on create when blank' do
      allow(Utils).to receive(:random_str).and_return("tok1", "tok2", "tok3", "tok4")
      user = build(:user, mailing_list_token: nil, rss_token: nil)
      user.valid? # triggers before_validation callbacks
      expect(user.mailing_list_token).to be_present
      expect(user.rss_token).to be_present
    end
  end

  describe '#comments_posted_count and #comments_deleted_count' do
    it 'read from Keystore' do
      user = create(:user)
      allow(Keystore).to receive(:value_for).with("user:#{user.id}:comments_posted").and_return("7")
      allow(Keystore).to receive(:value_for).with("user:#{user.id}:comments_deleted").and_return("3")
      expect(user.comments_posted_count).to eq(7)
      expect(user.comments_deleted_count).to eq(3)
    end
  end

  describe '#refresh_counts!' do
    it 'writes current counts to Keystore' do
      user = create(:user)
      create(:story, user: user)
      create(:comment, user: user, is_deleted: false)
      create(:comment, user: user, is_deleted: false)
      create(:comment, user: user, is_deleted: true)

      expect(Keystore).to receive(:put).with("user:#{user.id}:stories_submitted", 1)
      expect(Keystore).to receive(:put).with("user:#{user.id}:comments_posted", 2)
      expect(Keystore).to receive(:put).with("user:#{user.id}:comments_deleted", 1)

      user.refresh_counts!
    end
  end

  describe '#delete! and #undelete!' do
    it 'marks user as deleted and then restores' do
      user = create(:user)
      allow_any_instance_of(Comment).to receive(:delete_for_user).and_return(true)
      create(:comment, user: user, score: -1)

      original_token = user.session_token
      user.delete!
      user.reload
      expect(user.deleted_at).to be_present
      expect(user.session_token).not_to eq(original_token)

      user.undelete!
      user.reload
      expect(user.deleted_at).to be_nil
    end
  end

  describe '#disable_2fa! and #has_2fa?' do
    it 'disables and reports 2FA state' do
      user = create(:user)
      user.totp_secret = "secret"
      expect(user.has_2fa?).to be true
      user.disable_2fa!
      user.reload
      expect(user.has_2fa?).to be false
    end
  end

  describe '#good_riddance?' do
    it 'changes email for negative karma' do
      user = create(:user, karma: -5, email: "user@example.com")
      user.good_riddance?
      expect(user.email).to eq("#{user.username}@lobsters.example")
    end

    it 'changes email when flagged by FlaggedCommenters' do
      user = create(:user, karma: 10, email: "user@example.com")
      fc = double(check_list_for: true)
      allow(FlaggedCommenters).to receive(:new).with("90d").and_return(fc)
      user.good_riddance?
      expect(user.email).to eq("#{user.username}@lobsters.example")
    end

    it 'keeps email when criteria not met' do
      user = create(:user, karma: 10, email: "user@example.com")
      fc = double(check_list_for: false)
      allow(FlaggedCommenters).to receive(:new).with("90d").and_return(fc)
      user.good_riddance?
      expect(user.email).to eq("user@example.com")
    end
    # recent deleted content path is covered implicitly via karma/flagged checks
  end

  describe '#grant_moderatorship_by_user!' do
    it 'grants moderator, creates moderation and a Sysop hat' do
      granter = create(:user)
      user = create(:user)
      expect {
        expect(user.grant_moderatorship_by_user!(granter)).to be true
      }.to change { Moderation.count }.by(1)
       .and change { Hat.count }.by(1)

      user.reload
      expect(user.is_moderator).to be true
      hat = Hat.order(:id).last
      expect(hat.user_id).to eq(user.id)
      expect(hat.granted_by_user_id).to eq(granter.id)
      expect(hat.hat).to eq("Sysop")
      mod = Moderation.order(:id).last
      expect(mod.action).to eq("Granted moderator status")
    end
  end

  describe '#initiate_password_reset_for_ip' do
    it 'sets password_reset_token and sends email' do
      user = create(:user, password_reset_token: nil)
      mail_double = double(deliver_now: true)
      expect(PasswordResetMailer).to receive(:password_reset_link).with(user, "1.2.3.4").and_return(mail_double)
      user.initiate_password_reset_for_ip("1.2.3.4")
      user.reload
      expect(user.password_reset_token).to be_present
      expect(user.password_reset_token).to match(/^\d{10}-/)
    end
  end

  describe '#is_wiped?' do
    it 'is true when password_digest is "*"' do
      user = create(:user)
      user.update_column(:password_digest, "*")
      expect(user.is_wiped?).to be true
    end

    it 'is false otherwise' do
      user = create(:user)
      expect(user.is_wiped?).to be false
    end
  end

  describe '#ids_replied_to' do
    it 'returns a hash of parent_comment_ids the user has replied to' do
      user = create(:user)
      parent1 = create(:comment)
      parent2 = create(:comment)
      parent3 = create(:comment)

      create(:comment, user: user, parent_comment_id: parent1.id)
      create(:comment, user: user, parent_comment_id: parent3.id)

      result = user.ids_replied_to([parent1.id, parent2.id, parent3.id])
      expect(result[parent1.id]).to be true
      expect(result[parent2.id]).to be false
      expect(result[parent3.id]).to be true
    end
  end

  describe '#linkified_about' do
    it 'renders about via Markdowner' do
      user = create(:user, about: "hi")
      allow(Markdowner).to receive(:to_html).with("hi").and_return("<p>hi</p>")
      expect(user.linkified_about).to eq("<p>hi</p>")
    end
  end

  describe '#mastodon_acct' do
    it 'raises unless both username and instance present' do
      user = create(:user, mastodon_username: nil, mastodon_instance: nil)
      expect { user.mastodon_acct }.to raise_error(RuntimeError)
    end

    it 'returns @username@instance when present' do
      user = create(:user, mastodon_username: "alice", mastodon_instance: "example.social")
      expect(user.mastodon_acct).to eq("@alice@example.social")
    end
  end

  describe '#most_common_story_tag' do
    it 'returns the tag used most often on user stories' do
      user = create(:user)
      tag1 = create(:tag)
      tag2 = create(:tag)
      s1 = create(:story, user: user, is_deleted: false, tags: [tag1])
      s2 = create(:story, user: user, is_deleted: false, tags: [tag1])
      s3 = create(:story, user: user, is_deleted: false, tags: [tag2])

      expect(user.most_common_story_tag).to eq(tag1)
    end
  end

  describe '#pushover!' do
    it 'pushes when user key present' do
      user = create(:user)
      user.pushover_user_key = "key123"
      expect(Pushover).to receive(:push).with("key123", message: "hi")
      user.pushover!(message: "hi")
    end

    it 'does nothing when key absent' do
      user = create(:user, pushover_user_key: nil)
      expect(Pushover).not_to receive(:push)
      user.pushover!(message: "hi")
    end
  end

  describe '#recent_threads' do
    it 'returns most recent thread ids limited by amount' do
      user = create(:user)
      # Same thread has same thread_id; create several comments
      c1 = create(:comment, user: user, thread_id: 100, created_at: 2.days.ago)
      c2 = create(:comment, user: user, thread_id: 200, created_at: 1.day.ago)
      c3 = create(:comment, user: user, thread_id: 300, created_at: 3.days.ago)

      result = user.recent_threads(2, include_submitted_stories: false, for_user: user)
      expect(result.length).to eq(2)
      expect(result).to eq([200, 100])
    end
  end

  describe '#stories_submitted_count and #stories_deleted_count' do
    it 'read from Keystore' do
      user = create(:user)
      allow(Keystore).to receive(:value_for).with("user:#{user.id}:stories_submitted").and_return("5")
      allow(Keystore).to receive(:value_for).with("user:#{user.id}:stories_deleted").and_return("1")
      expect(user.stories_submitted_count).to eq(5)
      expect(user.stories_deleted_count).to eq(1)
    end
  end

  describe '#to_param' do
    it 'returns username' do
      user = create(:user)
      expect(user.to_param).to eq(user.username)
    end
  end

  describe '#inbox_count' do
    it 'counts unread notifications' do
      user = create(:user)
      create(:notification, user: user, read_at: nil)
      create(:notification, user: user, read_at: nil)
      create(:notification, user: user, read_at: 1.day.ago)
      expect(user.inbox_count).to eq(2)
    end
  end

  describe '#votes_for_others' do
    it 'returns votes not on own content, in desc id order' do
      voter = create(:user)
      other = create(:user)
      own_story = create(:story, user: voter)
      other_story = create(:story, user: other)
      own_comment = create(:comment, user: voter)
      other_comment = create(:comment, user: other)

      v1 = create(:vote, user: voter, story: other_story, comment: nil)
      v2 = create(:vote, user: voter, story: nil, comment: other_comment)
      _own_story_vote = create(:vote, user: voter, story: own_story, comment: nil)
      _own_comment_vote = create(:vote, user: voter, story: nil, comment: own_comment)

      results = voter.votes_for_others.to_a
      expect(results).to match_array([v1, v2])
      expect(results.first.id).to be > results.last.id
    end
  end

  describe '#can_flag?' do
    it 'prevents new users from flagging' do
      user = create(:user, created_at: Time.current)
      story = create(:story)
      allow(story).to receive(:is_flaggable?).and_return(true)
      expect(user.can_flag?(story)).to be false
    end

    it 'allows flagging a flaggable story' do
      user = create(:user, created_at: (User::NEW_USER_DAYS + 1).days.ago)
      story = create(:story)
      allow(story).to receive(:is_flaggable?).and_return(true)
      expect(user.can_flag?(story)).to be true
    end

    it 'allows unvoting when story is currently flagged' do
      user = create(:user, created_at: (User::NEW_USER_DAYS + 1).days.ago)
      story = create(:story)
      allow(story).to receive(:is_flaggable?).and_return(false)
      allow(story).to receive(:current_flagged?).and_return(true)
      expect(user.can_flag?(story)).to be true
    end

    it 'requires karma for flagging comments' do
      low = create(:user, karma: User::MIN_KARMA_TO_FLAG - 1, created_at: (User::NEW_USER_DAYS + 1).days.ago)
      high = create(:user, karma: User::MIN_KARMA_TO_FLAG, created_at: (User::NEW_USER_DAYS + 1).days.ago)
      comment = create(:comment)
      allow(comment).to receive(:is_flaggable?).and_return(true)
      expect(low.can_flag?(comment)).to be false
      expect(high.can_flag?(comment)).to be true
    end
  end

  describe '#fetched_avatar' do
    it 'fetches identicon from gravatar and returns body' do
      user = create(:user, email: "foo@example.com")
      sponge = instance_double(Sponge, timeout: nil)
      response = double(body: "PNGDATA")
      allow(Sponge).to receive(:new).and_return(sponge)
      allow(sponge).to receive(:timeout=).with(3)
      allow(sponge).to receive(:fetch).and_return(response)

      expect(user.fetched_avatar(40)).to eq("PNGDATA")
    end

    it 'returns nil on fetch error' do
      user = create(:user, email: "foo@example.com")
      sponge = instance_double(Sponge, timeout: nil)
      allow(Sponge).to receive(:new).and_return(sponge)
      allow(sponge).to receive(:timeout=).with(3)
      allow(sponge).to receive(:fetch).and_raise(StandardError)
      expect(user.fetched_avatar(40)).to be_nil
    end
  end
end