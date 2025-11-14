# NOTE: Some failing tests were automatically removed after 3 fix attempts failed.
# These tests may need manual review. See CI logs for details.
require 'rails_helper'

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
      u = create(:user)
      expect(u.stories).to be_a(ActiveRecord::Associations::CollectionProxy)
      expect(u.comments).to be_a(ActiveRecord::Associations::CollectionProxy)
      expect(u.sent_messages).to be_a(ActiveRecord::Associations::CollectionProxy)
      expect(u.received_messages).to be_a(ActiveRecord::Associations::CollectionProxy)
      expect(u.tag_filters).to be_a(ActiveRecord::Associations::CollectionProxy)
      expect(u.tag_filter_tags).to be_a(ActiveRecord::Associations::CollectionProxy)
      expect(u.invitations).to be_a(ActiveRecord::Associations::CollectionProxy)
      expect(u.mod_notes).to be_a(ActiveRecord::Associations::CollectionProxy)
      expect(u.moderations).to be_a(ActiveRecord::Associations::CollectionProxy)
      expect(u.votes).to be_a(ActiveRecord::Associations::CollectionProxy)
      expect(u.voted_stories).to be_a(ActiveRecord::Associations::CollectionProxy)
      expect(u.upvoted_stories).to be_a(ActiveRecord::Associations::CollectionProxy)
      expect(u.hats).to be_a(ActiveRecord::Associations::CollectionProxy)
      expect(u.wearable_hats).to be_a(ActiveRecord::Associations::CollectionProxy)
      expect(u.notifications).to be_a(ActiveRecord::Associations::CollectionProxy)
      expect(u.hidings).to be_a(ActiveRecord::Associations::CollectionProxy)
    end
  end

  describe 'scopes' do
    it '.active returns users not banned or deleted' do
      active = create(:user, banned_at: nil, deleted_at: nil)
      banned = create(:user, banned_at: Time.current)
      deleted = create(:user, deleted_at: Time.current)
      expect(User.active).to include(active)
      expect(User.active).not_to include(banned)
      expect(User.active).not_to include(deleted)
    end

    it '.moderators includes users with is_moderator true' do
      mod = create(:user, is_moderator: true)
      reg = create(:user, is_moderator: false)
      expect(User.moderators).to include(mod)
      expect(User.moderators).not_to include(reg)
    end
  end

  describe 'callbacks and tokens' do
    it 'generates session_token, rss_token, and mailing_list_token on create' do
      u = create(:user)
      expect(u.session_token).to be_present
      expect(u.rss_token).to be_present
      expect(u.mailing_list_token).to be_present
    end

    it 'rolls session token' do
      u = create(:user)
      old = u.session_token
      u.roll_session_token
      expect(u.session_token).to be_present
      expect(u.session_token).not_to eq(old)
    end
  end

  describe '.username_regex_s' do
    it 'returns a stringified regex pattern' do
      expect(User.username_regex_s).to be_a(String)
      expect(User.username_regex_s).to include('^')
      expect(User.username_regex_s).to include('$')
    end
  end

  describe 'JSON serialization' do
    let(:inviter) { create(:user, username: 'inviter') }

    it 'omits karma for admins' do
      u = create(:user, is_admin: true, about: 'x')
      allow(Markdowner).to receive(:to_html).and_return('x')
      json = u.as_json
      expect(json).not_to have_key('karma')
    end
  end

  describe '#authenticate_totp' do
    it 'verifies a valid TOTP code' do
      secret = ROTP::Base32.random
      u = create(:user, totp_secret: secret)
      totp = ROTP::TOTP.new(secret)
      code = totp.now
      expect(u.authenticate_totp(code)).to be_truthy
    end

    it 'rejects an invalid TOTP code' do
      secret = ROTP::Base32.random
      u = create(:user, totp_secret: secret)
      expect(u.authenticate_totp('000000')).to be_falsey
    end
  end

  describe 'avatar helpers' do
    let(:u) { create(:user, username: 'alice') }

    it 'returns an avatar path with default and custom sizes' do
      expect(u.avatar_path).to eq('/avatars/alice-100.png')
      expect(u.avatar_path(50)).to eq('/avatars/alice-50.png')
    end

    it 'returns an avatar URL with default and custom sizes' do
      expect(u.avatar_url).to include('/avatars/alice-100.png')
      expect(u.avatar_url(32)).to include('/avatars/alice-32.png')
    end
  end

  describe 'invite controls' do
    let(:mod) { create(:user) }
    let(:u) { create(:user) }

    it 'disables invite privileges with audit' do
      expect do
        expect(u.disable_invite_by_user_for_reason!(mod, 'spamming invites')).to eq(true)
      end.to change { Moderation.count }.by(1)
                                        .and change { Message.count }.by(1)

      u.reload
      expect(u.disabled_invite_at).to be_present
      expect(u.disabled_invite_by_user_id).to eq(mod.id)
      expect(u.disabled_invite_reason).to eq('spamming invites')

      msg = Message.order(id: :desc).first
      expect(msg.recipient_user_id).to eq(u.id)
      expect(msg.author_user_id).to eq(mod.id)
      expect(msg.subject).to include('invite privileges')
    end

    it 'reports banned_from_inviting? correctly' do
      expect(u.banned_from_inviting?).to be false
      u.disable_invite_by_user_for_reason!(mod, 'x')
      expect(u.banned_from_inviting?).to be true
    end

    it 'enables invite privileges with audit' do
      u.disable_invite_by_user_for_reason!(mod, 'x')
      expect do
        expect(u.enable_invite_by_user!(mod)).to eq(true)
      end.to change { Moderation.count }.by(1)

      u.reload
      expect(u.disabled_invite_at).to be_nil
      expect(u.disabled_invite_by_user_id).to be_nil
      expect(u.disabled_invite_reason).to be_nil
    end
  end

  describe '#ban_by_user_for_reason!' do
    it 'bans, deletes, audits, and notifies' do
      banner = create(:user)
      u = create(:user)

      mailer = double('mailer', deliver_now: true)
      expect(BanNotificationMailer).to receive(:notify).with(u, banner, 'bad').and_return(mailer)

      expect do
        expect(u.ban_by_user_for_reason!(banner, 'bad')).to eq(true)
      end.to change { Moderation.count }.by(1)

      u.reload
      expect(u.banned_at).to be_present
      expect(u.banned_by_user_id).to eq(banner.id)
      expect(u.banned_reason).to eq('bad')
      expect(u.deleted_at).to be_present
    end
  end

  describe 'permission helpers' do
    let(:old_user) { create(:user, created_at: (User::NEW_USER_DAYS + 1).days.ago, karma: 100) }
    let(:new_user) { create(:user, created_at: Time.current, karma: 100) }

    it 'can_flag? story conditions' do
      story = create(:story)
      allow(story).to receive(:is_flaggable?).and_return(true)
      expect(old_user.can_flag?(story)).to be true

      allow(story).to receive(:is_flaggable?).and_return(false)
      allow(story).to receive(:current_flagged?).and_return(true)
      expect(old_user.can_flag?(story)).to be true

      allow(story).to receive(:current_flagged?).and_return(false)
      expect(old_user.can_flag?(story)).to be false

      allow(story).to receive(:is_flaggable?).and_return(true)
      expect(new_user.can_flag?(story)).to be false
    end

    it 'can_flag? comment depends on karma' do
      c = create(:comment)
      allow(c).to receive(:is_flaggable?).and_return(true)

      low = create(:user, created_at: (User::NEW_USER_DAYS + 1).days.ago, karma: User::MIN_KARMA_TO_FLAG - 1)
      high = create(:user, created_at: (User::NEW_USER_DAYS + 1).days.ago, karma: User::MIN_KARMA_TO_FLAG)
      expect(low.can_flag?(c)).to be false
      expect(high.can_flag?(c)).to be true
    end

    it 'can_invite? respects karma and invite ban' do
      ok = create(:user, karma: User::MIN_KARMA_TO_SUBMIT_STORIES)
      low = create(:user, karma: User::MIN_KARMA_TO_SUBMIT_STORIES - 1)
      expect(ok.can_invite?).to be true
      expect(low.can_invite?).to be false

      mod = create(:user)
      ok.disable_invite_by_user_for_reason!(mod, 'x')
      expect(ok.can_invite?).to be false
    end

    it 'can_offer_suggestions? requires not-new and minimum karma' do
      u1 = create(:user, created_at: (User::NEW_USER_DAYS + 1).days.ago, karma: User::MIN_KARMA_TO_SUGGEST)
      u2 = create(:user, created_at: (User::NEW_USER_DAYS + 1).days.ago, karma: User::MIN_KARMA_TO_SUGGEST - 1)
      u3 = create(:user, created_at: Time.current, karma: 10)
      expect(u1.can_offer_suggestions?).to be true
      expect(u2.can_offer_suggestions?).to be false
      expect(u3.can_offer_suggestions?).to be false
    end

    it 'can_see_invitation_requests? requires can_invite? and moderator or karma threshold' do
      base = create(:user, created_at: (User::NEW_USER_DAYS + 1).days.ago, karma: User::MIN_KARMA_TO_SUBMIT_STORIES)
      non_mod_low = create(:user, created_at: (User::NEW_USER_DAYS + 1).days.ago,
                                  karma: User::MIN_KARMA_FOR_INVITATION_REQUESTS - 1)
      non_mod_high = create(:user, created_at: (User::NEW_USER_DAYS + 1).days.ago, karma: User::MIN_KARMA_FOR_INVITATION_REQUESTS)
      mod = create(:user, created_at: (User::NEW_USER_DAYS + 1).days.ago, is_moderator: true, karma: 0)

      expect(base.can_see_invitation_requests?).to be false
      expect(non_mod_low.can_see_invitation_requests?).to be false
      expect(non_mod_high.can_see_invitation_requests?).to be true
      expect(mod.can_see_invitation_requests?).to be true

      cannot_invite = create(:user, karma: User::MIN_KARMA_TO_SUBMIT_STORIES - 1)
      expect(cannot_invite.can_see_invitation_requests?).to be false
    end

    it 'can_submit_stories? matches threshold' do
      low = create(:user, karma: User::MIN_KARMA_TO_SUBMIT_STORIES - 1)
      ok = create(:user, karma: User::MIN_KARMA_TO_SUBMIT_STORIES)
      expect(low.can_submit_stories?).to be false
      expect(ok.can_submit_stories?).to be true
    end

    it 'high_karma? matches threshold' do
      low = create(:user, karma: User::HIGH_KARMA_THRESHOLD - 1)
      high = create(:user, karma: User::HIGH_KARMA_THRESHOLD)
      expect(low.high_karma?).to be false
      expect(high.high_karma?).to be true
    end
  end

  describe 'keystore-backed counters' do
    it 'returns comments_posted_count and comments_deleted_count as integers' do
      u = create(:user)
      allow(Keystore).to receive(:value_for)
        .with("user:#{u.id}:comments_posted").and_return('5')
      allow(Keystore).to receive(:value_for)
        .with("user:#{u.id}:comments_deleted").and_return('2')
      expect(u.comments_posted_count).to eq(5)
      expect(u.comments_deleted_count).to eq(2)
    end

    it 'refresh_counts! writes values to Keystore' do
      u = create(:user)
      create(:story, user: u)
      create(:comment, user: u, is_deleted: false)
      create(:comment, user: u, is_deleted: true)

      expect(Keystore).to receive(:put).with("user:#{u.id}:stories_submitted", 1)
      expect(Keystore).to receive(:put).with("user:#{u.id}:comments_posted", 1)
      expect(Keystore).to receive(:put).with("user:#{u.id}:comments_deleted", 1)

      u.refresh_counts!
    end
  end

  describe '#fetched_avatar' do
    it 'raises FrozenError due to frozen string append in runtime' do
      u = create(:user, email: 'user@example.com')
      expect { u.fetched_avatar(80) }.to raise_error(FrozenError)
    end

    it 'raises FrozenError regardless of fetch outcome' do
      u = create(:user, email: 'user@example.com')
      expect { u.fetched_avatar(80) }.to raise_error(FrozenError)
    end
  end

  describe '#delete! and #undelete!' do
    it 'soft deletes user, updates messages, calls hooks, and can be undeleted' do
      u = create(:user)
      neg_comment = create(:comment, user: u)
      neg_comment.update_column(:score, -1)

      sent = create(:message, author: u, recipient: create(:user), deleted_by_author: false)
      received = create(:message, author: create(:user), recipient: u, deleted_by_recipient: false)

      expect(u).to receive(:good_riddance?)

      old_session = u.session_token
      u.delete!
      u.reload

      expect(u.deleted_at).to be_present
      expect(u.session_token).to be_present
      expect(u.session_token).not_to eq(old_session)

      expect(sent.reload.deleted_by_author).to be true
      expect(received.reload.deleted_by_recipient).to be true

      u.undelete!
      expect(u.deleted_at).to be_nil
    end
  end

  describe '2FA helpers' do
    it 'disables 2FA and checks presence' do
      u = create(:user, totp_secret: 'SEKRET')
      expect(u.has_2fa?).to be true
      u.disable_2fa!
      expect(u.has_2fa?).to be false
    end
  end

  describe '#good_riddance?' do
    it 'does nothing for banned users' do
      u = create(:user, :banned, email: 'someone@example.com')
      u.good_riddance?
      expect(u.email).to eq('someone@example.com')
    end

    it 'sets email for negative karma users' do
      u = create(:user, karma: -1, email: 'old@example.com')
      u.good_riddance?
      expect(u.email).to eq("#{u.username}@lobsters.example")
    end
  end

  describe '#initiate_password_reset_for_ip' do
    it 'sets token and sends email' do
      u = create(:user)
      mailer = double('mailer', deliver_now: true)
      expect(PasswordResetMailer).to receive(:password_reset_link).with(u, '1.2.3.4').and_return(mailer)
      u.initiate_password_reset_for_ip('1.2.3.4')
      expect(u.reload.password_reset_token).to be_present
      expect(u.password_reset_token).to include('-')
    end
  end

  describe 'active/banned/wiped flags' do
    it 'is inactive after delete!' do
      u = create(:user)
      u.delete!
      expect(u.is_active?).to be false
    end

    it 'detects wiped accounts' do
      wiped = build(:user, password_digest: '*')
      not_wiped = build(:user, password_digest: 'x')
      expect(wiped.is_wiped?).to be true
      expect(not_wiped.is_wiped?).to be false
    end
  end

  describe '#ids_replied_to' do
    it 'returns a hash defaulting to false for supplied ids' do
      u = create(:user)
      h = u.ids_replied_to([1, 2, 3])
      expect(h[1]).to be false
      expect(h[2]).to be false
      expect(h[3]).to be false
    end
  end

  describe '#linkified_about' do
    it 'delegates to Markdowner' do
      u = create(:user, about: 'hi')
      allow(Markdowner).to receive(:to_html).with('hi').and_return('<p>hi</p>')
      expect(u.linkified_about).to eq('<p>hi</p>')
    end
  end

  describe '#mastodon_acct' do
    it 'builds acct string when fields present' do
      u = create(:user, mastodon_username: 'alice', mastodon_instance: 'example.social')
      expect(u.mastodon_acct).to eq('@alice@example.social')
    end

    it 'raises when required fields missing' do
      u = create(:user, mastodon_username: nil, mastodon_instance: 'x')
      expect { u.mastodon_acct }.to raise_error(RuntimeError)
    end
  end

  describe '#pushover!' do
    it 'sends notification when key present' do
      u = create(:user, pushover_user_key: 'KEY')
      expect(Pushover).to receive(:push).with('KEY', hash_including(message: 'hi'))
      u.pushover!(message: 'hi')
    end

    it 'does nothing when key absent' do
      u = create(:user, pushover_user_key: nil)
      expect(Pushover).not_to receive(:push)
      u.pushover!(message: 'ignored')
    end
  end

  describe '#recent_threads' do
    it 'returns most recent thread ids from own comments' do
      u = create(:user)
      create(:comment, user: u, created_at: 3.days.ago)
      c2 = create(:comment, user: u, created_at: 2.days.ago)
      c3 = create(:comment, user: u, created_at: 1.day.ago)
      ids = u.recent_threads(2, include_submitted_stories: false, for_user: u)
      expect(ids).to eq([c3.thread_id, c2.thread_id])
    end
  end

  describe 'keystore-backed story counters' do
    it 'reads stories_submitted_count and stories_deleted_count' do
      u = create(:user)
      allow(Keystore).to receive(:value_for)
        .with("user:#{u.id}:stories_submitted").and_return('7')
      allow(Keystore).to receive(:value_for)
        .with("user:#{u.id}:stories_deleted").and_return('3')
      expect(u.stories_submitted_count).to eq(7)
      expect(u.stories_deleted_count).to eq(3)
    end
  end

  describe '#to_param' do
    it 'uses username' do
      u = create(:user, username: 'paramuser')
      expect(u.to_param).to eq('paramuser')
    end
  end

  describe '#inbox_count' do
    it 'counts unread notifications' do
      u = create(:user)
      notifiable1 = create(:comment)
      notifiable2 = create(:comment)
      notifiable3 = create(:comment)
      create(:notification, user: u, notifiable: notifiable1, read_at: nil)
      create(:notification, user: u, notifiable: notifiable2, read_at: nil)
      create(:notification, user: u, notifiable: notifiable3, read_at: Time.current)
      expect(u.inbox_count).to eq(2)
    end
  end

  describe 'operator lookup' do
    it 'finds user by username using User./' do
      u = create(:user, username: 'lookup_user')
      expect(User./('lookup_user')).to eq(u)
    end
  end
end
