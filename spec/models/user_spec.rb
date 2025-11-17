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
end

describe User do
  describe '.username_regex_s' do
    it 'returns a regex string with anchors' do
      expect(User.username_regex_s).to be_a(String)
      expect(User.username_regex_s).to start_with('/^')
      expect(User.username_regex_s).to end_with('$/')
    end
  end

  describe '#as_json' do
    let(:inviter) { create(:user) }
    let(:user) do
      create(
        :user,
        about: 'hello',
        homepage: 'https://example.com',
        invited_by_user: inviter,
        github_username: 'octocat',
        mastodon_username: 'alice',
        mastodon_instance: 'fosstodon.org',
        created_at: 2.days.ago
      )
    end

    it 'includes expected attributes and computed fields' do
      allow(Markdowner).to receive(:to_html).with(user.about).and_return('<p>hello</p>')
      json = user.as_json
      expect(json[:username]).to eq(user.username)
      expect(json[:created_at]).to be_within(5).of(user.created_at)
      expect(json[:is_admin]).to eq(false)
      expect(json[:is_moderator]).to eq(false)
      expect(json[:karma]).to eq(user.karma)
      expect(json[:homepage]).to eq('https://example.com')
      expect(json[:about]).to eq('<p>hello</p>')
      expect(json[:avatar_url]).to end_with("/avatars/#{user.username}-100.png")
      expect(json[:invited_by_user]).to eq(inviter.username)
      expect(json[:github_username]).to eq('octocat')
      expect(json[:mastodon_username]).to eq('alice')
    end

    it 'omits karma when user is admin' do
      admin = create(:user, is_admin: true)
      allow(Markdowner).to receive(:to_html).and_return('<p></p>')
      json = admin.as_json
      expect(json.key?(:karma)).to be false
    end
  end

  describe '#authenticate_totp' do
    it 'verifies valid codes and rejects invalid ones' do
      secret = ROTP::Base32.random_base32
      user = create(:user, totp_secret: secret)
      totp = ROTP::TOTP.new(secret)
      valid_code = totp.now
      expect(user.authenticate_totp(valid_code)).to be_truthy
      expect(user.authenticate_totp('000000')).to be_falsey
    end
  end

  describe '#avatar_path and #avatar_url' do
    let(:user) { create(:user, username: 'avataruser') }

    it 'builds the correct path' do
      expect(user.avatar_path(120)).to end_with('/avatars/avataruser-120.png')
    end

    it 'builds the correct url' do
      expect(user.avatar_url(80)).to end_with('/avatars/avataruser-80.png')
    end
  end

  describe '#disable_invite_by_user_for_reason!' do
    let(:mod) { create(:user) }
    let(:user) { create(:user) }

    it 'disables invites, notifies user, and logs moderation' do
      expect do
        expect(user.disable_invite_by_user_for_reason!(mod, 'spamming invites')).to be true
      end.to change(Message, :count).by(1).and change(Moderation, :count).by(1)

      user.reload
      expect(user.disabled_invite_at).to be_present
      expect(user.disabled_invite_by_user_id).to eq(mod.id)
      expect(user.disabled_invite_reason).to eq('spamming invites')
      msg = Message.order(:id).last
      expect(msg.subject).to eq('Your invite privileges have been revoked')
      modlog = Moderation.order(:id).last
      expect(modlog.action).to eq('Disabled invitations')
      expect(modlog.reason).to eq('spamming invites')
    end
  end

  describe '#ban_by_user_for_reason!' do
    let(:mod) { create(:user) }
    let(:user) { create(:user) }

    it 'bans, deletes, sends mail, and logs moderation' do
      mailer = double(deliver_now: true)
      allow(BanNotificationMailer).to receive(:notify).and_return(mailer)

      expect do
        expect(user.ban_by_user_for_reason!(mod, 'rule violations')).to be true
      end.to change(Moderation, :count).by(1)

      expect(BanNotificationMailer).to have_received(:notify).with(user, mod, 'rule violations')
      user.reload
      expect(user.is_banned?).to be true
      expect(user.deleted_at).to be_present
      modlog = Moderation.order(:id).last
      expect(modlog.action).to eq('Banned')
      expect(modlog.reason).to eq('rule violations')
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
    let(:old_user) { create(:user, created_at: (User::NEW_USER_DAYS + 1).days.ago) }

    describe '#can_flag?' do
      it 'allows flagging of flaggable stories' do
        story = create(:story)
        allow(story).to receive(:is_flaggable?).and_return(true)
        expect(old_user.can_flag?(story)).to be true
      end

      it 'allows unvoting currently flagged stories' do
        story = create(:story)
        allow(story).to receive(:is_flaggable?).and_return(false)
        allow(story).to receive(:current_flagged?).and_return(true)
        expect(old_user.can_flag?(story)).to be true
      end

      it 'disallows flagging when not permitted' do
        story = create(:story)
        allow(story).to receive(:is_flaggable?).and_return(false)
        allow(story).to receive(:current_flagged?).and_return(false)
        expect(old_user.can_flag?(story)).to be false
      end

      it 'requires sufficient karma to flag comments' do
        low = create(:user, karma: User::MIN_KARMA_TO_FLAG - 1, created_at: (User::NEW_USER_DAYS + 1).days.ago)
        high = create(:user, karma: User::MIN_KARMA_TO_FLAG, created_at: (User::NEW_USER_DAYS + 1).days.ago)
        comment = create(:comment)
        allow(comment).to receive(:is_flaggable?).and_return(true)
        expect(low.can_flag?(comment)).to be false
        expect(high.can_flag?(comment)).to be true
      end

      it 'disallows new users from flagging anything' do
        newbie = create(:user, created_at: Time.current)
        story = create(:story)
        allow(story).to receive(:is_flaggable?).and_return(true)
        expect(newbie.can_flag?(story)).to be false
      end
    end

    describe '#can_invite?' do
      it 'requires not being banned from inviting and ability to submit stories' do
        user = create(:user, karma: User::MIN_KARMA_TO_SUBMIT_STORIES, disabled_invite_at: nil)
        expect(user.can_invite?).to be true
        user.update!(disabled_invite_at: Time.current)
        expect(user.can_invite?).to be false
      end
    end

    describe '#can_offer_suggestions?' do
      it 'is true for old users with enough karma' do
        user = create(:user, karma: User::MIN_KARMA_TO_SUGGEST, created_at: (User::NEW_USER_DAYS + 1).days.ago)
        expect(user.can_offer_suggestions?).to be true
      end

      it 'is false for new users or low karma' do
        new_user = create(:user, karma: 100, created_at: Time.current)
        low_karma = create(:user, karma: User::MIN_KARMA_TO_SUGGEST - 1, created_at: (User::NEW_USER_DAYS + 1).days.ago)
        expect(new_user.can_offer_suggestions?).to be false
        expect(low_karma.can_offer_suggestions?).to be false
      end
    end

    describe '#can_see_invitation_requests?' do
      it 'allows moderators even below karma threshold if they can invite' do
        user = create(:user, is_moderator: true, karma: User::MIN_KARMA_TO_SUBMIT_STORIES, disabled_invite_at: nil,
                             created_at: (User::NEW_USER_DAYS + 1).days.ago)
        expect(user.can_see_invitation_requests?).to be true
      end

      it 'allows non-mods with sufficient karma if they can invite' do
        user = create(:user, karma: User::MIN_KARMA_FOR_INVITATION_REQUESTS, disabled_invite_at: nil,
                             created_at: (User::NEW_USER_DAYS + 1).days.ago)
        expect(user.can_see_invitation_requests?).to be true
      end

      it 'disallows users who cannot invite' do
        user = create(:user, karma: User::MIN_KARMA_FOR_INVITATION_REQUESTS, disabled_invite_at: Time.current,
                             created_at: (User::NEW_USER_DAYS + 1).days.ago)
        expect(user.can_see_invitation_requests?).to be false
      end
    end
  end

  describe '#can_submit_stories?' do
    it 'respects minimum karma threshold' do
      ok = create(:user, karma: User::MIN_KARMA_TO_SUBMIT_STORIES)
      bad = create(:user, karma: User::MIN_KARMA_TO_SUBMIT_STORIES - 1)
      expect(ok.can_submit_stories?).to be true
      expect(bad.can_submit_stories?).to be false
    end
  end

  describe '#high_karma?' do
    it 'detects high karma users' do
      low = create(:user, karma: User::HIGH_KARMA_THRESHOLD - 1)
      high = create(:user, karma: User::HIGH_KARMA_THRESHOLD)
      expect(low.high_karma?).to be false
      expect(high.high_karma?).to be true
    end
  end

  describe 'token generation callbacks' do
    it 'ensures session_token, rss_token, and mailing_list_token are present on create' do
      user = build(:user, session_token: nil, rss_token: nil, mailing_list_token: nil)
      user.save!
      expect(user.session_token).to be_present
      expect(user.rss_token).to be_present
      expect(user.mailing_list_token).to be_present
    end
  end

  describe 'keystore-backed counters' do
    let(:user) { create(:user) }

    it 'returns posted and deleted comment counts' do
      allow(Keystore).to receive(:value_for).with("user:#{user.id}:comments_posted").and_return('7')
      allow(Keystore).to receive(:value_for).with("user:#{user.id}:comments_deleted").and_return('2')
      expect(user.comments_posted_count).to eq(7)
      expect(user.comments_deleted_count).to eq(2)
    end

    it 'refreshes counts using keystore' do
      allow(Keystore).to receive(:put)
      allow(user).to receive_message_chain(:stories, :count).and_return(5)
      allow(user).to receive_message_chain(:comments, :active, :count).and_return(3)
      allow(user).to receive_message_chain(:comments, :deleted, :count).and_return(1)
      user.refresh_counts!
      expect(Keystore).to have_received(:put).with("user:#{user.id}:stories_submitted", 5)
      expect(Keystore).to have_received(:put).with("user:#{user.id}:comments_posted", 3)
      expect(Keystore).to have_received(:put).with("user:#{user.id}:comments_deleted", 1)
    end
  end

  describe '#fetched_avatar' do
    let(:user) { create(:user, email: 'fetch@example.com') }

    it 'returns body when fetch succeeds' do
      sponge = double
      response = double(body: 'imgdata')
      allow(Sponge).to receive(:new).and_return(sponge)
      allow(sponge).to receive(:timeout=).with(3)
      allow(sponge).to receive(:fetch).and_return(response)
      expect(user.fetched_avatar(80)).to eq('imgdata')
    end

    it 'returns nil on fetch error' do
      sponge = double
      allow(Sponge).to receive(:new).and_return(sponge)
      allow(sponge).to receive(:timeout=).with(3)
      allow(sponge).to receive(:fetch).and_raise(StandardError.new('boom'))
      expect(user.fetched_avatar(80)).to be_nil
    end
  end

  describe '#delete! and #undelete!' do
    it 'soft deletes the user and rotates session token' do
      user = create(:user)
      old_token = user.session_token
      user.delete!
      expect(user.deleted_at).to be_present
      expect(user.session_token).to be_present
      expect(user.session_token).to_not eq(old_token)
    end

    it 'restores a deleted user' do
      user = create(:user)
      user.delete!
      user.undelete!
      expect(user.deleted_at).to be_nil
    end
  end

  describe '#disable_2fa! and #has_2fa?' do
    it 'disables 2FA and reports status correctly' do
      user = create(:user, totp_secret: 'secret')
      expect(user.has_2fa?).to be true
      user.disable_2fa!
      expect(user.has_2fa?).to be false
    end
  end

  describe '#good_riddance?' do
    it 'masks email for problematic users' do
      user = create(:user, karma: -1, email: 'user@example.com')
      user.good_riddance?
      expect(user.email).to eq("#{user.username}@lobsters.example")
    end
  end

  describe '#grant_moderatorship_by_user!' do
    it 'marks user as moderator, logs mod action, and grants Sysop hat' do
      granter = create(:user)
      user = create(:user, is_moderator: false)
      expect do
        expect(user.grant_moderatorship_by_user!(granter)).to be true
      end.to change(Moderation, :count).by(1).and change(Hat, :count).by(1)
      user.reload
      expect(user.is_moderator).to be true
      hat = Hat.order(:id).last
      expect(hat.user_id).to eq(user.id)
      expect(hat.hat).to eq('Sysop')
      modlog = Moderation.order(:id).last
      expect(modlog.action).to eq('Granted moderator status')
    end
  end

  describe '#initiate_password_reset_for_ip' do
    it 'sets a reset token and sends mail' do
      user = create(:user)
      mailer = double(deliver_now: true)
      allow(PasswordResetMailer).to receive(:password_reset_link).and_return(mailer)
      user.initiate_password_reset_for_ip('127.0.0.1')
      expect(user.password_reset_token).to match(/^\d+-[A-Za-z0-9]{30}$/)
      expect(PasswordResetMailer).to have_received(:password_reset_link).with(user, '127.0.0.1')
    end
  end

  describe '#is_active?' do
    it 'is false when deleted' do
      user = create(:user, deleted_at: Time.current)
      expect(user.is_active?).to be false
    end
  end

  describe '#is_wiped?' do
    it 'detects wiped accounts' do
      user = create(:user)
      user.update_column(:password_digest, '*')
      expect(user.is_wiped?).to be true
    end
  end

  describe '#roll_session_token' do
    it 'changes the session token' do
      user = create(:user)
      old = user.session_token
      user.roll_session_token
      expect(user.session_token).to be_present
      expect(user.session_token).to_not eq(old)
    end
  end

  describe '#linkified_about' do
    it 'delegates to Markdowner' do
      user = create(:user, about: 'hello')
      allow(Markdowner).to receive(:to_html).with('hello').and_return('<p>hello</p>')
      expect(user.linkified_about).to eq('<p>hello</p>')
    end
  end

  describe '#mastodon_acct' do
    it 'builds acct when both fields present' do
      user = create(:user, mastodon_username: 'bob', mastodon_instance: 'mastodon.social')
      expect(user.mastodon_acct).to eq('@bob@mastodon.social')
    end

    it 'raises when fields are missing' do
      user = create(:user, mastodon_username: nil, mastodon_instance: nil)
      expect { user.mastodon_acct }.to raise_error(RuntimeError)
    end
  end

  describe '#pushover!' do
    it 'sends when a user key is present' do
      user = create(:user, pushover_user_key: 'uKey')
      allow(Pushover).to receive(:push)
      user.pushover!(title: 'hi')
      expect(Pushover).to have_received(:push).with('uKey', title: 'hi')
    end

    it 'does nothing without a user key' do
      user = create(:user, pushover_user_key: nil)
      allow(Pushover).to receive(:push)
      user.pushover!(message: 'nope')
      expect(Pushover).to_not have_received(:push)
    end
  end

  describe 'keystore-backed story counters' do
    let(:user) { create(:user) }

    it 'reads stories_submitted_count and stories_deleted_count' do
      allow(Keystore).to receive(:value_for).with("user:#{user.id}:stories_submitted").and_return('12')
      allow(Keystore).to receive(:value_for).with("user:#{user.id}:stories_deleted").and_return('3')
      expect(user.stories_submitted_count).to eq(12)
      expect(user.stories_deleted_count).to eq(3)
    end
  end

  describe '#to_param' do
    it 'uses the username' do
      user = create(:user, username: 'paramuser')
      expect(user.to_param).to eq('paramuser')
    end
  end

  describe '#enable_invite_by_user!' do
    it 're-enables invites and logs moderation' do
      mod = create(:user)
      user = create(:user, disabled_invite_at: Time.current, disabled_invite_by_user: mod,
                           disabled_invite_reason: 'reason')
      expect do
        expect(user.enable_invite_by_user!(mod)).to be true
      end.to change(Moderation, :count).by(1)
      user.reload
      expect(user.disabled_invite_at).to be_nil
      expect(user.disabled_invite_by_user_id).to be_nil
      expect(user.disabled_invite_reason).to be_nil
      modlog = Moderation.order(:id).last
      expect(modlog.action).to eq('Enabled invitations')
    end
  end

  describe '#inbox_count' do
    it 'counts unread notifications' do
      user = create(:user)
      create(:notification, user: user, read_at: nil)
      create(:notification, user: user, read_at: Time.current)
      create(:notification, user: user, read_at: nil)
      expect(user.inbox_count).to eq(2)
    end
  end

  describe '.active scope' do
    it 'includes only active users' do
      active = create(:user)
      banned = create(:user, :banned)
      deleted = create(:user, deleted_at: Time.current)
      expect(User.active).to include(active)
      expect(User.active).to_not include(banned)
      expect(User.active).to_not include(deleted)
    end
  end
end
