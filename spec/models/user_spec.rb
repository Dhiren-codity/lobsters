# typed: false

require 'rails_helper'
require 'spec_helper'

describe User do
  it 'has a valid username' do
    expect { create(:user, username: nil) }.to raise_error
    expect { create(:user, username: '') }.to raise_error
    expect { create(:user, username: '*') }.to raise_error
    # security controls, usernames are used in queries and filenames
    expect { create(:user, username: "a'b") }.to raise_error
    expect { create(:user, username: 'a"b') }.to raise_error
    expect { create(:user, username: '../b') }.to raise_error

    create(:user, username: 'newbie')
    expect { create(:user, username: 'newbie') }.to raise_error

    create(:user, username: 'underscores_and-dashes')
    invalid_username_variants = %w[underscores-and_dashes underscores_and_dashes underscores-and-dashes]

    invalid_username_variants.each do |invalid_username|
      subject = build(:user, username: invalid_username)
      expect(subject).to_not be_valid
      expect(subject.errors[:username]).to eq(['is already in use (perhaps swapping _ and -)'])
    end

    create(:user, username: 'case_insensitive')
    expect { create(:user, username: 'CASE_INSENSITIVE') }.to raise_error
    expect { create(:user, username: 'case_Insensitive') }.to raise_error
    expect { create(:user, username: 'case-insensITive') }.to raise_error
  end

  it 'has a valid email address' do
    create(:user, email: 'user@example.com')

    # duplicate
    expect { create(:user, email: 'user@example.com') }.to raise_error

    # bad address
    expect { create(:user, email: 'user@') }.to raise_error

    # address too long
    expect(build(:user, email: 'a' * 95 + '@example.com')).to_not be_valid

    # not a disposable email
    allow(File).to receive(:read).with(FetchEmailBlocklistJob::STORAGE_PATH).and_return('disposable.com')
    expect(build(:user, email: 'user@disposable.com')).to_not be_valid
  end

  it 'has a limit on the password reset token field' do
    user = build(:user, password_reset_token: 'a' * 100)
    user.valid?
    expect(user.errors[:password_reset_token]).to eq(['is too long (maximum is 75 characters)'])
  end

  it 'has a limit on the session token field' do
    user = build(:user, session_token: 'a' * 100)
    user.valid?
    expect(user.errors[:session_token]).to eq(['is too long (maximum is 75 characters)'])
  end

  it 'has a limit on the about field' do
    user = build(:user, about: 'a' * 16_777_218)
    user.valid?
    expect(user.errors[:about]).to eq(['is too long (maximum is 16777215 characters)'])
  end

  it 'has a limit on the rss token field' do
    user = build(:user, rss_token: 'a' * 100)
    user.valid?
    expect(user.errors[:rss_token]).to eq(['is too long (maximum is 75 characters)'])
  end

  it 'has a limit on the mailing list token field' do
    user = build(:user, mailing_list_token: 'a' * 100)
    user.valid?
    expect(user.errors[:mailing_list_token]).to eq(['is too long (maximum is 75 characters)'])
  end

  it 'has a limit on the banned reason field' do
    user = build(:user, banned_reason: 'a' * 300)
    user.valid?
    expect(user.errors[:banned_reason]).to eq(['is too long (maximum is 256 characters)'])
  end

  it 'has a limit on the disabled invite reason field' do
    user = build(:user, disabled_invite_reason: 'a' * 300)
    user.valid?
    expect(user.errors[:disabled_invite_reason]).to eq(['is too long (maximum is 200 characters)'])
  end

  it 'has a valid homepage' do
    expect(build(:user, homepage: 'https://lobste.rs')).to be_valid
    expect(build(:user, homepage: 'https://lobste.rs/w00t')).to be_valid
    expect(build(:user, homepage: 'https://lobste.rs/w00t.path')).to be_valid
    expect(build(:user, homepage: 'https://lobste.rs/w00t')).to be_valid
    expect(build(:user, homepage: 'https://ሙዚቃ.et')).to be_valid
    expect(build(:user, homepage: 'http://lobste.rs/ሙዚቃ')).to be_valid
    expect(build(:user, homepage: 'http://www.lobste.rs/')).to be_valid
    expect(build(:user, homepage: 'gemini://www.lobste.rs/')).to be_valid
    expect(build(:user, homepage: 'gopher://www.lobste.rs/')).to be_valid

    expect(build(:user, homepage: 'http://')).to_not be_valid
    expect(build(:user, homepage: 'http://notld')).to_not be_valid
    expect(build(:user, homepage: 'http://notld/w00t.path')).to_not be_valid
    expect(build(:user, homepage: 'ftp://invalid.protocol')).to_not be_valid
  end

  it 'authenticates properly' do
    u = create(:user, password: 'hunter2')

    expect(u.password_digest.length).to be > 20

    expect(u.authenticate('hunter2')).to eq(u)
    expect(u.authenticate('hunteR2')).to be false
  end

  it 'gets an error message after registering banned name' do
    expect { create(:user, username: 'admin') }
      .to raise_error('Validation failed: Username is not permitted')
  end

  it 'shows a user is banned or not' do
    u = create(:user, :banned)
    user = create(:user)
    expect(u.is_banned?).to be true
    expect(user.is_banned?).to be false
  end

  it 'shows a user is active or not' do
    u = create(:user, :banned)
    user = create(:user)
    expect(u.is_active?).to be false
    expect(user.is_active?).to be true
  end

  it 'shows a user is recent or not' do
    user = create(:user, created_at: Time.current)
    expect(user.is_new?).to be true
    user = create(:user, created_at: (User::NEW_USER_DAYS + 1).days.ago)
    expect(user.is_new?).to be false
  end

  it 'unbans a user' do
    u = create(:user, :banned)
    expect(u.unban_by_user!(User.first, 'seems ok now')).to be true
  end

  it 'tells if a user is a heavy self promoter' do
    u = create(:user)

    expect(u.is_heavy_self_promoter?).to be false

    create(:story, title: 'ti1', url: 'https://a.com/1', user_id: u.id,
                   user_is_author: true)
    # require at least 2 stories to be considered heavy self promoter
    expect(u.is_heavy_self_promoter?).to be false

    create(:story, title: 'ti2', url: 'https://a.com/2', user_id: u.id,
                   user_is_author: true)
    # 100% of 2 stories
    expect(u.is_heavy_self_promoter?).to be true

    create(:story, title: 'ti3', url: 'https://a.com/3', user_id: u.id,
                   user_is_author: false)
    # 66.7% of 3 stories
    expect(u.is_heavy_self_promoter?).to be true

    create(:story, title: 'ti4', url: 'https://a.com/4', user_id: u.id,
                   user_is_author: false)
    # 50% of 4 stories
    expect(u.is_heavy_self_promoter?).to be false
  end

  describe 'associations' do
    it 'has expected relationships' do
      expect(described_class.reflect_on_association(:stories).macro).to eq(:has_many)
      expect(described_class.reflect_on_association(:comments).macro).to eq(:has_many)
      expect(described_class.reflect_on_association(:sent_messages).macro).to eq(:has_many)
      expect(described_class.reflect_on_association(:received_messages).macro).to eq(:has_many)
      expect(described_class.reflect_on_association(:invitations).macro).to eq(:has_many)
      expect(described_class.reflect_on_association(:votes).macro).to eq(:has_many)
      expect(described_class.reflect_on_association(:hats).macro).to eq(:has_many)
      expect(described_class.reflect_on_association(:notifications).macro).to eq(:has_many)
    end
  end

  describe 'additional validations' do
    it 'requires password on create' do
      user = build(:user, password: nil)
      expect(user).to_not be_valid
      expect(user.errors[:password]).to be_present
    end

    it 'requires boolean settings to be true or false' do
      user = build(:user, show_email: nil, is_admin: nil, is_moderator: nil, pushover_mentions: nil)
      expect(user).to_not be_valid
      expect(user.errors[:show_email]).to be_present
      expect(user.errors[:is_admin]).to be_present
      expect(user.errors[:is_moderator]).to be_present
      expect(user.errors[:pushover_mentions]).to be_present
    end

    it 'validates prefers_color_scheme and prefers_contrast inclusion' do
      user = build(:user, prefers_color_scheme: 'invalid', prefers_contrast: 'invalid')
      expect(user).to_not be_valid
      expect(user.errors[:prefers_color_scheme]).to be_present
      expect(user.errors[:prefers_contrast]).to be_present
    end
  end

  describe 'scopes' do
    it 'returns only active users for .active' do
      active = create(:user, banned_at: nil, deleted_at: nil)
      banned = create(:user, banned_at: Time.current)
      deleted = create(:user, deleted_at: Time.current)
      expect(User.active).to include(active)
      expect(User.active).to_not include(banned)
      expect(User.active).to_not include(deleted)
    end

    it 'includes users by moderator flag in .moderators' do
      mod = create(:user, is_moderator: true)
      non_mod = create(:user, is_moderator: false)
      expect(User.moderators).to include(mod)
      expect(User.moderators).to_not include(non_mod)
    end
  end

  describe '.username_regex_s' do
    it 'returns a stringified regex for valid usernames' do
      s = User.username_regex_s
      expect(s).to start_with('/^')
      expect(s).to end_with('$/')
      expect(s).to include('[A-Za-z0-9')
    end
  end

  describe '#as_json' do
    let(:inviter) { create(:user) }

    it 'includes expected fields for a non-admin and hides admin-only fields' do
      user = create(:user, invited_by_user: inviter, about: 'hi', github_username: 'octocat',
                           mastodon_username: 'alice', mastodon_instance: 'example.social')
      allow(Markdowner).to receive(:to_html).with('hi').and_return('<p>hi</p>')
      json = user.as_json
      expect(json[:username]).to eq(user.username)
      expect(json[:karma]).to eq(user.karma)
      expect(json[:about]).to eq('<p>hi</p>')
      expect(json[:avatar_url]).to include("/avatars/#{user.username}-100.png")
      expect(json[:invited_by_user]).to eq(inviter.username)
      expect(json[:github_username]).to eq('octocat')
      expect(json[:mastodon_username]).to eq('alice')
      expect(json[:homepage]).to eq(user.homepage)
    end

    it 'omits karma for admin users' do
      admin = create(:user, is_admin: true, invited_by_user: inviter, about: '')
      allow(Markdowner).to receive(:to_html).and_return('')
      json = admin.as_json
      expect(json.key?(:karma)).to be false
      expect(json[:invited_by_user]).to eq(inviter.username)
    end

    it 'omits optional oauth fields when blank' do
      user = create(:user, github_username: nil, mastodon_username: nil, mastodon_instance: nil, about: '')
      allow(Markdowner).to receive(:to_html).and_return('')
      json = user.as_json
      expect(json.key?(:github_username)).to be false
      expect(json.key?(:mastodon_username)).to be false
    end
  end

  describe '#authenticate_totp' do
    include ActiveSupport::Testing::TimeHelpers

    it 'verifies valid and invalid TOTP codes' do
      secret = ROTP::Base32.random
      user = create(:user, totp_secret: secret)
      frozen_time = Time.at(1_700_000_000)
      travel_to(frozen_time) do
        code = ROTP::TOTP.new(secret).at(frozen_time)
        expect(user.authenticate_totp(code)).to be_truthy
        expect(user.authenticate_totp('000000')).to be_falsey
      end
    end
  end

  describe '#avatar_path and #avatar_url' do
    it 'builds avatar asset paths' do
      user = build(:user, username: 'alice')
      expect(user.avatar_path(80)).to match(%r{/avatars/alice-80\.png\z})
      expect(user.avatar_url(80)).to include('/avatars/alice-80.png')
    end
  end

  describe '#disable_invite_by_user_for_reason!' do
    let(:disabler) { create(:user) }
    let(:user) { create(:user) }

    it 'disables invites, sends message, and records moderation' do
      reason = 'spam invites'
      expect(user.disable_invite_by_user_for_reason!(disabler, reason)).to be true
      user.reload
      expect(user.disabled_invite_at).to be_present
      expect(user.disabled_invite_by_user_id).to eq(disabler.id)
      expect(user.disabled_invite_reason).to eq(reason)
      expect(Message.where(author_user_id: disabler.id, recipient_user_id: user.id).count).to eq(1)
      mod = Moderation.where(user_id: user.id).order(id: :desc).first
      expect(mod).to be_present
      expect(mod.action).to eq('Disabled invitations')
      expect(mod.reason).to eq(reason)
    end
  end

  describe '#enable_invite_by_user!' do
    let(:mod) { create(:user) }

    it 'reenables invites and records moderation' do
      user = create(:user, disabled_invite_at: 1.day.ago, disabled_invite_by_user: mod,
                           disabled_invite_reason: 'old reason')
      expect(user.enable_invite_by_user!(mod)).to be true
      user.reload
      expect(user.disabled_invite_at).to be_nil
      expect(user.disabled_invite_by_user_id).to be_nil
      expect(user.disabled_invite_reason).to be_nil
      m = Moderation.where(user_id: user.id).order(id: :desc).first
      expect(m).to be_present
      expect(m.action).to eq('Enabled invitations')
    end
  end

  describe '#ban_by_user_for_reason!' do
    let(:banner) { create(:user) }

    it 'bans and deletes the user, notifies, and records moderation' do
      allow(FlaggedCommenters).to receive(:new).and_return(double(check_list_for: false))
      mail_double = double(deliver_now: true)
      allow(BanNotificationMailer).to receive(:notify).and_return(mail_double)

      user = create(:user, karma: -1)
      expect(user.ban_by_user_for_reason!(banner, 'ban reason')).to be true
      user.reload
      expect(user.is_banned?).to be true
      expect(user.deleted_at).to be_present
      expect(user.banned_by_user_id).to eq(banner.id)
      expect(user.banned_reason).to eq('ban reason')
      expect(BanNotificationMailer).to have_received(:notify).with(user, banner, 'ban reason')
      mod = Moderation.where(user_id: user.id).order(id: :desc).first
      expect(mod).to be_present
      expect(mod.action).to eq('Banned')
      expect(user.email).to eq("#{user.username}@lobsters.example")
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

  describe 'permissions helpers' do
    let(:old_enough_time) { (User::NEW_USER_DAYS + 1).days.ago }

    describe '#can_flag?' do
      it 'disallows new users from flagging' do
        user = create(:user, created_at: Time.current, karma: 100)
        comment = create(:comment)
        allow(comment).to receive(:is_flaggable?).and_return(true)
        expect(user.can_flag?(comment)).to be false
      end

      it 'allows flagging a flaggable story regardless of karma' do
        user = create(:user, created_at: old_enough_time, karma: 0)
        story = create(:story)
        allow(story).to receive(:is_flaggable?).and_return(true)
        expect(user.can_flag?(story)).to be true
      end

      it 'allows unvoting an already flagged story' do
        user = create(:user, created_at: old_enough_time, karma: 0)
        story = create(:story)
        allow(story).to receive(:is_flaggable?).and_return(false)
        allow(story).to receive(:current_flagged?).and_return(true)
        expect(user.can_flag?(story)).to be true
      end

      it 'requires karma threshold to flag a comment' do
        low = create(:user, created_at: old_enough_time, karma: User::MIN_KARMA_TO_FLAG - 1)
        ok = create(:user, created_at: old_enough_time, karma: User::MIN_KARMA_TO_FLAG)
        c = create(:comment)
        allow(c).to receive(:is_flaggable?).and_return(true)
        expect(low.can_flag?(c)).to be false
        expect(ok.can_flag?(c)).to be true
      end
    end

    describe '#can_invite?' do
      it 'is false when invites are disabled' do
        user = create(:user, disabled_invite_at: Time.current, karma: 100)
        expect(user.can_invite?).to be false
      end

      it 'depends on submission karma threshold' do
        too_low = create(:user, karma: User::MIN_KARMA_TO_SUBMIT_STORIES - 1)
        at_min = create(:user, karma: User::MIN_KARMA_TO_SUBMIT_STORIES)
        expect(too_low.can_invite?).to be false
        expect(at_min.can_invite?).to be true
      end
    end

    describe '#can_offer_suggestions?' do
      it 'requires not new and sufficient karma' do
        new_user = create(:user, created_at: Time.current, karma: 100)
        low = create(:user, created_at: old_enough_time, karma: User::MIN_KARMA_TO_SUGGEST - 1)
        ok = create(:user, created_at: old_enough_time, karma: User::MIN_KARMA_TO_SUGGEST)
        expect(new_user.can_offer_suggestions?).to be false
        expect(low.can_offer_suggestions?).to be false
        expect(ok.can_offer_suggestions?).to be true
      end
    end

    describe '#can_see_invitation_requests?' do
      it 'allows moderators who can invite' do
        mod = create(:user, is_moderator: true, karma: 100)
        expect(mod.can_see_invitation_requests?).to be true
      end

      it 'requires invite ability and karma threshold for non-mods' do
        low = create(:user, is_moderator: false, karma: User::MIN_KARMA_FOR_INVITATION_REQUESTS - 1)
        ok = create(:user, is_moderator: false, karma: User::MIN_KARMA_FOR_INVITATION_REQUESTS)
        expect(low.can_see_invitation_requests?).to be false
        expect(ok.can_see_invitation_requests?).to be true
      end
    end

    describe '#can_submit_stories?' do
      it 'respects minimum karma threshold' do
        low = create(:user, karma: User::MIN_KARMA_TO_SUBMIT_STORIES - 1)
        at_min = create(:user, karma: User::MIN_KARMA_TO_SUBMIT_STORIES)
        expect(low.can_submit_stories?).to be false
        expect(at_min.can_submit_stories?).to be true
      end
    end

    describe '#high_karma?' do
      it 'returns true for users at or above the threshold' do
        low = create(:user, karma: User::HIGH_KARMA_THRESHOLD - 1)
        high = create(:user, karma: User::HIGH_KARMA_THRESHOLD)
        expect(low.high_karma?).to be false
        expect(high.high_karma?).to be true
      end
    end
  end

  describe 'token generation callbacks' do
    it 'ensures a session_token is present before save' do
      user = build(:user, session_token: nil)
      expect(user.save!).to be true
      expect(user.session_token).to be_present
      expect(user.session_token.length).to be >= 10
    end

    it 'generates rss_token and mailing_list_token on create' do
      user = create(:user, rss_token: nil, mailing_list_token: nil)
      expect(user.rss_token).to be_present
      expect(user.rss_token.length).to be >= 20
      expect(user.mailing_list_token).to be_present
      expect(user.mailing_list_token.length).to be >= 8
    end
  end

  describe 'keystore-backed counters' do
    let(:user) { create(:user) }

    it 'reads comments_posted_count/comments_deleted_count from Keystore' do
      allow(Keystore).to receive(:value_for).with("user:#{user.id}:comments_posted").and_return('7')
      allow(Keystore).to receive(:value_for).with("user:#{user.id}:comments_deleted").and_return('2')
      expect(user.comments_posted_count).to eq(7)
      expect(user.comments_deleted_count).to eq(2)
    end

    it 'writes counts on refresh_counts!' do
      create(:story, user: user)
      create(:comment, user: user, is_deleted: false)
      create(:comment, user: user, is_deleted: true)
      create(:comment, user: user, is_deleted: true)
      expect(Keystore).to receive(:put).with("user:#{user.id}:stories_submitted", 1)
      expect(Keystore).to receive(:put).with("user:#{user.id}:comments_posted", 1)
      expect(Keystore).to receive(:put).with("user:#{user.id}:comments_deleted", 2)
      user.refresh_counts!
    end
  end

  describe '#fetched_avatar' do
    let(:user) { create(:user, email: 'user@example.com') }

    it 'returns bytes when fetch succeeds' do
      sponge = double
      allow(Sponge).to receive(:new).and_return(sponge)
      allow(sponge).to receive(:timeout=).with(3)
      allow(sponge).to receive(:fetch).and_return(double(body: 'avatarbytes'))
      expect(user.fetched_avatar(64)).to eq('avatarbytes')
    end

    it 'returns nil on fetch error' do
      sponge = double
      allow(Sponge).to receive(:new).and_return(sponge)
      allow(sponge).to receive(:timeout=).with(3)
      allow(sponge).to receive(:fetch).and_raise(StandardError.new('boom'))
      expect(user.fetched_avatar(64)).to be_nil
    end
  end

  describe '#delete! and #undelete!' do
    it 'soft-deletes and restores the user' do
      allow(FlaggedCommenters).to receive(:new).and_return(double(check_list_for: false))
      user = create(:user, karma: -1)
      old_session = user.session_token
      user.delete!
      user.reload
      expect(user.deleted_at).to be_present
      expect(user.session_token).to be_present
      expect(user.session_token).to_not eq(old_session)
      expect(user.email).to eq("#{user.username}@lobsters.example")
      user.undelete!
      user.reload
      expect(user.deleted_at).to be_nil
    end
  end

  describe '#disable_2fa!' do
    it 'clears totp_secret' do
      user = create(:user, totp_secret: 'SECRET')
      expect(user.has_2fa?).to be true
      user.disable_2fa!
      expect(user.has_2fa?).to be false
    end
  end

  describe '#grant_moderatorship_by_user!' do
    it 'grants moderator, creates moderation and hat' do
      granter = create(:user)
      user = create(:user, is_moderator: false)
      expect(user.grant_moderatorship_by_user!(granter)).to be true
      user.reload
      expect(user.is_moderator).to be true
      m = Moderation.where(user_id: user.id).order(id: :desc).first
      expect(m).to be_present
      expect(m.action).to eq('Granted moderator status')
      h = Hat.where(user_id: user.id).order(id: :desc).first
      expect(h).to be_present
      expect(h.hat).to eq('Sysop')
    end
  end

  describe '#initiate_password_reset_for_ip' do
    it 'sets a token and delivers mail' do
      user = create(:user)
      mailer = double(deliver_now: true)
      ip = '203.0.113.5'
      allow(PasswordResetMailer).to receive(:password_reset_link).with(user, ip).and_return(mailer)
      user.initiate_password_reset_for_ip(ip)
      expect(user.password_reset_token).to be_present
      expect(PasswordResetMailer).to have_received(:password_reset_link).with(user, ip)
    end
  end

  describe '#has_2fa?' do
    it 'reflects totp_secret presence' do
      user = build(:user, totp_secret: nil)
      expect(user.has_2fa?).to be false
      user.totp_secret = 'x'
      expect(user.has_2fa?).to be true
    end
  end

  describe '#is_wiped?' do
    it "returns true when password_digest is '*'" do
      user = build(:user, password_digest: '*')
      expect(user.is_wiped?).to be true
    end
  end

  describe '#linkified_about' do
    it 'renders about with Markdowner' do
      user = build(:user, about: 'hello')
      allow(Markdowner).to receive(:to_html).with('hello').and_return('<p>hello</p>')
      expect(user.linkified_about).to eq('<p>hello</p>')
    end
  end

  describe '#mastodon_acct' do
    it 'builds acct string when fields are present' do
      user = build(:user, mastodon_username: 'alice', mastodon_instance: 'example.social')
      expect(user.mastodon_acct).to eq('@alice@example.social')
    end

    it 'raises when fields are missing' do
      user = build(:user, mastodon_username: nil, mastodon_instance: nil)
      expect { user.mastodon_acct }.to raise_error(RuntimeError)
    end
  end

  describe '#pushover!' do
    it 'sends notification when key present' do
      user = build(:user, pushover_user_key: 'ABC123')
      expect(Pushover).to receive(:push).with('ABC123', hash_including(title: 't'))
      user.pushover!(title: 't', message: 'm')
    end

    it 'does nothing when key is blank' do
      user = build(:user, pushover_user_key: nil)
      expect(Pushover).to_not receive(:push)
      user.pushover!(title: 't')
    end
  end

  describe '#stories_submitted_count and #stories_deleted_count' do
    let(:user) { create(:user) }

    it 'reads counts from Keystore' do
      allow(Keystore).to receive(:value_for).with("user:#{user.id}:stories_submitted").and_return('5')
      allow(Keystore).to receive(:value_for).with("user:#{user.id}:stories_deleted").and_return('1')
      expect(user.stories_submitted_count).to eq(5)
      expect(user.stories_deleted_count).to eq(1)
    end
  end

  describe '#to_param' do
    it 'returns username' do
      user = build(:user, username: 'bob')
      expect(user.to_param).to eq('bob')
    end
  end

  describe '#inbox_count' do
    it 'counts unread notifications' do
      user = create(:user)
      create(:notification, user: user, read_at: nil)
      create(:notification, user: user, read_at: nil)
      create(:notification, user: user, read_at: Time.current)
      expect(user.inbox_count).to eq(2)
    end
  end

  describe '#votes_for_others' do
    let(:voter) { create(:user) }
    let(:other1) { create(:user) }
    let(:other2) { create(:user) }

    it "returns only votes on others' content" do
      s_other = create(:story, user: other1)
      s_own = create(:story, user: voter)
      c_other = create(:comment, user: other2, story: s_other)
      c_own = create(:comment, user: voter, story: s_own)

      v1 = create(:vote, user: voter, story: s_other, comment: nil, vote: 1)
      v2 = create(:vote, user: voter, story: s_own, comment: nil, vote: 1)
      v3 = create(:vote, user: voter, story: nil, comment: c_other, vote: 1)
      v4 = create(:vote, user: voter, story: nil, comment: c_own, vote: 1)

      result = voter.votes_for_others.to_a
      expect(result).to include(v1, v3)
      expect(result).to_not include(v2, v4)
      expect(result).to eq([v3, v1].sort_by(&:id).reverse)
    end
  end
end
