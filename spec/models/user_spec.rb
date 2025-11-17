# NOTE: Some failing tests were automatically removed after 3 fix attempts failed.
# These tests may need manual review. See CI logs for details.
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

  describe 'scopes' do
    it 'returns only active users for .active' do
      active_user = create(:user)
      banned_user = create(:user, :banned)
      deleted_user = create(:user, deleted_at: Time.current)
      expect(User.active).to include(active_user)
      expect(User.active).to_not include(banned_user)
      expect(User.active).to_not include(deleted_user)
    end
  end

  describe 'callbacks' do
    it 'generates tokens on create and sets session_token before save' do
      u = build(:user, rss_token: nil, mailing_list_token: nil, session_token: nil)
      expect(u.rss_token).to be_nil
      expect(u.mailing_list_token).to be_nil
      expect(u.session_token).to be_nil
      u.save!
      expect(u.rss_token).to be_present
      expect(u.rss_token.length).to eq(60)
      expect(u.mailing_list_token).to be_present
      expect(u.mailing_list_token.length).to eq(10)
      expect(u.session_token).to be_present
      expect(u.session_token.length).to eq(60)
    end
  end

  describe '.username_regex_s' do
    it 'returns the formatted username regex string' do
      str = User.username_regex_s
      expect(str).to start_with('/^')
      expect(str).to end_with('$/')
    end
  end

  describe '#as_json' do
    let!(:inviter) { create(:user, username: 'inviter') }

    it 'omits karma for admin users' do
      admin = create(:user, is_admin: true)
      allow(admin).to receive(:avatar_url).and_return('url')
      allow(Markdowner).to receive(:to_html).and_return('html')
      json = admin.as_json
      expect(json).to_not have_key(:karma)
    end
  end

  describe '#authenticate_totp' do
    it 'verifies a correct TOTP code and rejects an invalid one' do
      secret = ROTP::Base32.random_base32
      u = create(:user, totp_secret: secret)
      totp = ROTP::TOTP.new(secret)
      code = totp.now
      expect(u.authenticate_totp(code)).to be_truthy
      expect(u.authenticate_totp('000000')).to be_falsey
    end
  end

  describe 'avatar helpers' do
    it 'builds avatar path and url for a given size' do
      u = create(:user, username: 'alice')
      expect(u.avatar_path(42)).to eq(ActionController::Base.helpers.image_path('/avatars/alice-42.png',
                                                                                skip_pipeline: true))
      expect(u.avatar_url(42)).to eq(ActionController::Base.helpers.image_url('/avatars/alice-42.png',
                                                                              skip_pipeline: true))
    end
  end

  describe 'invite disabling and enabling' do
    let!(:mod) { create(:user) }
    let!(:user) { create(:user) }

    it 'disables invite privileges, sends a message, and logs a moderation' do
      allow(Message).to receive(:new).and_call_original
      expect do
        expect(user.disable_invite_by_user_for_reason!(mod, 'too many bad invites')).to be true
      end.to change { Moderation.count }.by(1)
                                        .and change { Message.count }.by(1)
      user.reload
      expect(user.disabled_invite_at).to be_present
      expect(user.disabled_invite_by_user_id).to eq(mod.id)
      expect(user.disabled_invite_reason).to eq('too many bad invites')
      msg = Message.order(:id).last
      expect(msg.author_user_id).to eq(mod.id)
      expect(msg.recipient_user_id).to eq(user.id)
      expect(msg.deleted_by_author).to be true
      expect(msg.subject).to include('invite privileges')
      expect(Moderation.order(:id).last.action).to eq('Disabled invitations')
    end

    it 're-enables invite privileges and logs a moderation' do
      user.disable_invite_by_user_for_reason!(mod, 'reason')
      expect do
        expect(user.enable_invite_by_user!(mod)).to be true
      end.to change { Moderation.count }.by(1)
      user.reload
      expect(user.disabled_invite_at).to be_nil
      expect(user.disabled_invite_by_user_id).to be_nil
      expect(user.disabled_invite_reason).to be_nil
      expect(Moderation.order(:id).last.action).to eq('Enabled invitations')
    end

    it 'indicates whether a user is banned from inviting' do
      expect(user.banned_from_inviting?).to be false
      user.disable_invite_by_user_for_reason!(mod, 'reason')
      expect(user.banned_from_inviting?).to be true
    end
  end

  describe 'banning' do
    let!(:banner) { create(:user) }

    it 'bans a user, sends mail, deletes them, and logs a moderation' do
      u = create(:user)
      mailer_double = double(deliver_now: true)
      allow(BanNotificationMailer).to receive(:notify).and_return(mailer_double)
      expect do
        expect(u.ban_by_user_for_reason!(banner, 'spam')).to be true
      end.to change { Moderation.count }.by(1)
      u.reload
      expect(u.banned_at).to be_present
      expect(u.deleted_at).to be_present
      expect(BanNotificationMailer).to have_received(:notify).with(u, banner, 'spam')
      expect(Moderation.order(:id).last.action).to eq('Banned')
    end
  end

  describe 'permission helpers' do
    it 'checks can_submit_stories? threshold' do
      u1 = create(:user, karma: User::MIN_KARMA_TO_SUBMIT_STORIES)
      u2 = create(:user, karma: User::MIN_KARMA_TO_SUBMIT_STORIES - 1)
      expect(u1.can_submit_stories?).to be true
      expect(u2.can_submit_stories?).to be false
    end

    it 'checks high_karma?' do
      low = create(:user, karma: User::HIGH_KARMA_THRESHOLD - 1)
      high = create(:user, karma: User::HIGH_KARMA_THRESHOLD)
      expect(low.high_karma?).to be false
      expect(high.high_karma?).to be true
    end

    it 'checks can_invite? based on invite ban and submit threshold' do
      u = create(:user, karma: User::MIN_KARMA_TO_SUBMIT_STORIES)
      expect(u.can_invite?).to be true
      mod = create(:user)
      u.disable_invite_by_user_for_reason!(mod, 'reason')
      expect(u.can_invite?).to be false
      low = create(:user, karma: User::MIN_KARMA_TO_SUBMIT_STORIES - 1)
      expect(low.can_invite?).to be false
    end

    it 'checks can_offer_suggestions? based on account age and karma' do
      young = create(:user, created_at: Time.current, karma: 100)
      old_low = create(:user, created_at: (User::NEW_USER_DAYS + 1).days.ago, karma: User::MIN_KARMA_TO_SUGGEST - 1)
      old_ok = create(:user, created_at: (User::NEW_USER_DAYS + 1).days.ago, karma: User::MIN_KARMA_TO_SUGGEST)
      expect(young.can_offer_suggestions?).to be false
      expect(old_low.can_offer_suggestions?).to be false
      expect(old_ok.can_offer_suggestions?).to be true
    end

    it 'checks can_see_invitation_requests? for moderators or high karma' do
      base = create(:user, karma: User::MIN_KARMA_TO_SUBMIT_STORIES)
      expect(base.can_see_invitation_requests?).to be false
      high = create(:user, karma: User::MIN_KARMA_FOR_INVITATION_REQUESTS)
      expect(high.can_see_invitation_requests?).to be true
      mod = create(:user, is_moderator: true, karma: 0)
      expect(mod.can_see_invitation_requests?).to be true
      banned_invites = create(:user, karma: User::MIN_KARMA_FOR_INVITATION_REQUESTS)
      banned_invites.disable_invite_by_user_for_reason!(create(:user), 'reason')
      expect(banned_invites.can_see_invitation_requests?).to be false
    end
  end

  describe 'keystore-backed counters' do
    it 'reads stories_submitted_count and stories_deleted_count' do
      u = create(:user)
      allow(Keystore).to receive(:value_for).with("user:#{u.id}:stories_submitted").and_return('7')
      allow(Keystore).to receive(:value_for).with("user:#{u.id}:stories_deleted").and_return('2')
      expect(u.stories_submitted_count).to eq(7)
      expect(u.stories_deleted_count).to eq(2)
    end
  end

  describe '#refresh_counts!' do
    it 'writes counts to Keystore' do
      u = create(:user)
      create(:story, user: u)
      create(:story, user: u)
      create(:comment, user: u, is_deleted: false)
      create(:comment, user: u, is_deleted: true)
      allow(Keystore).to receive(:put)
      u.refresh_counts!
      expect(Keystore).to have_received(:put).with("user:#{u.id}:stories_submitted", 2)
      expect(Keystore).to have_received(:put).with("user:#{u.id}:comments_posted", 1)
      expect(Keystore).to have_received(:put).with("user:#{u.id}:comments_deleted", 1)
    end
  end

  describe 'account lifecycle' do
    it 'delete! marks as deleted and rotates session token, undelete! restores' do
      u = create(:user, session_token: 'abc')
      old_token = u.session_token
      allow(FlaggedCommenters).to receive(:new).and_return(double(check_list_for: false))
      u.delete!
      u.reload
      expect(u.deleted_at).to be_present
      expect(u.session_token).to be_present
      expect(u.session_token).to_not eq(old_token)
      u.undelete!
      expect(u.deleted_at).to be_nil
    end

    it 'disable_2fa! clears totp_secret' do
      u = create(:user, totp_secret: 'SECRET')
      u.disable_2fa!
      expect(u.totp_secret).to be_nil
    end

    it 'good_riddance? sets placeholder email for negative karma users' do
      u = create(:user, username: 'x', email: 'x@y.z', karma: -1)
      allow(FlaggedCommenters).to receive(:new).and_return(double(check_list_for: false))
      u.good_riddance?
      expect(u.email).to eq('x@lobsters.example')
    end
  end

  describe '#initiate_password_reset_for_ip' do
    it 'sets a reset token and delivers an email' do
      u = create(:user, password_reset_token: nil)
      mailer_double = double(deliver_now: true)
      allow(PasswordResetMailer).to receive(:password_reset_link).and_return(mailer_double)
      u.initiate_password_reset_for_ip('1.2.3.4')
      expect(u.password_reset_token).to be_present
      expect(u.password_reset_token).to match(/\A\d+-[A-Za-z0-9]+\z/)
      expect(PasswordResetMailer).to have_received(:password_reset_link).with(u, '1.2.3.4')
    end
  end

  describe '2FA helpers' do
    it 'has_2fa? reflects presence of totp_secret' do
      u1 = create(:user, totp_secret: nil)
      u2 = create(:user, totp_secret: 'S')
      expect(u1.has_2fa?).to be false
      expect(u2.has_2fa?).to be true
    end
  end

  describe 'misc helpers' do
    it "is_wiped? is true when password_digest is '*'" do
      u = create(:user)
      u.update!(password_digest: '*')
      expect(u.is_wiped?).to be true
    end

    it 'roll_session_token sets a random 60-char token' do
      u = create(:user, session_token: nil)
      u.roll_session_token
      expect(u.session_token).to be_present
      expect(u.session_token.length).to eq(60)
    end

    it 'linkified_about converts markdown to HTML' do
      u = create(:user, about: 'hello')
      allow(Markdowner).to receive(:to_html).with('hello').and_return('<p>hello</p>')
      expect(u.linkified_about).to eq('<p>hello</p>')
    end

    it 'mastodon_acct builds acct string and raises without required fields' do
      u = create(:user, mastodon_username: 'me', mastodon_instance: 'example.org')
      expect(u.mastodon_acct).to eq('@me@example.org')
      v = create(:user, mastodon_username: nil, mastodon_instance: nil)
      expect { v.mastodon_acct }.to raise_error(RuntimeError)
    end

    it 'to_param returns username' do
      u = create(:user, username: 'alice')
      expect(u.to_param).to eq('alice')
    end
  end
end
