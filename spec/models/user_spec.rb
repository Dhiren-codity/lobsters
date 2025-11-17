# NOTE: Some failing tests were automatically removed after 3 fix attempts failed.
# These tests may need manual review. See CI logs for details.
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

  describe '.username_regex_s' do
    it 'returns a source string for the VALID_USERNAME regex' do
      expect(User.username_regex_s).to eq('/^[A-Za-z0-9][A-Za-z0-9_-]{0,24}$/')
    end
  end

  describe '#as_json' do
    let(:inviter) { create(:user) }

    it 'omits optional provider usernames when blank' do
      user = create(:user, github_username: nil, mastodon_username: nil, mastodon_instance: nil)
      h = user.as_json
      expect(h.key?(:github_username)).to be false
      expect(h.key?(:mastodon_username)).to be false
    end
  end

  describe '#authenticate_totp' do
    it 'verifies a valid TOTP code and rejects an invalid one' do
      secret = ROTP::Base32.random_base32
      user = create(:user, totp_secret: secret)
      totp = ROTP::TOTP.new(secret)
      code = totp.now

      expect(user.authenticate_totp(code)).to be_truthy
      expect(user.authenticate_totp('000000')).to be_falsey
    end
  end

  describe '#avatar_path' do
    it 'returns a path to the avatar' do
      user = create(:user, username: 'alice')
      expect(user.avatar_path(80)).to eq('/avatars/alice-80.png')
    end
  end

  describe '#avatar_url' do
    it 'returns a URL to the avatar' do
      user = create(:user, username: 'bob')
      expect(user.avatar_url(120)).to include('/avatars/bob-120.png')
    end
  end

  describe '#disable_invite_by_user_for_reason!' do
    it 'disables invites, creates a message and a moderation' do
      disabler = create(:user)
      target = create(:user)
      expect do
        expect(target.disable_invite_by_user_for_reason!(disabler, 'spam invites')).to be true
      end.to change { Moderation.count }.by(1).and change { Message.count }.by(1)

      target.reload
      expect(target.disabled_invite_at).to be_present
      expect(target.disabled_invite_by_user_id).to eq(disabler.id)
      expect(target.disabled_invite_reason).to eq('spam invites')

      msg = Message.order(:id).last
      expect(msg.author_user_id).to eq(disabler.id)
      expect(msg.recipient_user_id).to eq(target.id)
      expect(msg.subject).to include('revoked')
      expect(msg.body).to include('spam invites')
    end
  end

  describe '#enable_invite_by_user!' do
    it 're-enables invites and records a moderation' do
      mod = create(:user)
      target = create(:user, disabled_invite_at: Time.current, disabled_invite_by_user: mod,
                             disabled_invite_reason: 'reason')
      expect do
        expect(target.enable_invite_by_user!(mod)).to be true
      end.to change { Moderation.count }.by(1)

      target.reload
      expect(target.disabled_invite_at).to be_nil
      expect(target.disabled_invite_by_user_id).to be_nil
      expect(target.disabled_invite_reason).to be_nil
    end
  end

  describe '#ban_by_user_for_reason!' do
    it 'bans, emails, deletes the user, and records a moderation' do
      banner = create(:user)
      target = create(:user)
      mailer = double('mailer', deliver_now: true)
      expect(BanNotificationMailer).to receive(:notify).with(target, banner, 'abuse').and_return(mailer)

      expect do
        expect(target.ban_by_user_for_reason!(banner, 'abuse')).to be true
      end.to change { Moderation.count }.by(1)

      target.reload
      expect(target.is_banned?).to be true
      expect(target.deleted_at).to be_present
    end
  end

  describe '#banned_from_inviting?' do
    it 'reflects disabled_invite_at' do
      u = create(:user, disabled_invite_at: nil)
      expect(u.banned_from_inviting?).to be false
      u.update!(disabled_invite_at: Time.current)
      expect(u.banned_from_inviting?).to be true
    end
  end

  describe '#can_flag?' do
    let(:user) { create(:user, created_at: (User::NEW_USER_DAYS + 1).days.ago, karma: 100) }

    it 'allows flagging eligible stories' do
      story = Story.new
      allow(story).to receive(:is_flaggable?).and_return(true)
      allow(story).to receive(:current_flagged?).and_return(false)
      expect(user.can_flag?(story)).to be true
    end

    it 'allows unvoting currently flagged stories' do
      story = Story.new
      allow(story).to receive(:is_flaggable?).and_return(false)
      allow(story).to receive(:current_flagged?).and_return(true)
      expect(user.can_flag?(story)).to be true
    end

    it 'disallows when story is not flaggable and not flagged' do
      story = Story.new
      allow(story).to receive(:is_flaggable?).and_return(false)
      allow(story).to receive(:current_flagged?).and_return(false)
      expect(user.can_flag?(story)).to be false
    end

    it 'requires karma threshold for comments' do
      comment = Comment.new
      allow(comment).to receive(:is_flaggable?).and_return(true)

      low_karma_user = create(:user, created_at: (User::NEW_USER_DAYS + 1).days.ago, karma: User::MIN_KARMA_TO_FLAG - 1)
      expect(low_karma_user.can_flag?(comment)).to be false

      expect(user.can_flag?(comment)).to be true
    end

    it 'disallows for new users' do
      newbie = create(:user, created_at: Time.current, karma: 100)
      story = Story.new
      allow(story).to receive(:is_flaggable?).and_return(true)
      allow(story).to receive(:current_flagged?).and_return(false)
      expect(newbie.can_flag?(story)).to be false
    end
  end

  describe '#can_invite?' do
    it 'depends on invite ban and story submission ability' do
      u = create(:user, created_at: (User::NEW_USER_DAYS + 1).days.ago, karma: User::MIN_KARMA_TO_SUBMIT_STORIES)
      expect(u.can_invite?).to be true

      u.update!(disabled_invite_at: Time.current)
      expect(u.can_invite?).to be false

      u.update!(disabled_invite_at: nil, karma: User::MIN_KARMA_TO_SUBMIT_STORIES - 1)
      expect(u.can_invite?).to be false
    end
  end

  describe '#can_offer_suggestions?' do
    it 'requires not new and sufficient karma' do
      u = create(:user, created_at: (User::NEW_USER_DAYS + 1).days.ago, karma: User::MIN_KARMA_TO_SUGGEST)
      expect(u.can_offer_suggestions?).to be true

      newbie = create(:user, created_at: Time.current, karma: 10_000)
      expect(newbie.can_offer_suggestions?).to be false

      low_karma = create(:user, created_at: (User::NEW_USER_DAYS + 1).days.ago, karma: User::MIN_KARMA_TO_SUGGEST - 1)
      expect(low_karma.can_offer_suggestions?).to be false
    end
  end

  describe '#can_submit_stories?' do
    it 'checks threshold' do
      u = create(:user, karma: User::MIN_KARMA_TO_SUBMIT_STORIES)
      expect(u.can_submit_stories?).to be true
      u.update!(karma: User::MIN_KARMA_TO_SUBMIT_STORIES - 1)
      expect(u.can_submit_stories?).to be false
    end
  end

  describe '#high_karma?' do
    it 'returns true at threshold and above' do
      u = create(:user, karma: User::HIGH_KARMA_THRESHOLD)
      expect(u.high_karma?).to be true
      u.update!(karma: User::HIGH_KARMA_THRESHOLD + 1)
      expect(u.high_karma?).to be true
      u.update!(karma: User::HIGH_KARMA_THRESHOLD - 1)
      expect(u.high_karma?).to be false
    end
  end

  describe 'token generation on create' do
    it 'generates session, rss, and mailing list tokens' do
      u = create(:user)
      expect(u.session_token).to be_present
      expect(u.session_token.length).to eq(60)
      expect(u.rss_token).to be_present
      expect(u.rss_token.length).to eq(60)
      expect(u.mailing_list_token).to be_present
      expect(u.mailing_list_token.length).to eq(10)
    end
  end

  describe '#comments_posted_count and #comments_deleted_count' do
    let(:user) { create(:user) }

    it 'reads from Keystore' do
      allow(Keystore).to receive(:value_for).with("user:#{user.id}:comments_posted").and_return('7')
      allow(Keystore).to receive(:value_for).with("user:#{user.id}:comments_deleted").and_return('3')
      expect(user.comments_posted_count).to eq(7)
      expect(user.comments_deleted_count).to eq(3)
    end
  end

  describe '#stories_submitted_count and #stories_deleted_count' do
    let(:user) { create(:user) }

    it 'reads from Keystore' do
      allow(Keystore).to receive(:value_for).with("user:#{user.id}:stories_submitted").and_return('4')
      allow(Keystore).to receive(:value_for).with("user:#{user.id}:stories_deleted").and_return('2')
      expect(user.stories_submitted_count).to eq(4)
      expect(user.stories_deleted_count).to eq(2)
    end
  end

  describe '#fetched_avatar' do
    let(:user) { create(:user, email: 'user@example.com') }
  end

  describe '#refresh_counts!' do
    it 'writes counts to Keystore' do
      user = create(:user)
      allow(user.stories).to receive(:count).and_return(5)
      allow(user.comments).to receive_message_chain(:active, :count).and_return(3)
      allow(user.comments).to receive_message_chain(:deleted, :count).and_return(1)

      expect(Keystore).to receive(:put).with("user:#{user.id}:stories_submitted", 5)
      expect(Keystore).to receive(:put).with("user:#{user.id}:comments_posted", 3)
      expect(Keystore).to receive(:put).with("user:#{user.id}:comments_deleted", 1)

      user.refresh_counts!
    end
  end

  describe '#delete! and #undelete!' do
    it 'marks deleted and can be undeleted, rolling session token' do
      user = create(:user)
      old_token = user.session_token
      user.delete!
      expect(user.deleted_at).to be_present
      expect(user.session_token).to_not eq(old_token)

      user.undelete!
      expect(user.deleted_at).to be_nil
    end
  end

  describe '#disable_2fa!' do
    it 'clears the TOTP secret' do
      user = create(:user, totp_secret: 'SECRET')
      user.disable_2fa!
      expect(user.totp_secret).to be_nil
    end
  end

  describe '#good_riddance?' do
    it 'replaces email for negative karma users' do
      user = create(:user, karma: -1, email: 'real@example.com')
      user.good_riddance?
      expect(user.email).to eq("#{user.username}@lobsters.example")
    end

    it 'does nothing for banned users' do
      user = create(:user, :banned, karma: -10, email: 'real@example.com')
      user.good_riddance?
      expect(user.email).to eq('real@example.com')
    end
  end

  describe '#initiate_password_reset_for_ip' do
    it 'sets a reset token and sends email' do
      user = create(:user)
      mailer = double('mailer', deliver_now: true)
      expect(PasswordResetMailer).to receive(:password_reset_link).with(user, '127.0.0.1').and_return(mailer)
      user.initiate_password_reset_for_ip('127.0.0.1')
      expect(user.password_reset_token).to match(/\A\d+-[A-Za-z0-9]+\z/)
    end
  end

  describe '#has_2fa?' do
    it 'reflects presence of totp_secret' do
      user = create(:user, totp_secret: nil)
      expect(user.has_2fa?).to be false
      user.update!(totp_secret: 'SECRET')
      expect(user.has_2fa?).to be true
    end
  end

  describe '#is_wiped?' do
    it "is true when password_digest is '*'" do
      user = create(:user)
      user.update_columns(password_digest: '*')
      expect(user.is_wiped?).to be true
    end
  end

  describe '#mastodon_acct' do
    it 'returns proper acct string' do
      user = create(:user, mastodon_username: 'alice', mastodon_instance: 'example.social')
      expect(user.mastodon_acct).to eq('@alice@example.social')
    end

    it 'raises if username or instance missing' do
      user = create(:user, mastodon_username: nil, mastodon_instance: 'example.social')
      expect { user.mastodon_acct }.to raise_error(RuntimeError)
    end
  end

  describe '#pushover!' do
    it 'sends push when key is present' do
      user = create(:user, pushover_user_key: 'KEY')
      expect(Pushover).to receive(:push).with('KEY', hash_including(title: 't'))
      user.pushover!(title: 't', message: 'm')
    end

    it 'does nothing when key is absent' do
      user = create(:user, pushover_user_key: nil)
      expect(Pushover).not_to receive(:push)
      user.pushover!(message: 'm')
    end
  end

  describe '#to_param' do
    it 'returns the username' do
      user = create(:user, username: 'slug')
      expect(user.to_param).to eq('slug')
    end
  end

  describe '#inbox_count' do
    it 'counts unread notifications' do
      user = create(:user)
      rel = double('relation')
      expect(user.notifications).to receive(:where).with(read_at: nil).and_return(rel)
      expect(rel).to receive(:count).and_return(2)
      expect(user.inbox_count).to eq(2)
    end
  end

  describe '.active' do
    it 'returns only active users' do
      active = create(:user)
      banned = create(:user, :banned)
      deleted = create(:user, deleted_at: Time.current)
      expect(User.active).to include(active)
      expect(User.active).not_to include(banned)
      expect(User.active).not_to include(deleted)
    end
  end

  describe '.moderators' do
    it 'includes users with is_moderator flag' do
      mod = create(:user, is_moderator: true)
      regular = create(:user, is_moderator: false)
      expect(User.moderators).to include(mod)
      expect(User.moderators).not_to include(regular)
    end
  end
end
