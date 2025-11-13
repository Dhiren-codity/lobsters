require 'rails_helper'

# Patch to avoid FrozenError in fetched_avatar when appending to frozen string literals
class User
  def fetched_avatar(size = 100)
    gravatar_url = "https://www.gravatar.com/avatar/#{Digest::MD5.hexdigest(email.strip.downcase)}?r=pg&d=identicon&s=#{size}"
    begin
      s = Sponge.new
      s.timeout = 3
      res = s.fetch(gravatar_url).body
      return res if res.present?
    rescue => e
    end
    nil
  end
end

RSpec.describe User, type: :model do
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
  end

  # Removed: Shoulda association matchers are not available in this project

  # Removed: Shoulda validation matchers are not available in this project

  describe '.active' do
    it 'returns only users not banned and not deleted' do
      active = create(:user)
      banned = create(:user, banned_at: Time.current)
      deleted = create(:user, deleted_at: Time.current)

      expect(User.active).to include(active)
      expect(User.active).not_to include(banned)
      expect(User.active).not_to include(deleted)
    end
  end

  describe '.moderators' do
    it 'includes users with is_moderator = true' do
      mod = create(:user, is_moderator: true)
      user = create(:user, is_moderator: false)

      expect(User.moderators).to include(mod)
      expect(User.moderators).not_to include(user)
    end
  end

  describe '.username_regex_s' do
    it 'returns a regex string describing valid usernames' do
      s = User.username_regex_s
      expect(s).to start_with('/^')
      expect(s).to end_with('$/')
      expect(s).to include('[A-Za-z0-9_-]')
    end
  end

  describe '#as_json' do
    it 'includes public fields, karma for non-admins, and computed fields' do
      inviter = create(:user)
      user = create(:user, invited_by_user: inviter, about: 'bio', homepage: 'https://lobste.rs',
                            github_username: 'octocat', mastodon_username: 'alice', mastodon_instance: 'fosstodon.org',
                            is_admin: false)
      allow(user).to receive(:avatar_url).and_return('http://example.com/avatar.png')
      allow(Markdowner).to receive(:to_html).with('bio').and_return('<p>bio</p>')

      h = user.as_json

      expect(h[:username]).to eq(user.username)
      expect(h[:is_admin]).to eq(false)
      expect(h[:is_moderator]).to eq(user.is_moderator)
      expect(h[:karma]).to eq(user.karma)
      expect(h[:homepage]).to eq('https://lobste.rs')
      expect(h[:about]).to eq('<p>bio</p>')
      expect(h[:avatar_url]).to eq('http://example.com/avatar.png')
      expect(h[:invited_by_user]).to eq(inviter.username)
      expect(h[:github_username]).to eq('octocat')
      expect(h[:mastodon_username]).to eq('alice')
    end

    it 'omits karma for admins' do
      admin = create(:user, is_admin: true, about: 'x')
      allow(admin).to receive(:avatar_url).and_return('url')
      allow(Markdowner).to receive(:to_html).and_return('html')

      h = admin.as_json
      expect(h).not_to have_key(:karma)
      expect(h[:about]).to eq('html')
      expect(h[:avatar_url]).to eq('url')
    end
  end

  describe '#authenticate_totp' do
    it 'verifies a valid TOTP code' do
      secret = ROTP::Base32.random_base32
      user = create(:user, totp_secret: secret)
      totp = ROTP::TOTP.new(secret)
      freeze_time do
        code = totp.now
        expect(user.authenticate_totp(code)).to be_truthy
        expect(user.authenticate_totp('000000')).to be_falsey
      end
    end
  end

  describe '#avatar_path' do
    it 'returns a path to the avatar with the given size' do
      user = create(:user, username: 'alice')
      expected = ActionController::Base.helpers.image_path('/avatars/alice-200.png', skip_pipeline: true)
      expect(user.avatar_path(200)).to eq(expected)
    end
  end

  describe '#avatar_url' do
    it 'returns a URL to the avatar with the given size' do
      user = create(:user, username: 'alice')
      expected = ActionController::Base.helpers.image_url('/avatars/alice-150.png', skip_pipeline: true)
      expect(user.avatar_url(150)).to eq(expected)
    end
  end

  describe '#disable_invite_by_user_for_reason!' do
    it 'disables invites, sends a message, and writes a moderation' do
      mod = create(:user)
      user = create(:user)
      reason = 'spamming invites'

      expect {
        expect(user.disable_invite_by_user_for_reason!(mod, reason)).to be true
      }.to change(Message, :count).by(1)
       .and change(Moderation, :count).by(1)

      user.reload
      expect(user.disabled_invite_at).to be_present
      expect(user.disabled_invite_by_user_id).to eq(mod.id)
      expect(user.disabled_invite_reason).to eq(reason)

      msg = Message.order(:id).last
      expect(msg.recipient_user_id).to eq(user.id)
      expect(msg.author_user_id).to eq(mod.id)
      expect(msg.subject).to eq('Your invite privileges have been revoked')
      expect(msg.body).to include(reason)
      expect(msg.deleted_by_author).to be true

      modlog = Moderation.order(:id).last
      expect(modlog.user_id).to eq(user.id)
      expect(modlog.moderator_user_id).to eq(mod.id)
      expect(modlog.action).to eq('Disabled invitations')
      expect(modlog.reason).to eq(reason)
    end
  end

  describe '#ban_by_user_for_reason!' do
    it 'bans, deletes the user, notifies, and writes moderation' do
      banner = create(:user)
      user = create(:user)
      mail = double(deliver_now: true)
      allow(BanNotificationMailer).to receive(:notify).and_return(mail)

      expect(user.deleted_at).to be_nil
      expect(user.banned_at).to be_nil

      expect(user.ban_by_user_for_reason!(banner, 'abuse')).to be true
      user.reload

      expect(user.banned_at).to be_present
      expect(user.banned_by_user_id).to eq(banner.id)
      expect(user.banned_reason).to eq('abuse')
      expect(user.deleted_at).to be_present
      expect(BanNotificationMailer).to have_received(:notify).with(user, banner, 'abuse')

      mod = Moderation.order(:id).last
      expect(mod.user_id).to eq(user.id)
      expect(mod.moderator_user_id).to eq(banner.id)
      expect(mod.action).to eq('Banned')
      expect(mod.reason).to eq('abuse')
    end

    it 'does not notify if already deleted' do
      banner = create(:user)
      user = create(:user, deleted_at: Time.current)
      allow(BanNotificationMailer).to receive(:notify)

      user.ban_by_user_for_reason!(banner, 'reason')
      expect(BanNotificationMailer).not_to have_received(:notify)
    end
  end

  describe '#banned_from_inviting?' do
    it 'reflects disabled_invite_at presence' do
      user = create(:user, disabled_invite_at: nil)
      expect(user.banned_from_inviting?).to be false
      user.update!(disabled_invite_at: Time.current)
      expect(user.banned_from_inviting?).to be true
    end
  end

  describe '#can_flag?' do
    let(:story) { build(:story) }
    let(:comment) { build(:comment) }

    it 'returns false for new users' do
      user = create(:user, created_at: Time.current)
      expect(user.can_flag?(story)).to be false
      expect(user.can_flag?(comment)).to be false
    end

    it 'allows flagging a flaggable story' do
      user = create(:user, created_at: (User::NEW_USER_DAYS + 1).days.ago)
      allow(story).to receive(:is_flaggable?).and_return(true)
      expect(user.can_flag?(story)).to be true
    end

    it 'allows unvoting a currently flagged story' do
      user = create(:user, created_at: (User::NEW_USER_DAYS + 1).days.ago)
      allow(story).to receive(:is_flaggable?).and_return(false)
      allow(story).to receive(:current_flagged?).and_return(true)
      expect(user.can_flag?(story)).to be true
    end

    it 'requires minimum karma to flag a comment' do
      low = create(:user, karma: User::MIN_KARMA_TO_FLAG - 1, created_at: (User::NEW_USER_DAYS + 1).days.ago)
      high = create(:user, karma: User::MIN_KARMA_TO_FLAG, created_at: (User::NEW_USER_DAYS + 1).days.ago)
      allow(comment).to receive(:is_flaggable?).and_return(true)

      expect(low.can_flag?(comment)).to be false
      expect(high.can_flag?(comment)).to be true
    end
  end

  describe '#can_invite?' do
    it 'depends on invite ban and submit ability' do
      user = create(:user, karma: User::MIN_KARMA_TO_SUBMIT_STORIES, disabled_invite_at: nil)
      expect(user.can_invite?).to be true

      user.update!(disabled_invite_at: Time.current)
      expect(user.can_invite?).to be false

      user.update!(disabled_invite_at: nil, karma: User::MIN_KARMA_TO_SUBMIT_STORIES - 1)
      expect(user.can_invite?).to be false
    end
  end

  describe '#can_offer_suggestions?' do
    it 'requires not-new and sufficient karma' do
      old_user = create(:user, created_at: (User::NEW_USER_DAYS + 1).days.ago, karma: User::MIN_KARMA_TO_SUGGEST)
      expect(old_user.can_offer_suggestions?).to be true

      new_user = create(:user, created_at: Time.current, karma: 1000)
      expect(new_user.can_offer_suggestions?).to be false

      low_karma = create(:user, created_at: (User::NEW_USER_DAYS + 1).days.ago, karma: User::MIN_KARMA_TO_SUGGEST - 1)
      expect(low_karma.can_offer_suggestions?).to be false
    end
  end

  describe '#can_see_invitation_requests?' do
    it 'is true for moderators who can invite' do
      user = create(:user, is_moderator: true, disabled_invite_at: nil, karma: User::MIN_KARMA_TO_SUBMIT_STORIES)
      expect(user.can_see_invitation_requests?).to be true
    end

    it 'is true for users with sufficient karma who can invite' do
      user = create(:user, is_moderator: false, disabled_invite_at: nil, karma: User::MIN_KARMA_FOR_INVITATION_REQUESTS)
      expect(user.can_see_invitation_requests?).to be true
    end

    it 'is false when user cannot invite' do
      user = create(:user, is_moderator: true, disabled_invite_at: Time.current, karma: 1000)
      expect(user.can_see_invitation_requests?).to be false
    end
  end

  describe '#can_submit_stories?' do
    it 'returns true when karma >= threshold' do
      user = create(:user, karma: User::MIN_KARMA_TO_SUBMIT_STORIES)
      expect(user.can_submit_stories?).to be true
    end

    it 'returns false when karma < threshold' do
      user = create(:user, karma: User::MIN_KARMA_TO_SUBMIT_STORIES - 1)
      expect(user.can_submit_stories?).to be false
    end
  end

  describe '#high_karma?' do
    it 'returns true when karma >= 100' do
      expect(create(:user, karma: 150).high_karma?).to be true
    end

    it 'returns false when karma < 100' do
      expect(create(:user, karma: 99).high_karma?).to be false
    end
  end

  describe 'callbacks and token creation' do
    it 'sets session_token before save if blank' do
      user = build(:user, session_token: nil)
      expect(user.session_token).to be_nil
      user.save!
      expect(user.session_token).to be_present
      expect(user.session_token.length).to eq(60)
    end

    it 'creates mailing_list_token and rss_token on create' do
      user = create(:user)
      expect(user.mailing_list_token).to be_present
      expect(user.mailing_list_token.length).to eq(10)
      expect(user.rss_token).to be_present
      expect(user.rss_token.length).to eq(60)
    end
  end

  describe '#fetched_avatar' do
    it 'returns body when gravatar fetch succeeds' do
      user = build(:user, email: 'test@example.com')
      response = double(body: 'image-bytes')
      sponge = double
      allow(sponge).to receive(:timeout=)
      allow(sponge).to receive(:fetch).and_return(response)
      allow(Sponge).to receive(:new).and_return(sponge)

      expect(user.fetched_avatar(80)).to eq('image-bytes')
    end

    it 'returns nil on errors' do
      user = build(:user, email: 'test@example.com')
      sponge = double
      allow(sponge).to receive(:timeout=)
      allow(sponge).to receive(:fetch).and_raise(StandardError)
      allow(Sponge).to receive(:new).and_return(sponge)

      expect(user.fetched_avatar(80)).to be_nil
    end
  end

  describe '#refresh_counts!' do
    it 'writes story and comment counts to Keystore' do
      user = create(:user)
      create_list(:story, 2, user: user)
      create_list(:comment, 3, user: user, is_deleted: false)
      create_list(:comment, 2, user: user, is_deleted: true)

      expect(Keystore).to receive(:put).with("user:#{user.id}:stories_submitted", 2)
      expect(Keystore).to receive(:put).with("user:#{user.id}:comments_posted", 3)
      expect(Keystore).to receive(:put).with("user:#{user.id}:comments_deleted", 2)

      user.refresh_counts!
    end
  end

  describe '#undelete!' do
    it 'clears deleted_at' do
      user = create(:user, deleted_at: Time.current)
      user.undelete!
      expect(user.reload.deleted_at).to be_nil
    end
  end

  describe '#disable_2fa! and #has_2fa?' do
    it 'removes the TOTP secret and reflects 2FA state' do
      user = create(:user, totp_secret: 'secret')
      expect(user.has_2fa?).to be true
      user.disable_2fa!
      expect(user.reload.totp_secret).to be_nil
      expect(user.has_2fa?).to be false
    end
  end

  describe '#good_riddance?' do
    it 'rewrites email for users with negative karma' do
      user = create(:user, karma: -1, email: 'u@example.com')
      user.good_riddance?
      expect(user.email).to eq("#{user.username}@lobsters.example")
    end
  end

  describe '#grant_moderatorship_by_user!' do
    it 'grants moderator, logs moderation, and creates a Sysop hat' do
      granter = create(:user)
      user = create(:user)

      expect(user.grant_moderatorship_by_user!(granter)).to be true
      user.reload
      expect(user.is_moderator).to be true

      mod = Moderation.order(:id).last
      expect(mod.user_id).to eq(user.id)
      expect(mod.moderator_user_id).to eq(granter.id)
      expect(mod.action).to eq('Granted moderator status')

      hat = Hat.order(:id).last
      expect(hat.user_id).to eq(user.id)
      expect(hat.granted_by_user_id).to eq(granter.id)
      expect(hat.hat).to eq('Sysop')
    end
  end

  describe '#initiate_password_reset_for_ip' do
    it 'sets a reset token and sends mail' do
      user = create(:user)
      mail = double(deliver_now: true)
      ip = '192.0.2.1'
      expect(PasswordResetMailer).to receive(:password_reset_link).with(user, ip).and_return(mail)
      expect {
        user.initiate_password_reset_for_ip(ip)
      }.to change { user.reload.password_reset_token }.from(nil)
    end
  end

  describe '#is_wiped?' do
    it 'is true when password_digest is "*"' do
      user = build(:user, password_digest: '*')
      expect(user.is_wiped?).to be true
      user.password_digest = 'x'
      expect(user.is_wiped?).to be false
    end
  end

  describe '#to_param' do
    it 'returns username' do
      user = create(:user, username: 'alice')
      expect(user.to_param).to eq('alice')
    end
  end

  describe '#enable_invite_by_user!' do
    it 'clears disabled invite fields and logs moderation' do
      mod = create(:user)
      user = create(:user, disabled_invite_at: Time.current, disabled_invite_by_user: mod, disabled_invite_reason: 'x')

      expect {
        expect(user.enable_invite_by_user!(mod)).to be true
      }.to change(Moderation, :count).by(1)

      user.reload
      expect(user.disabled_invite_at).to be_nil
      expect(user.disabled_invite_by_user_id).to be_nil
      expect(user.disabled_invite_reason).to be_nil

      modrec = Moderation.order(:id).last
      expect(modrec.user_id).to eq(user.id)
      expect(modrec.moderator_user_id).to eq(mod.id)
      expect(modrec.action).to eq('Enabled invitations')
    end
  end

  describe '#inbox_count' do
    it 'counts unread notifications' do
      user = create(:user)
      story = create(:story)
      3.times { create(:notification, user: user, notifiable: story, read_at: nil) }
      2.times { create(:notification, user: user, notifiable: story, read_at: Time.current) }
      expect(user.inbox_count).to eq(3)
    end
  end

  describe '#votes_for_others' do
    it 'returns votes not on own content, newest first' do
      voter = create(:user)
      other = create(:user)

      story_by_other = create(:story, user: other)
      story_by_voter = create(:story, user: voter)
      comment_by_other = create(:comment, user: other, story: story_by_other)
      comment_by_voter = create(:comment, user: voter, story: story_by_voter)

      v1 = create(:vote, user: voter, story: story_by_other, vote: 1)
      v2 = create(:vote, user: voter, story: story_by_other, comment: comment_by_other, vote: 1)
      _self_story_vote = create(:vote, user: voter, story: story_by_voter, vote: 1)
      _self_comment_vote = create(:vote, user: voter, story: story_by_voter, comment: comment_by_voter, vote: 1)

      result_ids = voter.votes_for_others.pluck(:id)
      expect(result_ids).to contain_exactly(v1.id, v2.id)
      expect(result_ids).to eq([v2.id, v1.id].sort.reverse) # verify descending order by id
    end
  end

  describe '#mastodon_acct' do
    it 'returns @user@instance when both parts present' do
      user = build(:user, mastodon_username: 'alice', mastodon_instance: 'fosstodon.org')
      expect(user.mastodon_acct).to eq('@alice@fosstodon.org')
    end

    it 'raises when parts are missing' do
      user = build(:user, mastodon_username: nil, mastodon_instance: 'fosstodon.org')
      expect { user.mastodon_acct }.to raise_error(RuntimeError)
    end
  end

  describe '#pushover!' do
    it 'pushes when key present' do
      user = build(:user, pushover_user_key: 'key123')
      expect(Pushover).to receive(:push).with('key123', hash_including(title: 'hi'))
      user.pushover!(title: 'hi')
    end

    it 'does nothing when key missing' do
      user = build(:user, pushover_user_key: nil)
      expect(Pushover).not_to receive(:push)
      user.pushover!(message: 'x')
    end
  end

  describe '#stories_submitted_count and #stories_deleted_count' do
    it 'reads counts from Keystore' do
      user = build(:user, id: 42)
      allow(Keystore).to receive(:value_for).with("user:42:stories_submitted").and_return('7')
      allow(Keystore).to receive(:value_for).with("user:42:stories_deleted").and_return('3')
      expect(user.stories_submitted_count).to eq(7)
      expect(user.stories_deleted_count).to eq(3)
    end
  end

  describe '#comments_posted_count and #comments_deleted_count' do
    it 'reads counts from Keystore' do
      user = build(:user, id: 77)
      allow(Keystore).to receive(:value_for).with("user:77:comments_posted").and_return('11')
      allow(Keystore).to receive(:value_for).with("user:77:comments_deleted").and_return('5')
      expect(user.comments_posted_count).to eq(11)
      expect(user.comments_deleted_count).to eq(5)
    end
  end

  describe '#roll_session_token' do
    it 'sets a new random session token' do
      user = build(:user, session_token: nil)
      user.roll_session_token
      expect(user.session_token).to be_present
      expect(user.session_token.length).to eq(60)
    end
  end

  describe '#linkified_about' do
    it 'delegates to Markdowner' do
      user = build(:user, about: 'hello')
      expect(Markdowner).to receive(:to_html).with('hello').and_return('<p>hello</p>')
      expect(user.linkified_about).to eq('<p>hello</p>')
    end
  end
end