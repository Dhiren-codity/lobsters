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

  describe '.username_regex_s' do
    it 'returns a string regex that matches allowed usernames' do
      s = User.username_regex_s
      expect(s).to start_with('/^')
      expect(s).to end_with('$/')
      re = Regexp.new(s[1..-2])
      expect('a').to match(re)
      expect('valid_name-123').to match(re)
      expect('a' * 26).to_not match(re)
      expect('-bad').to_not match(re)
      expect('bad!').to_not match(re)
    end
  end

  describe '#as_json' do
    let!(:inviter) { create(:user, username: 'inviter_user') }

    before do
      allow(Markdowner).to receive(:to_html).and_return('<p>about</p>')
      allow(ActionController::Base.helpers).to receive(:image_url).and_return('http://images.example/avatars/user-100.png')
    end

    it 'includes public fields and karma for non-admins plus optional handles' do
      user = create(:user,
                    invited_by_user: inviter,
                    about: 'about text',
                    homepage: 'https://example.com',
                    github_username: 'octocat',
                    mastodon_username: 'masto_user',
                    mastodon_instance: 'mastodon.example')

      json = user.as_json

      expect(json[:username]).to eq(user.username)
      expect(json.key?(:karma)).to be true
      expect(json[:homepage]).to eq('https://example.com')
      expect(json[:about]).to eq('<p>about</p>')
      expect(json[:avatar_url]).to eq('http://images.example/avatars/user-100.png')
      expect(json[:invited_by_user]).to eq('inviter_user')
      expect(json[:github_username]).to eq('octocat')
      expect(json[:mastodon_username]).to eq('masto_user')
    end

    it 'omits karma for admins' do
      admin = create(:user, is_admin: true, invited_by_user: inviter)
      json = admin.as_json
      expect(json.key?(:karma)).to be false
      expect(json[:invited_by_user]).to eq(inviter.username)
    end
  end

  describe '#authenticate_totp' do
    it 'verifies a valid TOTP code and rejects an invalid one' do
      secret = ROTP::Base32.random_base32
      user = create(:user, totp_secret: secret)
      totp = ROTP::TOTP.new(secret)
      valid_code = totp.now

      expect(user.authenticate_totp(valid_code)).to be_truthy
      expect(user.authenticate_totp('000000')).to be_falsey
    end
  end

  describe '#avatar_path and #avatar_url' do
    let(:user) { create(:user, username: 'alice') }

    it 'returns a path string for the avatar' do
      expect(ActionController::Base.helpers).to receive(:image_path).with('/avatars/alice-80.png',
                                                                          skip_pipeline: true).and_return('/avatars/alice-80.png')
      expect(user.avatar_path(80)).to eq('/avatars/alice-80.png')
    end

    it 'returns a URL string for the avatar' do
      expect(ActionController::Base.helpers).to receive(:image_url).with('/avatars/alice-80.png',
                                                                         skip_pipeline: true).and_return('http://assets/avatars/alice-80.png')
      expect(user.avatar_url(80)).to eq('http://assets/avatars/alice-80.png')
    end
  end

  describe '#disable_invite_by_user_for_reason!' do
    it 'disables invites, sends a message, creates a moderation, and returns true' do
      user = create(:user)
      mod = create(:user)
      reason = 'abuse of invite privileges'

      result = user.disable_invite_by_user_for_reason!(mod, reason)
      user.reload

      expect(result).to be true
      expect(user.banned_from_inviting?).to be true
      expect(user.disabled_invite_by_user_id).to eq(mod.id)
      expect(user.disabled_invite_reason).to eq(reason)

      msg = Message.find_by(author_user_id: mod.id, recipient_user_id: user.id,
                            subject: 'Your invite privileges have been revoked')
      expect(msg).to be_present

      moderation = Moderation.find_by(user_id: user.id, moderator_user_id: mod.id, action: 'Disabled invitations')
      expect(moderation).to be_present
      expect(moderation.reason).to eq(reason)
    end
  end

  describe '#ban_by_user_for_reason!' do
    it 'bans and deletes the user, sends a notification, creates a moderation' do
      allow(FlaggedCommenters).to receive(:new).with('90d').and_return(double(check_list_for: false))
      allow(BanNotificationMailer).to receive(:notify).and_return(double(deliver_now: true))

      user = create(:user)
      banner = create(:user)
      previous_token = user.session_token
      reason = 'TOS violation'

      result = user.ban_by_user_for_reason!(banner, reason)
      user.reload

      expect(result).to be true
      expect(user.is_banned?).to be true
      expect(user.deleted_at?).to be true
      expect(user.banned_by_user_id).to eq(banner.id)
      expect(user.banned_reason).to eq(reason)
      expect(user.session_token).to_not eq(previous_token)
      expect(BanNotificationMailer).to have_received(:notify).with(user, banner, reason)

      moderation = Moderation.find_by(user_id: user.id, moderator_user_id: banner.id, action: 'Banned')
      expect(moderation).to be_present
      expect(moderation.reason).to eq(reason)
    end
  end

  describe '#can_flag?' do
    let(:user) { create(:user, created_at: (User::NEW_USER_DAYS + 1).days.ago, karma: 100) }

    it 'disallows new users from flagging anything' do
      new_user = create(:user, created_at: Time.current)
      story = create(:story)
      allow(story).to receive(:is_flaggable?).and_return(true)
      expect(new_user.can_flag?(story)).to be false
    end

    it 'allows flagging a flaggable story' do
      story = create(:story)
      allow(story).to receive(:is_flaggable?).and_return(true)
      expect(user.can_flag?(story)).to be true
    end

    it 'allows unvoting a currently flagged story' do
      story = create(:story)
      allow(story).to receive(:is_flaggable?).and_return(false)
      allow(story).to receive(:current_flagged?).and_return(true)
      expect(user.can_flag?(story)).to be true
    end

    it 'allows flagging a flaggable comment only with sufficient karma' do
      comment = create(:comment)
      allow(comment).to receive(:is_flaggable?).and_return(true)
      high = create(:user, created_at: (User::NEW_USER_DAYS + 1).days.ago, karma: User::MIN_KARMA_TO_FLAG)
      low = create(:user, created_at: (User::NEW_USER_DAYS + 1).days.ago, karma: User::MIN_KARMA_TO_FLAG - 1)

      expect(high.can_flag?(comment)).to be true
      expect(low.can_flag?(comment)).to be false
    end
  end

  describe '#can_invite?' do
    it 'requires invite privileges and submit ability' do
      u = create(:user, karma: 0)
      expect(u.can_invite?).to be true

      u_low = create(:user, karma: User::MIN_KARMA_TO_SUBMIT_STORIES - 1)
      expect(u_low.can_invite?).to be false

      mod = create(:user, karma: 10)
      mod.disable_invite_by_user_for_reason!(create(:user), 'test')
      expect(mod.can_invite?).to be false
    end
  end

  describe '#can_offer_suggestions?' do
    it 'requires not new and minimum karma' do
      new_user = create(:user, created_at: Time.current, karma: 100)
      expect(new_user.can_offer_suggestions?).to be false

      low = create(:user, created_at: (User::NEW_USER_DAYS + 1).days.ago, karma: User::MIN_KARMA_TO_SUGGEST - 1)
      expect(low.can_offer_suggestions?).to be false

      ok = create(:user, created_at: (User::NEW_USER_DAYS + 1).days.ago, karma: User::MIN_KARMA_TO_SUGGEST)
      expect(ok.can_offer_suggestions?).to be true
    end
  end

  describe '#can_see_invitation_requests?' do
    it 'requires can_invite and either moderator or sufficient karma' do
      base = create(:user, created_at: (User::NEW_USER_DAYS + 1).days.ago, karma: 0)
      expect(base.can_see_invitation_requests?).to be false

      mod = create(:user, created_at: (User::NEW_USER_DAYS + 1).days.ago, karma: 0, is_moderator: true)
      expect(mod.can_see_invitation_requests?).to be true

      high = create(:user, created_at: (User::NEW_USER_DAYS + 1).days.ago, karma: User::MIN_KARMA_FOR_INVITATION_REQUESTS)
      expect(high.can_see_invitation_requests?).to be true

      banned_invites = create(:user, created_at: (User::NEW_USER_DAYS + 1).days.ago, karma: 100, is_moderator: true)
      banned_invites.disable_invite_by_user_for_reason!(create(:user), 'test')
      expect(banned_invites.can_see_invitation_requests?).to be false
    end
  end

  describe '#can_submit_stories?' do
    it 'allows users at threshold and above' do
      at = create(:user, karma: User::MIN_KARMA_TO_SUBMIT_STORIES)
      low = create(:user, karma: User::MIN_KARMA_TO_SUBMIT_STORIES - 1)

      expect(at.can_submit_stories?).to be true
      expect(low.can_submit_stories?).to be false
    end
  end

  describe '#high_karma?' do
    it 'checks against threshold' do
      low = create(:user, karma: User::HIGH_KARMA_THRESHOLD - 1)
      high = create(:user, karma: User::HIGH_KARMA_THRESHOLD)
      expect(low.high_karma?).to be false
      expect(high.high_karma?).to be true
    end
  end

  describe 'token generation callbacks' do
    it 'ensures session_token, rss_token, and mailing_list_token are generated on create' do
      u = create(:user, session_token: nil, rss_token: nil, mailing_list_token: nil)
      expect(u.session_token).to be_present
      expect(u.session_token.length).to eq(60)
      expect(u.rss_token).to be_present
      expect(u.rss_token.length).to eq(60)
      expect(u.mailing_list_token).to be_present
      expect(u.mailing_list_token.length).to eq(10)
    end
  end

  describe '#comments_posted_count and #comments_deleted_count' do
    it 'reads counts from keystore' do
      user = create(:user)
      allow(Keystore).to receive(:value_for).with("user:#{user.id}:comments_posted").and_return('7')
      allow(Keystore).to receive(:value_for).with("user:#{user.id}:comments_deleted").and_return('3')
      expect(user.comments_posted_count).to eq(7)
      expect(user.comments_deleted_count).to eq(3)
    end
  end

  describe '#fetched_avatar' do
    it 'returns image bytes from gravatar and nil on error' do
      user = build(:user, email: 'user@example.com')
      sponge = double('Sponge', timeout: 3)
      response = double('Response', body: 'PNGDATA')
      allow(Sponge).to receive(:new).and_return(sponge)
      allow(sponge).to receive(:timeout=)
      allow(sponge).to receive(:fetch).and_return(response)

      expect(user.fetched_avatar(40)).to eq('PNGDATA')

      allow(sponge).to receive(:fetch).and_raise(StandardError.new('network error'))
      expect(user.fetched_avatar(40)).to be_nil
    end
  end

  describe '#refresh_counts!' do
    it 'writes story and comment counts to keystore' do
      user = create(:user)
      create_list(:story, 2, user: user)
      create(:comment, user: user, is_deleted: false)
      create_list(:comment, 2, user: user, is_deleted: true)

      expect(Keystore).to receive(:put).with("user:#{user.id}:stories_submitted", 2)
      expect(Keystore).to receive(:put).with("user:#{user.id}:comments_posted", 1)
      expect(Keystore).to receive(:put).with("user:#{user.id}:comments_deleted", 2)

      user.refresh_counts!
    end
  end

  describe '#delete! and #undelete!' do
    it 'soft deletes user, marks messages, uses invites, and can be undeleted' do
      allow(FlaggedCommenters).to receive(:new).with('90d').and_return(double(check_list_for: false))

      user = create(:user, karma: 10, email: 'orig@example.com')
      other = create(:user)
      create(:comment, user: user, score: -1)
      expect_any_instance_of(Comment).to receive(:delete_for_user).with(user).at_least(:once)

      sent = Message.create!(author_user_id: user.id, recipient_user_id: other.id, subject: 'hi', body: 'msg',
                             deleted_by_author: false, deleted_by_recipient: false)
      recv = Message.create!(author_user_id: other.id, recipient_user_id: user.id, subject: 'hi', body: 'msg',
                             deleted_by_author: false, deleted_by_recipient: false)
      inv = create(:invitation, user: user, used_at: nil)

      old_token = user.session_token
      user.delete!
      user.reload
      sent.reload
      recv.reload
      inv.reload

      expect(user.deleted_at?).to be true
      expect(user.session_token).to_not eq(old_token)
      expect(sent.deleted_by_author).to be true
      expect(recv.deleted_by_recipient).to be true
      expect(inv.used_at).to be_present

      user.undelete!
      user.reload
      expect(user.deleted_at).to be_nil
    end
  end

  describe '#disable_2fa!' do
    it 'clears the TOTP secret' do
      user = create(:user, totp_secret: 'abc')
      user.disable_2fa!
      expect(user.reload.totp_secret).to be_nil
    end
  end

  describe '#good_riddance?' do
    it 'changes email if karma is negative' do
      user = create(:user, karma: -1, email: 'real@example.com')
      user.good_riddance?
      expect(user.email).to eq("#{user.username}@lobsters.example")
    end

    it 'changes email if many recent deleted posts/comments' do
      user = create(:user, karma: 0, email: 'real@example.com')
      create_list(:comment, 4, user: user, is_deleted: true, created_at: 10.days.ago)
      user.good_riddance?
      expect(user.email).to eq("#{user.username}@lobsters.example")
    end

    it 'changes email if flagged by FlaggedCommenters' do
      user = create(:user, karma: 0, email: 'real@example.com')
      allow(FlaggedCommenters).to receive(:new).with('90d').and_return(double(check_list_for: true))
      user.good_riddance?
      expect(user.email).to eq("#{user.username}@lobsters.example")
    end

    it 'does not change email when conditions are not met' do
      user = create(:user, karma: 0, email: 'real@example.com')
      allow(FlaggedCommenters).to receive(:new).with('90d').and_return(double(check_list_for: false))
      user.good_riddance?
      expect(user.email).to eq('real@example.com')
    end
  end

  describe '#grant_moderatorship_by_user!' do
    it 'grants moderator, creates moderation and sysop hat' do
      user = create(:user, is_moderator: false)
      mod = create(:user)
      expect(user.grant_moderatorship_by_user!(mod)).to be true
      user.reload
      expect(user.is_moderator).to be true

      moderation = Moderation.find_by(user_id: user.id, moderator_user_id: mod.id, action: 'Granted moderator status')
      expect(moderation).to be_present

      hat = Hat.find_by(user_id: user.id, granted_by_user_id: mod.id, hat: 'Sysop')
      expect(hat).to be_present
    end
  end

  describe '#initiate_password_reset_for_ip' do
    it 'sets a reset token and emails a link' do
      user = create(:user, password_reset_token: nil)
      mailer = double(deliver_now: true)
      allow(PasswordResetMailer).to receive(:password_reset_link).and_return(mailer)

      user.initiate_password_reset_for_ip('127.0.0.1')
      user.reload

      expect(user.password_reset_token).to be_present
      expect(user.password_reset_token).to match(/\A\d+-[A-Za-z0-9]+\z/)
      expect(PasswordResetMailer).to have_received(:password_reset_link).with(user, '127.0.0.1')
    end
  end

  describe '#has_2fa?' do
    it 'returns true when secret present, false otherwise' do
      u1 = create(:user, totp_secret: 'x')
      u2 = create(:user, totp_secret: nil)
      expect(u1.has_2fa?).to be true
      expect(u2.has_2fa?).to be false
    end
  end

  describe '#is_wiped?' do
    it "is true when password_digest is '*'" do
      u = create(:user)
      u.update!(password_digest: '*')
      expect(u.is_wiped?).to be true
    end
  end

  describe '#mastodon_acct' do
    it 'returns acct when both username and instance are present' do
      u = create(:user, mastodon_username: 'alice', mastodon_instance: 'example.social')
      expect(u.mastodon_acct).to eq('@alice@example.social')
    end

    it 'raises when data is missing' do
      u = create(:user, mastodon_username: nil, mastodon_instance: 'example.social')
      expect { u.mastodon_acct }.to raise_error(RuntimeError)
    end
  end

  describe '#pushover!' do
    it 'sends a notification only when user key is present' do
      u_with = create(:user, pushover_user_key: 'key123')
      u_without = create(:user, pushover_user_key: nil)
      allow(Pushover).to receive(:push)

      u_with.pushover!(title: 'Hi')
      u_without.pushover!(title: 'Hi')

      expect(Pushover).to have_received(:push).with('key123', hash_including(:title)).once
    end
  end

  describe '#stories_submitted_count and #stories_deleted_count' do
    it 'reads values from keystore' do
      user = create(:user)
      allow(Keystore).to receive(:value_for).with("user:#{user.id}:stories_submitted").and_return('11')
      allow(Keystore).to receive(:value_for).with("user:#{user.id}:stories_deleted").and_return('2')
      expect(user.stories_submitted_count).to eq(11)
      expect(user.stories_deleted_count).to eq(2)
    end
  end

  describe '#to_param' do
    it 'uses username' do
      u = create(:user, username: 'paramuser')
      expect(u.to_param).to eq('paramuser')
    end
  end

  describe '#enable_invite_by_user!' do
    it 're-enables invites and records a moderation entry' do
      user = create(:user)
      mod = create(:user)
      user.disable_invite_by_user_for_reason!(mod, 'test')

      result = user.enable_invite_by_user!(mod)
      user.reload
      expect(result).to be true
      expect(user.banned_from_inviting?).to be false

      moderation = Moderation.find_by(user_id: user.id, moderator_user_id: mod.id, action: 'Enabled invitations')
      expect(moderation).to be_present
    end
  end

  describe '#inbox_count' do
    it 'counts only unread notifications' do
      u = create(:user)
      create_list(:notification, 3, user: u, read_at: nil)
      create_list(:notification, 2, user: u, read_at: Time.current)
      expect(u.inbox_count).to eq(3)
    end
  end

  describe 'scopes' do
    it '.active returns only active users' do
      active = create(:user)
      banned = create(:user, banned_at: Time.current)
      deleted = create(:user, deleted_at: Time.current)
      expect(User.active).to include(active)
      expect(User.active).to_not include(banned)
      expect(User.active).to_not include(deleted)
    end
  end

  describe 'settings validations' do
    it 'validates color scheme and contrast inclusion' do
      valid = build(:user, prefers_color_scheme: 'light', prefers_contrast: 'high')
      invalid = build(:user, prefers_color_scheme: 'neon', prefers_contrast: 'ultra')
      expect(valid).to be_valid
      expect(invalid).to_not be_valid
      expect(invalid.errors[:prefers_color_scheme]).to be_present
      expect(invalid.errors[:prefers_contrast]).to be_present
    end
  end
end
