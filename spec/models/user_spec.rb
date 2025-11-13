# frozen_string_literal: true

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
    expect(build(:user, email: "#{'a' * 95}@example.com")).to_not be_valid

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

  describe '.active' do
    it 'returns only active (not banned and not deleted) users' do
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

  describe '.username_regex_s' do
    it 'returns a stringified regex for usernames' do
      str = User.username_regex_s
      expect(str).to start_with('/^')
      expect(str).to end_with('$/')
      expect(str).to include('A-Za-z0-9')
      expect(str).to include('{0,24}')
    end
  end

  describe '#as_json' do
    it 'includes karma for non-admins and omits for admins' do
      inviter = create(:user)
      non_admin = create(:user, is_admin: false, about: 'hi', invited_by_user: inviter)
      admin = create(:user, is_admin: true, about: 'hi', invited_by_user: inviter)

      non_admin_json = non_admin.as_json
      admin_json = admin.as_json

      expect(non_admin_json).to include(:karma)
      expect(admin_json).not_to include(:karma)

      expect(non_admin_json[:about]).to eq(non_admin.linkified_about)
      expect(non_admin_json[:avatar_url]).to include("/avatars/#{non_admin.username}-100.png")
      expect(non_admin_json[:invited_by_user]).to eq(inviter.username)
      expect(non_admin_json).to include(:homepage)
      expect(non_admin_json).not_to include(:email)
    end

    it 'includes github and mastodon usernames only when present' do
      user = create(:user, github_username: nil, mastodon_username: nil)
      expect(user.as_json).not_to include(:github_username)
      expect(user.as_json).not_to include(:mastodon_username)

      user.update!(github_username: 'ghuser', mastodon_username: 'mduser', mastodon_instance: 'fosstodon.org')
      expect(user.as_json).to include(github_username: 'ghuser', mastodon_username: 'mduser')
    end
  end

  describe '#authenticate_totp' do
    it 'verifies a valid code and rejects an invalid code' do
      secret = ROTP::Base32.random
      user = create(:user, totp_secret: secret)
      totp = ROTP::TOTP.new(secret)

      expect(user.authenticate_totp(totp.now)).to be_truthy
      expect(user.authenticate_totp('000000')).to be_falsey
    end
  end

  describe '#avatar_path' do
    it 'returns a path to the avatar size variant' do
      user = create(:user, username: 'alice')
      expect(user.avatar_path(80)).to include('/avatars/alice-80.png')
    end
  end

  describe '#avatar_url' do
    it 'returns a URL to the avatar size variant' do
      user = create(:user, username: 'bob')
      expect(user.avatar_url(120)).to include('/avatars/bob-120.png')
    end
  end

  describe '#disable_invite_by_user_for_reason!' do
    it 'disables invites, creates a message and moderation, and returns true' do
      mod = create(:user)
      target = create(:user)
      expect do
        expect(target.disable_invite_by_user_for_reason!(mod, 'spamming')).to be true
      end.to change { Message.where(recipient_user_id: target.id).count }.by(1)
                                                                         .and change {
                                                                                Moderation.where(user_id: target.id,
                                                                                                 action: 'Disabled invitations').count
                                                                              }.by(1)

      target.reload
      expect(target.disabled_invite_at).to be_present
      expect(target.disabled_invite_by_user_id).to eq(mod.id)
      expect(target.disabled_invite_reason).to eq('spamming')
    end
  end

  describe '#enable_invite_by_user!' do
    it 'clears invite bans and creates a moderation record' do
      mod = create(:user)
      target = create(:user, disabled_invite_at: Time.current, disabled_invite_by_user: mod,
                             disabled_invite_reason: 'bad')
      expect do
        expect(target.enable_invite_by_user!(mod)).to be true
      end.to change { Moderation.where(user_id: target.id, action: 'Enabled invitations').count }.by(1)

      target.reload
      expect(target.disabled_invite_at).to be_nil
      expect(target.disabled_invite_by_user_id).to be_nil
      expect(target.disabled_invite_reason).to be_nil
    end
  end

  describe '#ban_by_user_for_reason!' do
    it 'bans and deletes the user, sends a notification, and logs moderation' do
      banner = create(:user)
      user = create(:user)

      mail_double = double(deliver_now: true)
      expect(BanNotificationMailer).to receive(:notify).and_return(mail_double)

      expect do
        expect(user.ban_by_user_for_reason!(banner, 'abuse')).to be true
      end.to change { Moderation.where(user_id: user.id, action: 'Banned').count }.by(1)

      user.reload
      expect(user.banned_at).to be_present
      expect(user.banned_by_user_id).to eq(banner.id)
      expect(user.deleted_at).to be_present
    end

    it 'does not attempt to notify if already deleted' do
      banner = create(:user)
      user = create(:user, deleted_at: Time.current)
      expect(BanNotificationMailer).not_to receive(:notify)
      expect(user.ban_by_user_for_reason!(banner, 'abuse')).to be true
    end
  end

  describe '#banned_from_inviting?' do
    it 'returns true if disabled_invite_at is set' do
      user = create(:user, disabled_invite_at: Time.current)
      expect(user.banned_from_inviting?).to be true
      user = create(:user, disabled_invite_at: nil)
      expect(user.banned_from_inviting?).to be false
    end
  end

  describe '#can_submit_stories?' do
    it 'requires minimum karma to submit stories' do
      expect(create(:user, karma: -5).can_submit_stories?).to be false
      expect(create(:user, karma: -4).can_submit_stories?).to be true
      expect(create(:user, karma: 0).can_submit_stories?).to be true
    end
  end

  describe '#can_invite?' do
    it 'requires submit permission and no invite ban' do
      u1 = create(:user, karma: -5)
      expect(u1.can_invite?).to be false

      u2 = create(:user, karma: 0, disabled_invite_at: Time.current)
      expect(u2.can_invite?).to be false

      u3 = create(:user, karma: 0, disabled_invite_at: nil)
      expect(u3.can_invite?).to be true
    end
  end

  describe '#can_offer_suggestions?' do
    it 'requires not-new and minimum karma' do
      new_user = create(:user, karma: 100, created_at: Time.current)
      expect(new_user.can_offer_suggestions?).to be false

      low_karma_old = create(:user, karma: 5, created_at: (User::NEW_USER_DAYS + 1).days.ago)
      expect(low_karma_old.can_offer_suggestions?).to be false

      good = create(:user, karma: 10, created_at: (User::NEW_USER_DAYS + 1).days.ago)
      expect(good.can_offer_suggestions?).to be true
    end
  end

  describe '#can_see_invitation_requests?' do
    it 'requires invite permission and moderator or high karma' do
      mod = create(:user, is_moderator: true, karma: -4)
      expect(mod.can_see_invitation_requests?).to be true

      low = create(:user, is_moderator: false, karma: User::MIN_KARMA_FOR_INVITATION_REQUESTS - 1)
      expect(low.can_see_invitation_requests?).to be false

      high = create(:user, is_moderator: false, karma: User::MIN_KARMA_FOR_INVITATION_REQUESTS)
      expect(high.can_see_invitation_requests?).to be true

      banned_invites = create(:user, karma: 100, disabled_invite_at: Time.current)
      expect(banned_invites.can_see_invitation_requests?).to be false
    end
  end

  describe '#high_karma?' do
    it 'returns true when karma >= threshold' do
      expect(create(:user, karma: User::HIGH_KARMA_THRESHOLD).high_karma?).to be true
    end

    it 'returns false when karma below threshold' do
      expect(create(:user, karma: User::HIGH_KARMA_THRESHOLD - 1).high_karma?).to be false
    end
  end

  describe 'session and tokens on create' do
    it 'generates session_token if blank before save' do
      user = build(:user, session_token: nil)
      user.save!
      expect(user.session_token).to be_present
      expect(user.session_token.length).to be > 10
    end

    it 'generates rss and mailing list tokens on create' do
      user = create(:user, rss_token: nil, mailing_list_token: nil)
      expect(user.rss_token).to be_present
      expect(user.rss_token.length).to be >= 10
      expect(user.mailing_list_token).to be_present
      expect(user.mailing_list_token.length).to be >= 10
    end
  end

  describe '#fetched_avatar' do
    it 'returns body when Sponge fetch succeeds' do
      user = create(:user, email: 'u@example.com')
      fetch_double = double(body: 'imgbytes')
      sponge = double
      allow(sponge).to receive(:timeout=)
      allow(sponge).to receive(:fetch).and_return(fetch_double)
      allow(Sponge).to receive(:new).and_return(sponge)

      expect(user.fetched_avatar(50)).to eq('imgbytes')
    end

    it 'returns nil on exceptions' do
      user = create(:user, email: 'u@example.com')
      sponge = double
      allow(sponge).to receive(:timeout=)
      allow(sponge).to receive(:fetch).and_raise(StandardError.new('boom'))
      allow(Sponge).to receive(:new).and_return(sponge)

      expect(user.fetched_avatar(50)).to be_nil
    end
  end

  describe '#refresh_counts!' do
    it 'updates keystore-based counts for comments and stories' do
      user = create(:user)
      create(:story, user: user)
      create(:comment, user: user, is_deleted: false)
      create(:comment, user: user, is_deleted: true)

      user.refresh_counts!

      expect(user.stories_submitted_count).to eq(1)
      expect(user.comments_posted_count).to eq(1)
      expect(user.comments_deleted_count).to eq(1)
    end
  end

  describe '#grant_moderatorship_by_user!' do
    it 'grants moderator status, creates a moderation and hat' do
      granter = create(:user)
      target = create(:user, is_moderator: false)

      expect do
        expect(target.grant_moderatorship_by_user!(granter)).to be true
      end.to change { Moderation.where(user_id: target.id, action: 'Granted moderator status').count }.by(1)
                                                                                                      .and change {
                                                                                                             Hat.where(
                                                                                                               user_id: target.id, hat: 'Sysop'
                                                                                                             ).count
                                                                                                           }.by(1)

      expect(target.reload.is_moderator).to be true
    end
  end

  describe '#initiate_password_reset_for_ip' do
    it 'sets a password reset token and sends email' do
      user = create(:user, password_reset_token: nil)
      mail_double = double(deliver_now: true)
      expect(PasswordResetMailer).to receive(:password_reset_link).with(user, '1.2.3.4').and_return(mail_double)

      expect do
        user.initiate_password_reset_for_ip('1.2.3.4')
      end.to change { user.reload.password_reset_token }.from(nil)

      expect(user.password_reset_token).to be_present
      expect(user.password_reset_token.length).to be > 30
    end
  end

  describe '#has_2fa? and #disable_2fa!' do
    it 'reports 2FA presence and can disable it' do
      secret = ROTP::Base32.random
      user = create(:user, totp_secret: secret)
      expect(user.has_2fa?).to be true

      user.disable_2fa!
      expect(user.reload.has_2fa?).to be false
      expect(user.totp_secret).to be_nil
    end
  end

  describe '#roll_session_token' do
    it 'changes the session token' do
      user = create(:user)
      old = user.session_token
      user.roll_session_token
      expect(user.session_token).not_to eq(old)
      expect(user.session_token.length).to be > 30
    end
  end

  describe '#linkified_about' do
    it 'delegates to Markdowner.to_html' do
      user = create(:user, about: 'hello')
      expect(Markdowner).to receive(:to_html).with('hello').and_return('<p>hello</p>')
      expect(user.linkified_about).to eq('<p>hello</p>')
    end
  end

  describe '#mastodon_acct' do
    it 'returns a full acct string when both fields present' do
      user = create(:user, mastodon_username: 'alice', mastodon_instance: 'fosstodon.org')
      expect(user.mastodon_acct).to eq('@alice@fosstodon.org')
    end

    it 'raises when required fields are missing' do
      user = create(:user, mastodon_username: nil, mastodon_instance: 'fosstodon.org')
      expect { user.mastodon_acct }.to raise_error(RuntimeError)
    end
  end

  describe '#pushover!' do
    it 'pushes when a user key is present' do
      user = create(:user, pushover_user_key: 'abc123')
      expect(Pushover).to receive(:push).with('abc123', hash_including(title: 'Hello'))
      user.pushover!(title: 'Hello', message: 'World')
    end

    it 'does nothing when no user key' do
      user = create(:user, pushover_user_key: nil)
      expect(Pushover).not_to receive(:push)
      user.pushover!(title: 'Hello')
    end
  end

  describe '#to_param' do
    it 'returns the username' do
      user = create(:user, username: 'paramuser')
      expect(user.to_param).to eq('paramuser')
    end
  end

  describe '#inbox_count' do
    it 'counts unread notifications only' do
      user = create(:user)
      create(:notification, user: user, read_at: nil)
      create(:notification, user: user, read_at: nil)
      create(:notification, user: user, read_at: Time.current)

      expect(user.inbox_count).to eq(2)
    end
  end

  describe '#votes_for_others' do
    it 'returns only votes on content not authored by the voter' do
      voter = create(:user)
      other = create(:user)

      other_story = create(:story, user: other)
      own_story = create(:story, user: voter)

      other_comment = create(:comment, user: other, story: other_story)
      own_comment = create(:comment, user: voter, story: own_story)

      v1 = create(:vote, user: voter, story: other_story, vote: 1)
      v2 = create(:vote, user: voter, comment: other_comment, vote: 1)
      create(:vote, user: voter, story: own_story, vote: 1)
      create(:vote, user: voter, comment: own_comment, vote: 1)

      ids = voter.votes_for_others.pluck(:id)
      expect(ids).to match_array([v1.id, v2.id])
    end
  end
end
