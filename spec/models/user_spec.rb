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
    it { is_expected.to have_many(:stories) }
    it { is_expected.to have_many(:comments) }
    it { is_expected.to have_many(:sent_messages).class_name('Message') }
    it { is_expected.to have_many(:received_messages).class_name('Message') }
    it { is_expected.to have_many(:tag_filters) }
    it { is_expected.to have_many(:hats) }
    it { is_expected.to have_many(:notifications) }
    it { is_expected.to have_many(:votes) }
    it { is_expected.to belong_to(:invited_by_user).optional }
    it { is_expected.to belong_to(:banned_by_user).optional }
    it { is_expected.to belong_to(:disabled_invite_by_user).optional }
  end

  describe 'scopes' do
    let!(:active_user) do
      create(:user, banned_at: nil, deleted_at: nil)
    end

    let!(:banned_user) do
      create(:user, banned_at: Time.current)
    end

    let!(:deleted_user) do
      create(:user, deleted_at: Time.current)
    end

    it 'returns only active users for .active' do
      expect(User.active).to include(active_user)
      expect(User.active).to_not include(banned_user)
      expect(User.active).to_not include(deleted_user)
    end

    it 'returns moderators by flag or by moderation records' do
      mod1 = create(:user, is_moderator: true)
      non_mod = create(:user, is_moderator: false)
      expect(User.moderators).to include(mod1)
      expect(User.moderators).to_not include(non_mod)
    end
  end

  describe '.username_regex_s' do
    it 'returns a regex-like string with anchors' do
      str = User.username_regex_s
      expect(str).to start_with('/^')
      expect(str).to end_with('$/')
      expect(str).to include('[A-Za-z0-9')
    end
  end

  describe '#as_json' do
    let!(:inviter) do
      create(:user, username: 'inviter_user')
    end

    let!(:user) do
      create(:user, about: 'about me', invited_by_user: inviter, github_username: 'octocat',
                    mastodon_username: 'alice', mastodon_instance: 'example.social')
    end

    before do
      allow(user).to receive(:avatar_url).and_return('http://assets.test/avatar.png')
      allow(Markdowner).to receive(:to_html).with('about me').and_return('<p>about me</p>')
    end

    it 'includes expected fields for non-admin users and excludes sensitive fields' do
      h = user.as_json
      expect(h[:username]).to eq(user.username)
      expect(h).to include(:karma)
      expect(h[:about]).to eq('<p>about me</p>')
      expect(h[:avatar_url]).to eq('http://assets.test/avatar.png')
      expect(h[:invited_by_user]).to eq('inviter_user')
      expect(h[:github_username]).to eq('octocat')
      expect(h[:mastodon_username]).to eq('alice')
      expect(h[:homepage]).to eq(user.homepage)
      expect(h).to_not have_key(:totp_secret)
      expect(h).to_not have_key(:session_token)
    end

    it 'omits karma for admin users' do
      user.update!(is_admin: true)
      expect(user.as_json).to_not have_key(:karma)
    end
  end

  describe '#authenticate_totp' do
    let(:secret) do
      ROTP::Base32.random
    end

    let(:user) do
      create(:user, totp_secret: secret)
    end

    it 'returns truthy for a valid current code' do
      code = ROTP::TOTP.new(secret).now
      expect(user.authenticate_totp(code)).to be_truthy
    end

    it 'returns falsey for an invalid code' do
      expect(user.authenticate_totp('000000')).to be_falsey
    end
  end

  describe 'avatar helpers' do
    let(:user) do
      create(:user, username: 'alice')
    end

    it 'builds avatar_path with given size' do
      path = user.avatar_path(200)
      expect(path).to include('/avatars/alice-200.png')
    end

    it 'builds avatar_url with given size' do
      url = user.avatar_url(150)
      expect(url).to include('/avatars/alice-150.png')
    end
  end

  describe 'invite disabling/enabling' do
    let(:mod) do
      create(:user)
    end

    let(:user) do
      create(:user)
    end

    it 'disables invites, sends a message, and logs moderation' do
      expect do
        expect(user.disable_invite_by_user_for_reason!(mod, 'spamming invites')).to be true
      end.to change { Moderation.count }.by(1)
                                        .and change { Message.count }.by(1)

      user.reload
      expect(user.banned_from_inviting?).to be true
      expect(user.disabled_invite_by_user).to eq(mod)
      expect(user.disabled_invite_reason).to eq('spamming invites')
      expect(user.disabled_invite_at).to be_present
    end

    it 're-enables invites and logs moderation' do
      user.disable_invite_by_user_for_reason!(mod, 'spamming invites')
      expect do
        expect(user.enable_invite_by_user!(mod)).to be true
      end.to change { Moderation.count }.by(1)
      user.reload
      expect(user.banned_from_inviting?).to be false
      expect(user.disabled_invite_by_user).to be_nil
      expect(user.disabled_invite_reason).to be_nil
      expect(user.disabled_invite_at).to be_nil
    end
  end

  describe '#ban_by_user_for_reason!' do
    let(:mod) do
      create(:user)
    end

    let(:user) do
      create(:user)
    end

    it 'bans, deletes, emails, and logs moderation' do
      mailer_double = double('mailer', deliver_now: true)
      expect(BanNotificationMailer).to receive(:notify).with(user, mod, 'rule violation').and_return(mailer_double)
      expect do
        expect(user.ban_by_user_for_reason!(mod, 'rule violation')).to be true
      end.to change { Moderation.count }.by(1)
      user.reload
      expect(user.deleted_at).to be_present
      expect(user.is_banned?).to be true
      expect(user.banned_by_user).to eq(mod)
      expect(user.banned_reason).to eq('rule violation')
    end
  end

  describe 'permissions' do
    let(:old_user) do
      create(:user, created_at: (User::NEW_USER_DAYS + 1).days.ago, karma: User::MIN_KARMA_TO_FLAG)
    end

    let(:new_user) do
      create(:user, created_at: Time.current, karma: 999)
    end

    let(:story) do
      create(:story)
    end

    let(:comment) do
      create(:comment)
    end

    it 'prevents new users from flagging anything' do
      allow(story).to receive(:is_flaggable?).and_return(true)
      expect(new_user.can_flag?(story)).to be false
    end

    it 'allows eligible users to flag stories that are flaggable' do
      allow(story).to receive(:is_flaggable?).and_return(true)
      expect(old_user.can_flag?(story)).to be true
    end

    it 'allows eligible users to unvote flagged stories' do
      allow(story).to receive(:is_flaggable?).and_return(false)
      allow(story).to receive(:current_flagged?).and_return(true)
      expect(old_user.can_flag?(story)).to be true
    end

    it 'allows eligible users with enough karma to flag comments' do
      allow(comment).to receive(:is_flaggable?).and_return(true)
      expect(old_user.can_flag?(comment)).to be true
    end

    it 'prevents low-karma users from flagging comments' do
      u = create(:user, created_at: (User::NEW_USER_DAYS + 1).days.ago, karma: User::MIN_KARMA_TO_FLAG - 1)
      allow(comment).to receive(:is_flaggable?).and_return(true)
      expect(u.can_flag?(comment)).to be false
    end

    it 'evaluates can_invite? based on invite ban and minimal submit karma' do
      u = create(:user, karma: User::MIN_KARMA_TO_SUBMIT_STORIES)
      expect(u.can_invite?).to be true
      u.disable_invite_by_user_for_reason!(create(:user), 'testing')
      expect(u.can_invite?).to be false
    end

    it 'evaluates can_offer_suggestions? requiring not-new and karma threshold' do
      u1 = create(:user, created_at: (User::NEW_USER_DAYS + 1).days.ago, karma: User::MIN_KARMA_TO_SUGGEST)
      expect(u1.can_offer_suggestions?).to be true
      u2 = create(:user, created_at: (User::NEW_USER_DAYS + 1).days.ago, karma: User::MIN_KARMA_TO_SUGGEST - 1)
      expect(u2.can_offer_suggestions?).to be false
    end

    it 'evaluates can_see_invitation_requests? for moderators or high-karma users who can invite' do
      mod = create(:user, is_moderator: true, karma: User::MIN_KARMA_TO_SUBMIT_STORIES)
      expect(mod.can_see_invitation_requests?).to be true
      high = create(:user, karma: User::MIN_KARMA_FOR_INVITATION_REQUESTS)
      expect(high.can_see_invitation_requests?).to be true
      low = create(:user, karma: User::MIN_KARMA_FOR_INVITATION_REQUESTS - 1)
      expect(low.can_see_invitation_requests?).to be false
    end

    it 'evaluates can_submit_stories? on threshold' do
      u1 = create(:user, karma: User::MIN_KARMA_TO_SUBMIT_STORIES)
      u2 = create(:user, karma: User::MIN_KARMA_TO_SUBMIT_STORIES - 1)
      expect(u1.can_submit_stories?).to be true
      expect(u2.can_submit_stories?).to be false
    end

    it 'evaluates high_karma? on threshold' do
      u1 = create(:user, karma: User::HIGH_KARMA_THRESHOLD)
      u2 = create(:user, karma: User::HIGH_KARMA_THRESHOLD - 1)
      expect(u1.high_karma?).to be true
      expect(u2.high_karma?).to be false
    end
  end

  describe 'tokens and callbacks' do
    it 'assigns session_token on create if blank' do
      u = build(:user, session_token: nil)
      expect(u.session_token).to be_nil
      u.save!
      expect(u.session_token).to be_present
      expect(u.session_token.length).to be >= 20
    end

    it 'generates rss and mailing list tokens on create' do
      u = create(:user, rss_token: nil, mailing_list_token: nil)
      expect(u.rss_token).to be_present
      expect(u.rss_token.length).to eq(60)
      expect(u.mailing_list_token).to be_present
      expect(u.mailing_list_token.length).to eq(10)
    end

    it 'rolls the session_token' do
      u = create(:user)
      old = u.session_token
      u.roll_session_token
      expect(u.session_token).to be_present
      expect(u.session_token).to_not eq(old)
      expect(u.session_token.length).to eq(60)
    end
  end

  describe 'keystore-backed counters' do
    let(:user) do
      create(:user)
    end

    it 'reads comments_posted_count and comments_deleted_count' do
      expect(Keystore).to receive(:value_for).with("user:#{user.id}:comments_posted").and_return('3')
      expect(Keystore).to receive(:value_for).with("user:#{user.id}:comments_deleted").and_return('2')
      expect(user.comments_posted_count).to eq(3)
      expect(user.comments_deleted_count).to eq(2)
    end

    it 'refresh_counts! writes counters' do
      create_list(:comment, 2, user: user, is_deleted: false)
      create(:comment, user: user, is_deleted: true)
      allow(Keystore).to receive(:put)
      expect(Keystore).to receive(:put).with("user:#{user.id}:stories_submitted", user.stories.count)
      expect(Keystore).to receive(:put).with("user:#{user.id}:comments_posted", user.comments.active.count)
      expect(Keystore).to receive(:put).with("user:#{user.id}:comments_deleted", user.comments.deleted.count)
      user.refresh_counts!
    end

    it 'reads stories_submitted_count and stories_deleted_count' do
      expect(Keystore).to receive(:value_for).with("user:#{user.id}:stories_submitted").and_return('7')
      expect(Keystore).to receive(:value_for).with("user:#{user.id}:stories_deleted").and_return('4')
      expect(user.stories_submitted_count).to eq(7)
      expect(user.stories_deleted_count).to eq(4)
    end
  end

  describe '#fetched_avatar' do
    let(:user) do
      create(:user, email: 'user@example.com')
    end

    it 'returns body when sponge fetch succeeds' do
      sponge = double('Sponge', timeout: nil)
      response = double('Net::HTTPResponse', body: 'pngbytes')
      expect(Sponge).to receive(:new).and_return(sponge)
      expect(sponge).to receive(:timeout=).with(3)
      expect(sponge).to receive(:fetch).and_return(response)
      expect(user.fetched_avatar(64)).to eq('pngbytes')
    end

    it 'returns nil when sponge raises' do
      sponge = double('Sponge', timeout: nil)
      expect(Sponge).to receive(:new).and_return(sponge)
      expect(sponge).to receive(:timeout=).with(3)
      expect(sponge).to receive(:fetch).and_raise(StandardError.new('network'))
      expect(user.fetched_avatar(64)).to be_nil
    end
  end

  describe '#delete! and #undelete!' do
    let(:user) do
      create(:user)
    end

    it 'marks the user as deleted and rolls session token' do
      old = user.session_token
      user.delete!
      user.reload
      expect(user.deleted_at).to be_present
      expect(user.session_token).to be_present
      expect(user.session_token).to_not eq(old)
    end

    it 'restores the user on undelete!' do
      user.update!(deleted_at: Time.current)
      user.undelete!
      expect(user.deleted_at).to be_nil
    end
  end

  describe '2FA helpers' do
    it 'disables 2FA and checks has_2fa?' do
      u = create(:user, totp_secret: 'SECRET')
      expect(u.has_2fa?).to be true
      u.disable_2fa!
      expect(u.has_2fa?).to be false
    end
  end

  describe '#good_riddance?' do
    it 'replaces email for negative karma users' do
      u = create(:user, username: 'alice', karma: -1, email: 'alice@example.com')
      u.good_riddance?
      expect(u.email).to eq('alice@lobsters.example')
    end
  end

  describe '#grant_moderatorship_by_user!' do
    let(:grantor) do
      create(:user)
    end

    let(:user) do
      create(:user, is_moderator: false)
    end

    it 'grants moderator and creates moderation and hat' do
      expect do
        expect(user.grant_moderatorship_by_user!(grantor)).to be true
      end.to change { Moderation.count }.by(1)
                                        .and change { Hat.count }.by(1)
      user.reload
      expect(user.is_moderator).to be true
      expect(user.hats.where(hat: 'Sysop')).to exist
    end
  end

  describe '#initiate_password_reset_for_ip' do
    let(:user) do
      create(:user)
    end

    it 'sets a reset token and sends a mail' do
      mailer_double = double('mailer', deliver_now: true)
      expect(PasswordResetMailer).to receive(:password_reset_link).with(user, '127.0.0.1').and_return(mailer_double)
      user.initiate_password_reset_for_ip('127.0.0.1')
      expect(user.password_reset_token).to be_present
      expect(user.password_reset_token).to match(/\A\d+-/)
    end
  end

  describe '#is_wiped?' do
    it "returns true when password_digest is '*'" do
      u = create(:user)
      u.update_columns(password_digest: '*')
      expect(u.is_wiped?).to be true
    end
  end

  describe '#linkified_about' do
    it 'delegates to Markdowner' do
      u = create(:user, about: 'hello')
      expect(Markdowner).to receive(:to_html).with('hello').and_return('<p>hello</p>')
      expect(u.linkified_about).to eq('<p>hello</p>')
    end
  end

  describe '#mastodon_acct' do
    it 'returns acct when username and instance present' do
      u = create(:user, mastodon_username: 'alice', mastodon_instance: 'example.social')
      expect(u.mastodon_acct).to eq('@alice@example.social')
    end

    it 'raises when fields missing' do
      u = create(:user, mastodon_username: nil, mastodon_instance: nil)
      expect { u.mastodon_acct }.to raise_error(RuntimeError)
    end
  end

  describe '#most_common_story_tag' do
    let(:user) do
      create(:user)
    end

    let!(:tag1) do
      create(:tag, tag: 'ruby')
    end

    let!(:tag2) do
      create(:tag, tag: 'rails')
    end

    it "returns the most common active tag for user's non-deleted stories" do
      s1 = create(:story, user: user, is_deleted: false)
      s2 = create(:story, user: user, is_deleted: false)
      s3 = create(:story, user: user, is_deleted: true)
      s1.tags << tag1
      s2.tags << tag1
      s3.tags << tag2
      expect(user.most_common_story_tag).to eq(tag1)
    end
  end

  describe '#pushover!' do
    it 'sends when user has a pushover_user_key' do
      u = create(:user, pushover_user_key: 'KEY123')
      expect(Pushover).to receive(:push).with('KEY123', hash_including(message: 'hi'))
      u.pushover!(message: 'hi')
    end

    it 'does nothing without a pushover_user_key' do
      u = create(:user, pushover_user_key: nil)
      expect(Pushover).to_not receive(:push)
      u.pushover!(message: 'hi')
    end
  end

  describe '#recent_threads' do
    let(:user) do
      create(:user)
    end

    it "returns thread ids ordered by recent activity from user's comments" do
      c1 = create(:comment, user: user, created_at: 2.days.ago, thread_id: 11)
      c2 = create(:comment, user: user, created_at: 1.day.ago, thread_id: 22)
      c3 = create(:comment, user: user, created_at: 3.days.ago, thread_id: 33)
      result = user.recent_threads(2, include_submitted_stories: false, for_user: user)
      expect(result).to eq([22, 11])
      expect(result).to_not include(33)
      expect([c1.thread_id, c2.thread_id, c3.thread_id]).to include(*result)
    end
  end

  describe '#to_param' do
    it 'uses username for routing' do
      u = create(:user, username: 'alice')
      expect(u.to_param).to eq('alice')
    end
  end

  describe '#inbox_count' do
    it 'returns count of unread notifications' do
      u = create(:user)
      create_list(:notification, 2, user: u, read_at: nil)
      create(:notification, user: u, read_at: Time.current)
      expect(u.inbox_count).to eq(2)
    end
  end

  describe '#votes_for_others' do
    let(:voter) do
      create(:user)
    end

    let(:other) do
      create(:user)
    end

    it "includes votes on others' stories and comments and excludes self-votes" do
      story_by_other = create(:story, user: other)
      story_by_voter = create(:story, user: voter)
      comment_by_other = create(:comment, user: other, story: story_by_other)
      comment_by_voter = create(:comment, user: voter, story: story_by_voter)

      vote_story_other = create(:vote, user: voter, story: story_by_other, comment: nil, vote: 1)
      create(:vote, user: voter, story: story_by_voter, comment: nil, vote: 1)
      vote_comment_other = create(:vote, user: voter, story: story_by_other, comment: comment_by_other, vote: 1)
      create(:vote, user: voter, story: story_by_voter, comment: comment_by_voter, vote: 1)

      ids = voter.votes_for_others.pluck(:id)
      expect(ids).to include(vote_story_other.id, vote_comment_other.id)
      expect(ids.length).to eq(2)
    end
  end
end
