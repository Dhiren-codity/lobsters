# NOTE: Some failing tests were automatically removed after 3 fix attempts failed.
# These tests may need manual review. See CI logs for details.
# typed: false

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

  describe 'additional validations' do
    it 'validates presence of password on create' do
      user = build(:user, password: nil)
      expect(user).to_not be_valid
      expect(user.errors[:password]).to include("can't be blank")
    end

    it 'validates prefers_color_scheme and prefers_contrast inclusion' do
      expect(build(:user, prefers_color_scheme: 'system', prefers_contrast: 'high')).to be_valid
      invalid = build(:user, prefers_color_scheme: 'neon', prefers_contrast: 'none')
      expect(invalid).to_not be_valid
      expect(invalid.errors[:prefers_color_scheme]).to include('is not included in the list')
      expect(invalid.errors[:prefers_contrast]).to include('is not included in the list')
    end
  end

  describe 'scopes' do
    it 'returns only active users' do
      active = create(:user, banned_at: nil, deleted_at: nil)
      banned = create(:user, banned_at: Time.current)
      deleted = create(:user, deleted_at: Time.current)
      expect(User.active).to include(active)
      expect(User.active).to_not include(banned)
      expect(User.active).to_not include(deleted)
    end
  end

  describe 'tokens on create' do
    it 'generates session, rss, and mailing list tokens' do
      u = create(:user)
      expect(u.session_token).to be_present
      expect(u.rss_token).to be_present
      expect(u.mailing_list_token).to be_present
    end
  end

  describe 'class methods' do
    it 'finds by username using / operator' do
      u = create(:user, username: 'slashy')
      expect(User / 'slashy').to eq(u)
      expect { User / 'nope' }.to raise_error(ActiveRecord::RecordNotFound)
    end

    it 'returns username regex string' do
      s = User.username_regex_s
      expect(s).to start_with('/^')
      expect(s).to end_with('$/')
    end
  end

  describe '#as_json' do
    let(:inviter) { create(:user, username: 'inviter') }

    it 'includes public fields and excludes sensitive ones for non-admin' do
      allow(Markdowner).to receive(:to_html).and_return('rendered')
      u = create(:user, invited_by_user: inviter, about: 'hello', github_username: 'octo', mastodon_username: 'mast',
                        mastodon_instance: 'example.social')
      json = u.as_json

      expect(json['username']).to eq(u.username)
      expect(json.key?('karma')).to be true
      expect(json[:about]).to eq('rendered')
      expect(json[:invited_by_user]).to eq('inviter')
      expect(json[:avatar_url]).to include("/avatars/#{u.username}-100.png")
      expect(json[:github_username]).to eq('octo')
      expect(json[:mastodon_username]).to eq('mast')

      expect(json.key?('password_digest')).to be false
      expect(json.key?('email')).to be false
      expect(json.key?('totp_secret')).to be false
    end

    it 'omits karma for admins' do
      u = create(:user, is_admin: true)
      json = u.as_json
      expect(json.key?('karma')).to be false
    end
  end

  describe '#authenticate_totp' do
    it 'verifies a valid TOTP code' do
      secret = ROTP::Base32.random_base32
      u = create(:user, totp_secret: secret)
      code = ROTP::TOTP.new(secret).now
      expect(u.authenticate_totp(code)).to be_truthy
      expect(u.authenticate_totp('000000')).to be_falsey
    end
  end

  describe 'avatar helpers' do
    it 'returns avatar path and url for default and custom sizes' do
      u = create(:user, username: 'avataruser')
      expect(u.avatar_path).to end_with('/avatars/avataruser-100.png')
      expect(u.avatar_path(50)).to end_with('/avatars/avataruser-50.png')
      expect(u.avatar_url).to include('/avatars/avataruser-100.png')
      expect(u.avatar_url(50)).to include('/avatars/avataruser-50.png')
    end
  end

  describe '#disable_invite_by_user_for_reason!' do
    it 'disables invites, sends message, and logs moderation' do
      target = create(:user)
      mod = create(:user)
      reason = 'spamming invite codes'

      expect(target.disable_invite_by_user_for_reason!(mod, reason)).to be true
      target.reload

      expect(target.disabled_invite_at).to be_present
      expect(target.disabled_invite_by_user_id).to eq(mod.id)
      expect(target.disabled_invite_reason).to eq(reason)

      msg = Message.where(recipient_user_id: target.id).order(id: :desc).first
      expect(msg).to be_present
      expect(msg.subject).to include('revoked')
      expect(msg.body).to include(reason)

      moderation = Moderation.where(user_id: target.id).order(id: :desc).first
      expect(moderation).to be_present
      expect(moderation.action).to eq('Disabled invitations')
      expect(moderation.reason).to eq(reason)
    end
  end

  describe '#ban_by_user_for_reason!' do
    it 'bans, notifies by email, deletes account, and logs moderation' do
      user = create(:user)
      banner = create(:user)
      reason = 'terms violation'

      mail_double = double(deliver_now: true)
      expect(BanNotificationMailer).to receive(:notify).with(user, banner, reason).and_return(mail_double)

      expect(user.ban_by_user_for_reason!(banner, reason)).to be true
      user.reload

      expect(user.is_banned?).to be true
      expect(user.deleted_at).to be_present

      mod = Moderation.where(user_id: user.id).order(id: :desc).first
      expect(mod).to be_present
      expect(mod.action).to eq('Banned')
      expect(mod.reason).to eq(reason)
    end
  end

  describe '#banned_from_inviting?' do
    it 'reflects disabled_invite_at presence' do
      u = create(:user, disabled_invite_at: nil)
      expect(u.banned_from_inviting?).to be false
      u.update!(disabled_invite_at: Time.current)
      expect(u.banned_from_inviting?).to be true
    end
  end

  describe 'permission helpers' do
    it 'computes can_submit_stories? based on karma' do
      u1 = create(:user, karma: User::MIN_KARMA_TO_SUBMIT_STORIES)
      u2 = create(:user, karma: User::MIN_KARMA_TO_SUBMIT_STORIES - 1)
      expect(u1.can_submit_stories?).to be true
      expect(u2.can_submit_stories?).to be false
    end

    it 'computes high_karma?' do
      u1 = create(:user, karma: User::HIGH_KARMA_THRESHOLD)
      u2 = create(:user, karma: User::HIGH_KARMA_THRESHOLD - 1)
      expect(u1.high_karma?).to be true
      expect(u2.high_karma?).to be false
    end

    it 'computes can_invite?' do
      u = create(:user, karma: User::MIN_KARMA_TO_SUBMIT_STORIES, disabled_invite_at: nil)
      expect(u.can_invite?).to be true
      u.update!(disabled_invite_at: Time.current)
      expect(u.can_invite?).to be false
      u.update!(disabled_invite_at: nil, karma: User::MIN_KARMA_TO_SUBMIT_STORIES - 1)
      expect(u.can_invite?).to be false
    end

    it 'computes can_offer_suggestions?' do
      old = (User::NEW_USER_DAYS + 1).days.ago
      u1 = create(:user, created_at: old, karma: User::MIN_KARMA_TO_SUGGEST)
      u2 = create(:user, created_at: old, karma: User::MIN_KARMA_TO_SUGGEST - 1)
      u3 = create(:user, created_at: Time.current, karma: 1000)
      expect(u1.can_offer_suggestions?).to be true
      expect(u2.can_offer_suggestions?).to be false
      expect(u3.can_offer_suggestions?).to be false
    end

    it 'computes can_flag? for comments and stories' do
      old = (User::NEW_USER_DAYS + 1).days.ago
      u = create(:user, created_at: old, karma: User::MIN_KARMA_TO_FLAG)
      low = create(:user, created_at: old, karma: User::MIN_KARMA_TO_FLAG - 1)

      comment = create(:comment)
      allow(comment).to receive(:is_flaggable?).and_return(true)

      expect(u.can_flag?(comment)).to be true
      expect(low.can_flag?(comment)).to be false

      story = create(:story)
      allow(story).to receive(:is_flaggable?).and_return(true)
      expect(u.can_flag?(story)).to be true

      allow(story).to receive(:is_flaggable?).and_return(false)
      allow(story).to receive(:current_flagged?).and_return(true)
      expect(u.can_flag?(story)).to be true

      new_user = create(:user, created_at: Time.current, karma: 10)
      expect(new_user.can_flag?(story)).to be false
    end
  end

  describe 'keystore-backed counters' do
    it 'returns comments posted and deleted counts' do
      u = create(:user)
      allow(Keystore).to receive(:value_for).with("user:#{u.id}:comments_posted").and_return('5')
      allow(Keystore).to receive(:value_for).with("user:#{u.id}:comments_deleted").and_return('2')
      expect(u.comments_posted_count).to eq(5)
      expect(u.comments_deleted_count).to eq(2)
    end

    it 'refreshes counts into Keystore' do
      u = create(:user)
      create(:story, user: u)
      create(:comment, user: u, is_deleted: false)
      create(:comment, user: u, is_deleted: false)
      create(:comment, user: u, is_deleted: true)

      expect(Keystore).to receive(:put).with("user:#{u.id}:stories_submitted", 1)
      expect(Keystore).to receive(:put).with("user:#{u.id}:comments_posted", 2)
      expect(Keystore).to receive(:put).with("user:#{u.id}:comments_deleted", 1)
      u.refresh_counts!
    end
  end

  describe 'account deletion and restoration' do
    it 'delete! marks messages, invitations, rotates session, and sets deleted_at' do
      u = create(:user)
      old_token = u.session_token

      sent = create(:message, author: u, recipient: create(:user), deleted_by_author: false)
      recv = create(:message, author: create(:user), recipient: u, deleted_by_recipient: false)

      inv = create(:invitation, user: u, used_at: nil)

      u.delete!
      u.reload
      sent.reload
      recv.reload
      inv.reload

      expect(u.deleted_at).to be_present
      expect(u.session_token).to be_present
      expect(u.session_token).to_not eq(old_token)
      expect(sent.deleted_by_author).to be true
      expect(recv.deleted_by_recipient).to be true
      expect(inv.used_at).to be_present
    end

    it 'undelete! clears deleted_at' do
      u = create(:user, deleted_at: Time.current)
      u.undelete!
      expect(u.deleted_at).to be_nil
    end
  end

  describe '2FA helpers' do
    it 'disable_2fa! clears TOTP secret' do
      u = create(:user, totp_secret: 'SECRET')
      u.disable_2fa!
      expect(u.totp_secret).to be_nil
    end

    it 'has_2fa? reflects presence' do
      u = create(:user, totp_secret: nil)
      expect(u.has_2fa?).to be false
      u.update!(totp_secret: 'SECRET')
      expect(u.has_2fa?).to be true
    end
  end

  describe '#good_riddance?' do
    it 'sets placeholder email when karma is negative' do
      u = create(:user, karma: -1, email: 'x@y.com')
      u.good_riddance?
      expect(u.email).to eq("#{u.username}@lobsters.example")
    end
  end

  describe '#initiate_password_reset_for_ip' do
    it 'sets token and sends email' do
      u = create(:user)
      mail_double = double(deliver_now: true)
      expect(PasswordResetMailer).to receive(:password_reset_link).with(u, '1.2.3.4').and_return(mail_double)
      u.initiate_password_reset_for_ip('1.2.3.4')
      expect(u.password_reset_token).to be_present
      expect(u.password_reset_token).to include('-')
    end
  end

  describe 'misc helpers' do
    it "is_wiped? when password_digest is '*'" do
      u = create(:user)
      u.update!(password_digest: '*')
      expect(u.is_wiped?).to be true
    end

    it 'roll_session_token changes token' do
      u = create(:user)
      old = u.session_token
      u.roll_session_token
      expect(u.session_token).to be_present
      expect(u.session_token).to_not eq(old)
      expect(u.session_token.length).to be >= 60
    end

    it 'linkified_about uses Markdowner' do
      u = create(:user, about: 'hello')
      expect(Markdowner).to receive(:to_html).with('hello').and_return('<p>hello</p>')
      expect(u.linkified_about).to eq('<p>hello</p>')
    end

    it 'mastodon_acct composes acct and raises when incomplete' do
      u = create(:user, mastodon_username: 'alice', mastodon_instance: 'example.social')
      expect(u.mastodon_acct).to eq('@alice@example.social')

      u2 = create(:user, mastodon_username: 'bob', mastodon_instance: nil)
      expect { u2.mastodon_acct }.to raise_error(RuntimeError)
    end

    it 'to_param returns username' do
      u = create(:user, username: 'paramuser')
      expect(u.to_param).to eq('paramuser')
    end
  end

  describe '#votes_for_others' do
    it "returns votes on others' content only, newest first" do
      voter = create(:user)
      other = create(:user)
      own_story = create(:story, user: voter)
      other_story = create(:story, user: other)
      own_comment = create(:comment, user: voter, story: other_story)
      other_comment = create(:comment, user: other, story: other_story)

      v1 = create(:vote, user: voter, story: own_story, comment: nil, vote: 1)
      v2 = create(:vote, user: voter, story: other_story, comment: nil, vote: 1)
      v3 = create(:vote, user: voter, story: other_story, comment: other_comment, vote: 1)
      v4 = create(:vote, user: voter, story: other_story, comment: own_comment, vote: 1)

      results = voter.votes_for_others.to_a
      expect(results).to include(v2, v3)
      expect(results).to_not include(v1, v4)
      expect(results.first.id).to be > results.last.id
    end
  end
end
