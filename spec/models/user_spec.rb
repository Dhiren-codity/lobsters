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
    it 'returns the expected username regex string' do
      expect(User.username_regex_s).to eq('/^[A-Za-z0-9][A-Za-z0-9_-]{0,24}$/')
    end
  end

  describe '#as_json' do
    it 'serializes non-admin including karma and optional fields' do
      inviter = create(:user, username: 'username774')
      u = create(
        :user,
        invited_by_user: inviter,
        about: 'hello world',
        homepage: 'https://lobste.rs',
        github_username: 'ghuser',
        mastodon_username: 'alice',
        mastodon_instance: 'fosstodon.org',
        is_admin: false
      )

      h = u.as_json
      expect(h[:username]).to eq(u.username)
      expect(h[:karma]).to eq(u.karma)
      expect(h[:homepage]).to eq('https://lobste.rs')
      expect(h[:invited_by_user]).to eq('username774')
      expect(h[:github_username]).to eq('ghuser')
      expect(h[:mastodon_username]).to eq('alice')
      expect(h[:avatar_url]).to include("/avatars/#{u.username}-100.png")
      expect(h).to have_key(:about)
    end

    it 'omits karma for admin users' do
      u = create(:user, is_admin: true)
      h = u.as_json
      expect(h).not_to have_key(:karma)
    end
  end

  describe '#authenticate_totp' do
    it 'verifies a correct code and rejects an incorrect one' do
      secret = ROTP::Base32.random
      user = create(:user, totp_secret: secret)
      totp = ROTP::TOTP.new(secret)
      code = totp.now

      expect(user.authenticate_totp(code)).to be_truthy
      expect(user.authenticate_totp('000000')).to be_falsey
    end
  end

  describe '#avatar_path and #avatar_url' do
    it 'return expected path and url for default size' do
      user = create(:user, username: 'alice')
      expect(user.avatar_path).to include('/avatars/alice-100.png')
      expect(user.avatar_url).to include('/avatars/alice-100.png')
    end

    it 'allow custom sizes' do
      user = create(:user, username: 'bob')
      expect(user.avatar_path(42)).to include('/avatars/bob-42.png')
      expect(user.avatar_url(42)).to include('/avatars/bob-42.png')
    end
  end

  describe '#disable_invite_by_user_for_reason! and #enable_invite_by_user!' do
    it 'disables and re-enables invitations and records moderation and message' do
      disabler = create(:user)
      user = create(:user)

      expect do
        expect(user.disable_invite_by_user_for_reason!(disabler, 'too many invites')).to be true
      end.to change { Moderation.count }.by(1).and change { Message.count }.by(1)

      user.reload
      expect(user.banned_from_inviting?).to be true
      expect(user.disabled_invite_by_user_id).to eq(disabler.id)
      expect(user.disabled_invite_reason).to eq('too many invites')

      msg = Message.order(:id).last
      expect(msg.recipient_user_id).to eq(user.id)
      expect(msg.author_user_id).to eq(disabler.id)
      expect(msg.subject).to eq('Your invite privileges have been revoked')
      expect(msg.body).to include('too many invites')

      mod = Moderation.order(:id).last
      expect(mod.user_id).to eq(user.id)
      expect(mod.moderator_user_id).to eq(disabler.id)
      expect(mod.action).to eq('Disabled invitations')
      expect(mod.reason).to eq('too many invites')

      expect do
        expect(user.enable_invite_by_user!(disabler)).to be true
      end.to change { Moderation.count }.by(1)

      user.reload
      expect(user.banned_from_inviting?).to be false
      expect(user.disabled_invite_by_user_id).to be_nil
      expect(user.disabled_invite_reason).to be_nil

      mod2 = Moderation.order(:id).last
      expect(mod2.action).to eq('Enabled invitations')
      expect(mod2.user_id).to eq(user.id)
    end
  end

  describe '#ban_by_user_for_reason!' do
    it 'bans and deletes a user, notifies, and records moderation' do
      banner = create(:user)
      user = create(:user)
      mail_double = double('mailer', deliver_now: true)
      expect(BanNotificationMailer).to receive(:notify).with(user, banner, 'bad').and_return(mail_double)

      expect do
        expect(user.ban_by_user_for_reason!(banner, 'bad')).to be true
      end.to change { Moderation.count }.by(1)

      user.reload
      expect(user.is_banned?).to be true
      expect(user.deleted_at?).to be true
      expect(user.banned_by_user_id).to eq(banner.id)
      expect(user.banned_reason).to eq('bad')

      mod = Moderation.order(:id).last
      expect(mod.user_id).to eq(user.id)
      expect(mod.moderator_user_id).to eq(banner.id)
      expect(mod.action).to eq('Banned')
      expect(mod.reason).to eq('bad')
    end
  end

  describe '#can_invite?' do
    it 'requires not banned from inviting and submit stories ability' do
      user = create(:user, karma: 0)
      expect(user.can_invite?).to be true

      # too low karma
      user.update!(karma: User::MIN_KARMA_TO_SUBMIT_STORIES - 1)
      expect(user.can_invite?).to be false

      # disabled invites
      mod = create(:user)
      user.update!(karma: 0)
      user.disable_invite_by_user_for_reason!(mod, 'stop')
      expect(user.can_invite?).to be false
    end
  end

  describe '#can_offer_suggestions?' do
    it 'considers account age and karma' do
      old_user = create(:user, created_at: (User::NEW_USER_DAYS + 1).days.ago, karma: 9)
      expect(old_user.can_offer_suggestions?).to be false

      old_user.update!(karma: 10)
      expect(old_user.can_offer_suggestions?).to be true

      new_user = create(:user, created_at: Time.current, karma: 100)
      expect(new_user.can_offer_suggestions?).to be false
    end
  end

  describe '#can_see_invitation_requests?' do
    it 'allows moderators regardless of karma if can_invite' do
      u = create(:user, is_moderator: true, karma: -3)
      expect(u.can_invite?).to be true
      expect(u.can_see_invitation_requests?).to be true
    end

    it 'requires sufficient karma for non-moderators and can_invite' do
      u = create(:user, karma: User::MIN_KARMA_FOR_INVITATION_REQUESTS - 1)
      expect(u.can_see_invitation_requests?).to be false

      u.update!(karma: User::MIN_KARMA_FOR_INVITATION_REQUESTS)
      expect(u.can_see_invitation_requests?).to be true

      # if banned from inviting then false
      mod = create(:user)
      u.disable_invite_by_user_for_reason!(mod, 'no')
      expect(u.can_see_invitation_requests?).to be false
    end
  end

  describe '#can_submit_stories?' do
    it 'enforces minimum karma threshold' do
      u = create(:user, karma: User::MIN_KARMA_TO_SUBMIT_STORIES)
      expect(u.can_submit_stories?).to be true

      u.update!(karma: User::MIN_KARMA_TO_SUBMIT_STORIES - 1)
      expect(u.can_submit_stories?).to be false
    end
  end

  describe '#high_karma?' do
    it 'reflects threshold' do
      u = create(:user, karma: User::HIGH_KARMA_THRESHOLD - 1)
      expect(u.high_karma?).to be false
      u.update!(karma: User::HIGH_KARMA_THRESHOLD)
      expect(u.high_karma?).to be true
    end
  end

  describe 'tokens and callbacks' do
    it 'rolls session token before save if blank' do
      u = build(:user, session_token: nil, password: 'pw')
      expect(u.session_token).to be_nil
      u.save!
      expect(u.session_token).to be_present
      expect(u.session_token.length).to be >= 10
    end

    it 'creates rss and mailing list tokens on create' do
      u = build(:user, rss_token: nil, mailing_list_token: nil)
      expect(u.valid?).to be true
      u.save!
      expect(u.rss_token).to be_present
      expect(u.mailing_list_token).to be_present
      expect(u.rss_token.length).to be >= 20
      expect(u.mailing_list_token.length).to be >= 6
    end
  end

  describe '#refresh_counts!' do
    it 'updates keystore counts for comments' do
      u = create(:user)
      s = create(:story, user: create(:user))
      create(:comment, user: u, story: s, is_deleted: false)
      create(:comment, user: u, story: s, is_deleted: true)
      create(:comment, user: u, story: s, is_deleted: true)

      u.refresh_counts!

      expect(u.comments_posted_count).to eq(1)
      expect(u.comments_deleted_count).to eq(2)
    end
  end

  describe '#undelete!' do
    it 'restores a deleted user' do
      u = create(:user, deleted_at: Time.current)
      u.undelete!
      expect(u.reload.deleted_at).to be_nil
    end
  end

  describe '#disable_2fa! and #has_2fa?' do
    it 'clears totp_secret and reflects presence' do
      u = create(:user, totp_secret: 'SECRET')
      expect(u.has_2fa?).to be true
      u.disable_2fa!
      expect(u.reload.has_2fa?).to be false
    end
  end

  describe '#grant_moderatorship_by_user!' do
    it 'grants moderator, creates moderation and hat' do
      admin = create(:user)
      u = create(:user)
      expect do
        expect(u.grant_moderatorship_by_user!(admin)).to be true
      end.to change { Moderation.count }.by(1).and change { Hat.count }.by(1)

      u.reload
      expect(u.is_moderator).to be true
      hat = Hat.order(:id).last
      expect(hat.user_id).to eq(u.id)
      expect(hat.hat).to eq('Sysop')
      expect(hat.granted_by_user_id).to eq(admin.id)
    end
  end

  describe '#initiate_password_reset_for_ip' do
    it 'sets a token and sends an email' do
      u = create(:user)
      mail_double = double('mailer', deliver_now: true)
      expect(PasswordResetMailer).to receive(:password_reset_link).with(u, '127.0.0.1').and_return(mail_double)
      u.initiate_password_reset_for_ip('127.0.0.1')
      expect(u.reload.password_reset_token).to match(/\A\d{10}-[A-Za-z0-9]{30}\z/)
    end
  end

  describe '#is_wiped?' do
    it 'detects wiped users' do
      u = create(:user)
      expect(u.is_wiped?).to be false
      u.update_column(:password_digest, '*')
      expect(u.is_wiped?).to be true
    end
  end

  describe '#roll_session_token' do
    it 'generates a new random token' do
      u = create(:user)
      old = u.session_token
      u.roll_session_token
      expect(u.session_token).to be_present
      expect(u.session_token).not_to eq(old)
      expect(u.session_token.length).to be >= 20
    end
  end

  describe '#linkified_about' do
    it 'returns rendered HTML' do
      u = create(:user, about: 'hello')
      expect(Markdowner).to receive(:to_html).with('hello').and_return('<p>hello</p>')
      expect(u.linkified_about).to eq('<p>hello</p>')
    end
  end

  describe '#mastodon_acct' do
    it 'returns acct when configured and raises otherwise' do
      u = create(:user, mastodon_username: 'alice', mastodon_instance: 'fosstodon.org')
      expect(u.mastodon_acct).to eq('@alice@fosstodon.org')

      u2 = create(:user, mastodon_username: nil, mastodon_instance: 'fosstodon.org')
      expect { u2.mastodon_acct }.to raise_error(RuntimeError)
    end
  end

  describe '#most_common_story_tag' do
    it "returns the most frequently used tag on user's non-deleted stories" do
      u = create(:user)
      t1 = create(:tag)
      t2 = create(:tag)
      create(:story, user: u, tags: [t1])
      create(:story, user: u, tags: [t1])
      create(:story, user: u, tags: [t2])
      create(:story, user: u, tags: [t2], is_deleted: true)

      expect(u.most_common_story_tag).to eq(t1)
    end
  end

  describe '#pushover!' do
    it 'sends a push when user has a key and does nothing otherwise' do
      params = { title: 'Hello', message: 'World' }
      u = create(:user, settings: { 'pushover_user_key' => 'KEY123' })
      expect(Pushover).to receive(:push).with('KEY123', params)
      u.pushover!(params)

      u2 = create(:user, settings: { 'pushover_user_key' => nil })
      expect(Pushover).not_to receive(:push)
      u2.pushover!(params)
    end
  end

  describe '#inbox_count' do
    it 'counts unread notifications' do
      u = create(:user)
      s = create(:story, user: create(:user))
      c = create(:comment, user: create(:user), story: s)
      create(:notification, user: u, notifiable: c, read_at: nil)
      create(:notification, user: u, notifiable: c, read_at: nil)
      create(:notification, user: u, notifiable: c, read_at: Time.current)
      expect(u.inbox_count).to eq(2)
    end
  end

  describe '#votes_for_others' do
    it "returns only votes on others' content in descending id order" do
      u = create(:user)
      other = create(:user)

      story_by_other = create(:story, user: other)
      story_by_self = create(:story, user: u)
      comment_by_other = create(:comment, user: other, story: story_by_other)
      comment_by_self = create(:comment, user: u, story: story_by_other)

      v1 = create(:vote, user: u, story: story_by_other, vote: 1)
      create(:vote, user: u, story: story_by_self, vote: 1)
      v3 = create(:vote, user: u, comment: comment_by_other, story: comment_by_other.story, vote: 1)
      create(:vote, user: u, comment: comment_by_self, story: comment_by_self.story, vote: 1)

      result = u.votes_for_others.to_a
      expect(result.map(&:id)).to eq([v3.id, v1.id])
    end
  end

  describe '#to_param' do
    it 'uses username as param' do
      u = create(:user, username: 'charlie')
      expect(u.to_param).to eq('charlie')
    end
  end
end
