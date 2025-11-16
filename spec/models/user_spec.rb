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

  describe 'additional validations' do
    it 'validates presence of password on create' do
      u = build(:user, password: nil)
      expect(u).to_not be_valid
      expect(u.errors[:password]).to_not be_empty
    end

    it 'validates prefers_color_scheme inclusion' do
      expect(build(:user, prefers_color_scheme: 'system')).to be_valid
      expect(build(:user, prefers_color_scheme: 'dark')).to be_valid
      expect(build(:user, prefers_color_scheme: 'light')).to be_valid
      u = build(:user, prefers_color_scheme: 'invalid')
      expect(u).to_not be_valid
      expect(u.errors[:prefers_color_scheme]).to_not be_empty
    end

    it 'validates prefers_contrast inclusion' do
      expect(build(:user, prefers_contrast: 'system')).to be_valid
      expect(build(:user, prefers_contrast: 'normal')).to be_valid
      expect(build(:user, prefers_contrast: 'high')).to be_valid
      u = build(:user, prefers_contrast: 'invalid')
      expect(u).to_not be_valid
      expect(u.errors[:prefers_contrast]).to_not be_empty
    end

    it 'validates boolean fields inclusion' do
      u = build(:user, show_email: nil)
      expect(u).to_not be_valid
      expect(u.errors[:show_email]).to_not be_empty
    end
  end

  describe 'scopes' do
    it 'returns active users only' do
      active = create(:user, deleted_at: nil, banned_at: nil)
      banned = create(:user, banned_at: Time.current)
      deleted = create(:user, deleted_at: Time.current)
      expect(User.active).to include(active)
      expect(User.active).to_not include(banned)
      expect(User.active).to_not include(deleted)
    end

    it 'returns moderators including via moderation history' do
      mod_flag = create(:user, is_moderator: true)
      history_mod = create(:user, is_moderator: false)
      non_mod = create(:user, is_moderator: false)
      Moderation.create!(moderator_user_id: history_mod.id, user_id: non_mod.id, action: 'Did something',
                         token: 'some_action')
      result = User.moderators.to_a
      expect(result).to include(mod_flag)
      expect(result).to include(history_mod)
      expect(result).to_not include(non_mod)
    end
  end

  describe 'callbacks and tokens' do
    it 'generates tokens on create and ensures session_token is present' do
      u = create(:user)
      expect(u.session_token).to be_present
      expect(u.session_token.length).to eq(60)
      expect(u.rss_token).to be_present
      expect(u.mailing_list_token).to be_present
    end

    it 'rolls session token' do
      u = create(:user)
      old = u.session_token
      u.roll_session_token
      expect(u.session_token).to be_present
      expect(u.session_token).to_not eq(old)
      expect(u.session_token.length).to eq(60)
    end
  end

  describe '.username_regex_s' do
    it 'returns a stringified regex matching VALID_USERNAME' do
      expected = '/^' + User::VALID_USERNAME.to_s.gsub(/(\?-mix:|\(|\))/, '') + '$/'
      expect(User.username_regex_s).to eq(expected)
    end
  end

  describe '#as_json' do
    let!(:inviter) { create(:user) }

    it 'includes public fields and computed fields for non-admin' do
      u = create(:user, invited_by_user_id: inviter.id, about: 'hi', is_admin: false)
      allow(Markdowner).to receive(:to_html).with(u.about).and_return('about_html')
      allow(ActionController::Base.helpers).to receive(:image_url).and_return('http://example.com/avatar.png')
      h = u.as_json
      expect(h[:username]).to eq(u.username)
      expect(h[:created_at]).to be_present
      expect(h[:karma]).to eq(u.karma)
      expect(h[:about]).to eq('about_html')
      expect(h[:avatar_url]).to eq('http://example.com/avatar.png')
      expect(h[:invited_by_user]).to eq(inviter.username)
    end

    it 'omits karma for admins' do
      u = create(:user, is_admin: true, about: 'hello')
      allow(Markdowner).to receive(:to_html).and_return('md')
      allow(ActionController::Base.helpers).to receive(:image_url).and_return('url')
      h = u.as_json
      expect(h).to_not have_key(:karma)
    end
  end

  describe '#authenticate_totp' do
    it 'delegates to ROTP with the stored secret' do
      u = create(:user, totp_secret: 'secret')
      totp = double
      allow(ROTP::TOTP).to receive(:new).with('secret').and_return(totp)
      allow(totp).to receive(:verify).with('123456').and_return(true)
      expect(u.authenticate_totp('123456')).to eq(true)
    end
  end

  describe 'avatar helpers' do
    let(:u) { create(:user, username: 'alice') }

    it 'builds avatar_path' do
      allow(ActionController::Base.helpers).to receive(:image_path).and_return('/avatars/alice-50.png')
      expect(u.avatar_path(50)).to eq('/avatars/alice-50.png')
    end

    it 'builds avatar_url' do
      allow(ActionController::Base.helpers).to receive(:image_url).and_return('http://cdn/avatars/alice-50.png')
      expect(u.avatar_url(50)).to eq('http://cdn/avatars/alice-50.png')
    end
  end

  describe '#disable_invite_by_user_for_reason!' do
    it 'disables invites, sends message, and records moderation' do
      disabler = create(:user)
      u = create(:user)
      expect(u.disable_invite_by_user_for_reason!(disabler, 'stop inviting')).to be true
      u.reload
      expect(u.disabled_invite_at).to be_present
      expect(u.disabled_invite_by_user_id).to eq(disabler.id)
      expect(u.disabled_invite_reason).to eq('stop inviting')

      msg = Message.order(:id).last
      expect(msg.author_user_id).to eq(disabler.id)
      expect(msg.recipient_user_id).to eq(u.id)
      expect(msg.deleted_by_author).to be true
      expect(msg.subject).to include('revoked')

      mod = Moderation.order(:id).last
      expect(mod.moderator_user_id).to eq(disabler.id)
      expect(mod.user_id).to eq(u.id)
      expect(mod.action).to eq('Disabled invitations')
      expect(mod.reason).to eq('stop inviting')
    end
  end

  describe '#ban_by_user_for_reason!' do
    it 'bans, notifies, deletes the user, and records moderation' do
      banner = create(:user)
      u = create(:user)
      mail = double
      allow(BanNotificationMailer).to receive(:notify).and_return(mail)
      allow(mail).to receive(:deliver_now).and_return(true)

      expect(u.ban_by_user_for_reason!(banner, 'spam')).to be true
      u.reload
      expect(u.is_banned?).to be true
      expect(u.deleted_at).to be_present

      mod = Moderation.order(:id).last
      expect(mod.moderator_user_id).to eq(banner.id)
      expect(mod.user_id).to eq(u.id)
      expect(mod.action).to eq('Banned')
      expect(mod.reason).to eq('spam')
      expect(BanNotificationMailer).to have_received(:notify).with(u, banner, 'spam')
    end
  end

  describe 'invitation permissions' do
    it 'reports banned_from_inviting? based on disabled_invite_at' do
      u = create(:user, disabled_invite_at: nil)
      expect(u.banned_from_inviting?).to be false
      u.update!(disabled_invite_at: Time.current)
      expect(u.banned_from_inviting?).to be true
    end

    it 'can_invite? depends on karma and invite ban' do
      u = create(:user, karma: User::MIN_KARMA_TO_SUBMIT_STORIES)
      expect(u.can_invite?).to be true
      u.update!(karma: User::MIN_KARMA_TO_SUBMIT_STORIES - 1)
      expect(u.can_invite?).to be false
      u.update!(karma: 10, disabled_invite_at: Time.current)
      expect(u.can_invite?).to be false
    end

    it 'can_offer_suggestions? requires not new and minimum karma' do
      u = create(:user, created_at: (User::NEW_USER_DAYS + 1).days.ago, karma: User::MIN_KARMA_TO_SUGGEST)
      expect(u.can_offer_suggestions?).to be true
      u.update!(karma: User::MIN_KARMA_TO_SUGGEST - 1)
      expect(u.can_offer_suggestions?).to be false
      new_user = create(:user, created_at: Time.current, karma: 1000)
      expect(new_user.can_offer_suggestions?).to be false
    end

    it 'can_see_invitation_requests? for moderators or high-karma users who can invite' do
      mod = create(:user, is_moderator: true, karma: User::MIN_KARMA_TO_SUBMIT_STORIES)
      expect(mod.can_see_invitation_requests?).to be true

      high = create(:user, karma: User::MIN_KARMA_FOR_INVITATION_REQUESTS,
                           created_at: (User::NEW_USER_DAYS + 1).days.ago)
      expect(high.can_see_invitation_requests?).to be true

      low = create(:user, karma: User::MIN_KARMA_FOR_INVITATION_REQUESTS - 1)
      expect(low.can_see_invitation_requests?).to be false

      banned = create(:user, karma: 100, disabled_invite_at: Time.current)
      expect(banned.can_see_invitation_requests?).to be false
    end
  end

  describe '#can_submit_stories?' do
    it 'allows submission at or above threshold' do
      u = create(:user, karma: User::MIN_KARMA_TO_SUBMIT_STORIES)
      expect(u.can_submit_stories?).to be true
      u.update!(karma: User::MIN_KARMA_TO_SUBMIT_STORIES - 1)
      expect(u.can_submit_stories?).to be false
    end
  end

  describe '#high_karma?' do
    it 'returns true at or above threshold' do
      u = create(:user, karma: User::HIGH_KARMA_THRESHOLD)
      expect(u.high_karma?).to be true
      u.update!(karma: User::HIGH_KARMA_THRESHOLD - 1)
      expect(u.high_karma?).to be false
    end
  end

  describe 'comment/story counts' do
    it 'reads counts from Keystore' do
      u = create(:user)
      allow(Keystore).to receive(:value_for).with("user:#{u.id}:comments_posted").and_return('5')
      allow(Keystore).to receive(:value_for).with("user:#{u.id}:comments_deleted").and_return('2')
      allow(Keystore).to receive(:value_for).with("user:#{u.id}:stories_submitted").and_return('7')
      allow(Keystore).to receive(:value_for).with("user:#{u.id}:stories_deleted").and_return('3')
      expect(u.comments_posted_count).to eq(5)
      expect(u.comments_deleted_count).to eq(2)
      expect(u.stories_submitted_count).to eq(7)
      expect(u.stories_deleted_count).to eq(3)
    end

    it 'refreshes counts into Keystore' do
      u = create(:user)
      create(:story, user: u, is_deleted: false)
      create(:comment, user: u, is_deleted: false)
      create(:comment, user: u, is_deleted: true)
      expect(Keystore).to receive(:put).with("user:#{u.id}:stories_submitted", u.stories.count)
      expect(Keystore).to receive(:put).with("user:#{u.id}:comments_posted", u.comments.active.count)
      expect(Keystore).to receive(:put).with("user:#{u.id}:comments_deleted", u.comments.deleted.count)
      u.refresh_counts!
    end
  end

  describe '#fetched_avatar' do
    it 'returns bytes when fetch succeeds' do
      allow_any_instance_of(String).to receive(:<<) { |str, arg| str + arg.to_s }
      u = create(:user, email: 'user@example.com')
      sponge = double
      allow(Sponge).to receive(:new).and_return(sponge)
      allow(sponge).to receive(:timeout=)
      allow(sponge).to receive(:fetch).and_return(double(body: 'IMGDATA'))
      expect(u.fetched_avatar(80)).to eq('IMGDATA')
    end

    it 'returns nil when fetch fails' do
      allow_any_instance_of(String).to receive(:<<) { |str, arg| str + arg.to_s }
      u = create(:user, email: 'user@example.com')
      sponge = double
      allow(Sponge).to receive(:new).and_return(sponge)
      allow(sponge).to receive(:timeout=)
      allow(sponge).to receive(:fetch).and_raise(StandardError.new('boom'))
      expect(u.fetched_avatar(80)).to be_nil
    end
  end

  describe 'deletion and undeletion' do
    it 'marks deleted and can be undeleted' do
      u = create(:user)
      old_token = u.session_token
      u.delete!
      u.reload
      expect(u.deleted_at).to be_present
      expect(u.session_token).to_not eq(old_token)
      u.undelete!
      u.reload
      expect(u.deleted_at).to be_nil
    end
  end

  describe '#disable_2fa!' do
    it 'clears totp secret' do
      u = create(:user, totp_secret: 'abc')
      u.disable_2fa!
      expect(u.totp_secret).to be_nil
    end
  end

  describe '#good_riddance?' do
    it 'changes email for negative karma users unless banned' do
      u = create(:user, karma: -1, email: 'real@example.com')
      u.good_riddance?
      expect(u.email).to eq("#{u.username}@lobsters.example")

      banned = create(:user, :banned, karma: -10, email: 'real2@example.com')
      banned.good_riddance?
      expect(banned.email).to eq('real2@example.com')
    end

    it 'changes email when flagged commenter' do
      u = create(:user, karma: 10, email: 'real@example.com')
      fc = double
      allow(FlaggedCommenters).to receive(:new).with('90d').and_return(fc)
      allow(fc).to receive(:check_list_for).with(u).and_return(true)
      u.good_riddance?
      expect(u.email).to eq("#{u.username}@lobsters.example")
    end
  end

  describe '#grant_moderatorship_by_user!' do
    it 'grants moderator status, creates moderation and hat' do
      granter = create(:user)
      u = create(:user, is_moderator: false)
      expect(u.grant_moderatorship_by_user!(granter)).to be true
      u.reload
      expect(u.is_moderator).to be true
      mod = Moderation.where(action: 'Granted moderator status').order(:id).last
      expect(mod.moderator_user_id).to eq(granter.id)
      expect(mod.user_id).to eq(u.id)
      expect(mod.action).to eq('Granted moderator status')
      hat = Hat.order(:id).last
      expect(hat.user_id).to eq(u.id)
      expect(hat.granted_by_user_id).to eq(granter.id)
      expect(hat.hat).to eq('Sysop')
    end
  end

  describe '#initiate_password_reset_for_ip' do
    it 'sets a token and sends an email' do
      u = create(:user)
      allow(Utils).to receive(:random_str).and_return('abcd')
      mail = double
      allow(PasswordResetMailer).to receive(:password_reset_link).and_return(mail)
      allow(mail).to receive(:deliver_now).and_return(true)
      u.initiate_password_reset_for_ip('127.0.0.1')
      u.reload
      expect(u.password_reset_token).to match(/\A\d+-abcd\z/)
      expect(PasswordResetMailer).to have_received(:password_reset_link).with(u, '127.0.0.1')
    end
  end

  describe '2FA helpers' do
    it 'has_2fa? reflects totp_secret presence' do
      u = create(:user, totp_secret: nil)
      expect(u.has_2fa?).to be false
      u.update!(totp_secret: 'xyz')
      expect(u.has_2fa?).to be true
    end
  end

  describe 'activity helpers' do
    it 'is_active? returns false for deleted users' do
      u = create(:user, deleted_at: Time.current)
      expect(u.is_active?).to be false
    end

    it "is_wiped? returns true when password is '*'" do
      u = create(:user)
      u.update_column(:password_digest, '*')
      expect(u.is_wiped?).to be true
    end
  end

  describe '#linkified_about' do
    it 'uses Markdowner to render about' do
      u = create(:user, about: 'hello')
      allow(Markdowner).to receive(:to_html).with('hello').and_return('<p>hello</p>')
      expect(u.linkified_about).to eq('<p>hello</p>')
    end
  end

  describe '#mastodon_acct' do
    it 'returns acct with username and instance' do
      u = create(:user, mastodon_username: 'alice', mastodon_instance: 'example.social')
      expect(u.mastodon_acct).to eq('@alice@example.social')
    end

    it 'raises when missing fields' do
      u = create(:user, mastodon_username: nil, mastodon_instance: nil)
      expect { u.mastodon_acct }.to raise_error(RuntimeError)
    end
  end

  describe '#most_common_story_tag' do
    it "returns the most common active tag for user's non-deleted stories" do
      u = create(:user)
      tag1 = create(:tag)
      tag2 = create(:tag)
      s1 = create(:story, user: u, is_deleted: false)
      s2 = create(:story, user: u, is_deleted: false)
      s3 = create(:story, user: u, is_deleted: false)
      create(:tagging, story: s1, tag: tag1)
      create(:tagging, story: s2, tag: tag1)
      create(:tagging, story: s3, tag: tag2)
      expect(u.most_common_story_tag).to eq(tag1)
    end
  end

  describe '#pushover!' do
    it 'pushes when pushover_user_key is present' do
      u = create(:user, pushover_user_key: 'key')
      expect(Pushover).to receive(:push).with('key', hash_including(title: 't'))
      u.pushover!(title: 't', message: 'm')
    end

    it 'does nothing when no user key' do
      u = create(:user, pushover_user_key: nil)
      expect(Pushover).to_not receive(:push)
      u.pushover!(title: 't')
    end
  end

  describe '#to_param' do
    it 'returns the username' do
      u = create(:user, username: 'bob')
      expect(u.to_param).to eq('bob')
    end
  end

  describe '#enable_invite_by_user!' do
    it 'enables invitations and creates a moderation' do
      mod = create(:user)
      u = create(:user, disabled_invite_at: Time.current, disabled_invite_by_user_id: mod.id,
                        disabled_invite_reason: 'x')
      expect(u.enable_invite_by_user!(mod)).to be true
      u.reload
      expect(u.disabled_invite_at).to be_nil
      expect(u.disabled_invite_by_user_id).to be_nil
      expect(u.disabled_invite_reason).to be_nil
      m = Moderation.order(:id).last
      expect(m.user_id).to eq(u.id)
      expect(m.moderator_user_id).to eq(mod.id)
      expect(m.action).to eq('Enabled invitations')
    end
  end

  describe '#inbox_count' do
    it 'counts unread notifications' do
      u = create(:user)
      s = create(:story, user: u)
      c = create(:comment, user: u, story: s)
      create(:notification, user: u, notifiable: s, read_at: nil)
      create(:notification, user: u, notifiable: c, read_at: nil)
      create(:notification, user: u, notifiable: s, read_at: Time.current)
      expect(u.inbox_count).to eq(2)
    end
  end

  describe '#votes_for_others' do
    it "returns only votes on others' content" do
      voter = create(:user)
      other = create(:user)
      own_story = create(:story, user: voter)
      other_story = create(:story, user: other)
      own_comment = create(:comment, user: voter, story: own_story)
      other_comment = create(:comment, user: other, story: other_story)

      vote_on_own_story = create(:vote, user: voter, story: own_story, comment: nil)
      vote_on_other_story = create(:vote, user: voter, story: other_story, comment: nil)
      vote_on_own_comment = create(:vote, user: voter, comment: own_comment, story: own_story)
      vote_on_other_comment = create(:vote, user: voter, comment: other_comment, story: other_story)

      results = voter.votes_for_others.to_a
      expect(results).to include(vote_on_other_story, vote_on_other_comment)
      expect(results).to_not include(vote_on_own_story, vote_on_own_comment)
    end
  end
end
