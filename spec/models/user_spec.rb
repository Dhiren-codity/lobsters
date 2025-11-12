require 'rails_helper'

RSpec.describe User, type: :model do
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
    it 'returns a printable regex string with anchors' do
      str = User.username_regex_s
      expect(str).to start_with('/^')
      expect(str).to end_with('$/')
      expect(str).to include('[A-Za-z0-9_-]')
    end
  end

  describe '#as_json' do
    it 'includes karma for non-admins, basic fields, about/linkified, avatar_url, inviter, and oauth usernames when present' do
      inviter = create(:user, username: 'inviter_user')
      allow(Markdowner).to receive(:to_html).and_return('<p>about html</p>')
      u = create(:user, username: 'alice', invited_by_user: inviter, about: 'about',
                        homepage: 'https://example.com', github_username: 'alicehub', mastodon_username: 'alice',
                        mastodon_instance: 'social.example', is_admin: false)

      json = u.as_json

      expect(json[:username]).to eq('alice')
      expect(json).to have_key(:created_at)
      expect(json[:is_admin]).to be(false)
      expect(json[:is_moderator]).to be(false)
      expect(json[:karma]).to eq(u.karma)
      expect(json[:homepage]).to eq('https://example.com')
      expect(json[:about]).to eq('<p>about html</p>')
      expect(json[:avatar_url].to_s).to include('avatars/alice-100.png')
      expect(json[:invited_by_user]).to eq('inviter_user')
      expect(json[:github_username]).to eq('alicehub')
      expect(json[:mastodon_username]).to eq('alice')
    end

    it 'omits karma for admins and omits oauth usernames when blank' do
      allow(Markdowner).to receive(:to_html).and_return('<p>about html</p>')
      u = create(:user, username: 'adminuser', is_admin: true, github_username: nil, mastodon_username: nil,
                        mastodon_instance: nil)

      json = u.as_json

      expect(json.key?(:karma)).to be(false)
      expect(json.key?(:github_username)).to be(false)
      expect(json.key?(:mastodon_username)).to be(false)
    end
  end

  describe '#authenticate_totp' do
    it 'verifies a correct TOTP code and rejects an incorrect one' do
      secret = ROTP::Base32.random_base32
      u = create(:user, totp_secret: secret)
      totp = ROTP::TOTP.new(secret)
      code = totp.now

      expect(u.authenticate_totp(code)).to be_truthy
      expect(u.authenticate_totp('000000')).to be_falsey
    end
  end

  describe '#avatar_path and #avatar_url' do
    it 'builds avatar path and url for given size' do
      u = create(:user, username: 'bob')

      path = u.avatar_path(200)
      url = u.avatar_url(200)

      expect(path).to include('/avatars/bob-200.png')
      expect(url.to_s).to include('/avatars/bob-200.png')
    end
  end

  describe '#disable_invite_by_user_for_reason! and #banned_from_inviting?' do
    it 'disables inviting, notifies the user, and creates a moderation entry' do
      mod = create(:user)
      u = create(:user)

      expect(u.disable_invite_by_user_for_reason!(mod, 'too many invites')).to be(true)
      u.reload

      expect(u.disabled_invite_at).to be_present
      expect(u.disabled_invite_by_user_id).to eq(mod.id)
      expect(u.disabled_invite_reason).to eq('too many invites')
      expect(u.banned_from_inviting?).to be(true)

      msg = Message.where(recipient_user_id: u.id, author_user_id: mod.id).order(id: :desc).first
      expect(msg).to be_present
      expect(msg.subject).to eq('Your invite privileges have been revoked')
      expect(msg.deleted_by_author).to be(true)

      m = Moderation.where(user_id: u.id, moderator_user_id: mod.id).order(id: :desc).first
      expect(m).to be_present
      expect(m.action).to eq('Disabled invitations')
      expect(m.reason).to eq('too many invites')
    end
  end

  describe '#ban_by_user_for_reason!' do
    it 'bans and deletes the user, notifies them, and records moderation' do
      banner = create(:user)
      u = create(:user)
      mail_double = double(deliver_now: true)
      allow(BanNotificationMailer).to receive(:notify).and_return(mail_double)

      expect(u.ban_by_user_for_reason!(banner, 'spamming')).to be(true)
      u.reload

      expect(u.banned_at).to be_present
      expect(u.banned_by_user_id).to eq(banner.id)
      expect(u.banned_reason).to eq('spamming')
      expect(u.deleted_at).to be_present

      expect(BanNotificationMailer).to have_received(:notify).with(u, banner, 'spamming')

      m = Moderation.where(user_id: u.id, moderator_user_id: banner.id).order(id: :desc).first
      expect(m).to be_present
      expect(m.action).to eq('Banned')
      expect(m.reason).to eq('spamming')
    end
  end

  describe 'permission helpers' do
    it 'evaluates can_submit_stories? at threshold' do
      u1 = create(:user, karma: -5)
      u2 = create(:user, karma: -4)
      expect(u1.can_submit_stories?).to be(false)
      expect(u2.can_submit_stories?).to be(true)
    end

    it 'evaluates can_invite? based on invite ban and submit ability' do
      u = create(:user, karma: -5)
      expect(u.can_invite?).to be(false)

      u2 = create(:user, karma: 10)
      expect(u2.can_invite?).to be(true)

      # disable invitations
      mod = create(:user)
      u2.disable_invite_by_user_for_reason!(mod, 'oops')
      expect(u2.can_invite?).to be(false)
    end

    it 'evaluates can_offer_suggestions? using age and karma' do
      old_enough = create(:user, created_at: (User::NEW_USER_DAYS + 1).days.ago, karma: 10)
      expect(old_enough.can_offer_suggestions?).to be(true)

      low_karma = create(:user, created_at: (User::NEW_USER_DAYS + 1).days.ago, karma: 9)
      expect(low_karma.can_offer_suggestions?).to be(false)

      new_user = create(:user, created_at: Time.current, karma: 100)
      expect(new_user.can_offer_suggestions?).to be(false)
    end

    it 'evaluates can_see_invitation_requests? for moderators and high karma users' do
      low_user = create(:user, karma: 0)
      expect(low_user.can_see_invitation_requests?).to be(false)

      high_karma_user = create(:user, karma: User::MIN_KARMA_FOR_INVITATION_REQUESTS)
      expect(high_karma_user.can_see_invitation_requests?).to be(true)

      moderator = create(:user, is_moderator: true)
      expect(moderator.can_see_invitation_requests?).to be(true)
    end

    it 'returns high_karma? at threshold' do
      u1 = create(:user, karma: User::HIGH_KARMA_THRESHOLD - 1)
      u2 = create(:user, karma: User::HIGH_KARMA_THRESHOLD)
      expect(u1.high_karma?).to be(false)
      expect(u2.high_karma?).to be(true)
    end
  end

  describe 'token generation callbacks' do
    it 'generates session_token, rss_token, and mailing_list_token on create' do
      allow(Utils).to receive(:random_str) { |n| 'x' * n }
      u = create(:user, session_token: nil, rss_token: nil, mailing_list_token: nil)
      expect(u.session_token).to eq('x' * 60)
      expect(u.rss_token).to eq('x' * 60)
      expect(u.mailing_list_token).to eq('x' * 10)
    end

    it 'rolls session token if blank before save' do
      allow(Utils).to receive(:random_str).with(60).and_return('t' * 60)
      u = build(:user, session_token: nil)
      u.save!
      expect(u.session_token).to eq('t' * 60)
    end
  end

  describe '#refresh_counts!' do
    it 'updates keystore-backed counters for stories and comments' do
      u = create(:user)
      create(:story, user: u)
      create(:story, user: u)
      create(:story, user: u)
      create(:comment, user: u, is_deleted: false)
      create(:comment, user: u, is_deleted: false)
      create(:comment, user: u, is_deleted: true)

      u.refresh_counts!

      expect(u.stories_submitted_count).to eq(3)
      expect(u.comments_posted_count).to eq(2)
      expect(u.comments_deleted_count).to eq(1)
    end
  end

  describe '#fetched_avatar' do
    it 'returns body when gravatar fetch succeeds' do
      u = create(:user, email: 'user@example.com')
      sponge = double
      allow(Sponge).to receive(:new).and_return(sponge)
      allow(sponge).to receive(:timeout=)
      allow(sponge).to receive(:fetch).and_return(double(body: 'IMGDATA'))

      expect(u.fetched_avatar(80)).to eq('IMGDATA')
    end

    it 'returns nil when gravatar fetch raises' do
      u = create(:user, email: 'user@example.com')
      sponge = double
      allow(Sponge).to receive(:new).and_return(sponge)
      allow(sponge).to receive(:timeout=)
      allow(sponge).to receive(:fetch).and_raise(StandardError.new('network'))

      expect(u.fetched_avatar(80)).to be_nil
    end
  end

  describe '#delete! and #undelete!' do
    it 'marks messages, invitations, rolls tokens, sets deleted_at, and applies good_riddance for low karma' do
      # avoid FlaggedCommenters side effects
      allow(FlaggedCommenters).to receive(:new).and_return(double(check_list_for: false))
      u = create(:user, karma: -1) # triggers good_riddance? email change
      other = create(:user)

      sent = create(:message, author_user_id: u.id, recipient_user_id: other.id, deleted_by_author: false)
      received = create(:message, author_user_id: other.id, recipient_user_id: u.id, deleted_by_recipient: false)
      inv = create(:invitation, user: u, used_at: nil)

      old_token = u.session_token
      u.delete!
      u.reload

      expect(u.deleted_at).to be_present
      expect(u.session_token).not_to eq(old_token)
      expect(Message.find(sent.id).deleted_by_author).to be(true)
      expect(Message.find(received.id).deleted_by_recipient).to be(true)
      expect(Invitation.find(inv.id).used_at).to be_present
      expect(u.email).to eq("#{u.username}@lobsters.example")

      u.undelete!
      u.reload
      expect(u.deleted_at).to be_nil
    end
  end

  describe '#disable_2fa! and #has_2fa?' do
    it 'disables 2fa and reflects presence correctly' do
      u = create(:user, totp_secret: 'ABC')
      expect(u.has_2fa?).to be(true)
      u.disable_2fa!
      expect(u.has_2fa?).to be(false)
      expect(u.totp_secret).to be_nil
    end
  end

  describe '#grant_moderatorship_by_user!' do
    it 'grants moderatorship, logs moderation, and creates a Sysop hat' do
      mod = create(:user)
      u = create(:user, is_moderator: false)

      expect(u.grant_moderatorship_by_user!(mod)).to be(true)
      u.reload

      expect(u.is_moderator).to be(true)

      m = Moderation.where(user_id: u.id, moderator_user_id: mod.id).order(id: :desc).first
      expect(m).to be_present
      expect(m.action).to eq('Granted moderator status')

      h = Hat.where(user_id: u.id, granted_by_user_id: mod.id).order(id: :desc).first
      expect(h).to be_present
      expect(h.hat).to eq('Sysop')
    end
  end

  describe '#initiate_password_reset_for_ip' do
    it 'sets a reset token and sends an email' do
      u = create(:user)
      mail = double(deliver_now: true)
      allow(PasswordResetMailer).to receive(:password_reset_link).and_return(mail)

      u.initiate_password_reset_for_ip('1.2.3.4')
      u.reload

      expect(u.password_reset_token).to match(/\A\d+-[A-Za-z0-9]+\z/)
      expect(PasswordResetMailer).to have_received(:password_reset_link).with(u, '1.2.3.4')
    end
  end

  describe '#is_wiped?' do
    it "is true only when password_digest is '*'" do
      u = create(:user)
      expect(u.is_wiped?).to be(false)
      u.update!(password_digest: '*')
      expect(u.is_wiped?).to be(true)
    end
  end

  describe '#ids_replied_to' do
    it 'returns a hash of comment ids the user replied to' do
      u = create(:user)
      other = create(:user)
      story = create(:story, user: other)
      parent1 = create(:comment, user: other, story: story)
      parent2 = create(:comment, user: other, story: story)
      parent3 = create(:comment, user: other, story: story)
      # replies by u to parent1 and parent3
      create(:comment, user: u, story: story, parent_comment_id: parent1.id)
      create(:comment, user: u, story: story, parent_comment_id: parent3.id)
      # unrelated comment
      create(:comment, user: u, story: story)

      result = u.ids_replied_to([parent1.id, parent2.id, parent3.id])

      expect(result[parent1.id]).to be(true)
      expect(result[parent2.id]).to be(false)
      expect(result[parent3.id]).to be(true)
    end
  end

  describe '#roll_session_token' do
    it 'sets a random session token' do
      u = create(:user)
      allow(Utils).to receive(:random_str).with(60).and_return('s' * 60)
      u.roll_session_token
      expect(u.session_token).to eq('s' * 60)
    end
  end

  describe '#linkified_about' do
    it 'delegates to Markdowner' do
      u = create(:user, about: 'hello')
      allow(Markdowner).to receive(:to_html).with('hello').and_return('<p>hello</p>')
      expect(u.linkified_about).to eq('<p>hello</p>')
    end
  end

  describe '#mastodon_acct' do
    it 'returns the acct string when configured, else raises' do
      u = create(:user, mastodon_username: 'alice', mastodon_instance: 'social.example')
      expect(u.mastodon_acct).to eq('@alice@social.example')

      u2 = create(:user, mastodon_username: nil, mastodon_instance: 'x')
      expect { u2.mastodon_acct }.to raise_error(RuntimeError)
    end
  end

  describe '#pushover!' do
    it 'sends a push when user key is present and does nothing when blank' do
      u = create(:user, pushover_user_key: 'KEY123')
      expect(Pushover).to receive(:push).with('KEY123', { title: 'Hi' })
      u.pushover!(title: 'Hi')

      u2 = create(:user, pushover_user_key: nil)
      expect(Pushover).not_to receive(:push)
      u2.pushover!(title: 'Hi')
    end
  end

  describe '#to_param' do
    it 'returns the username' do
      u = create(:user, username: 'paramuser')
      expect(u.to_param).to eq('paramuser')
    end
  end

  describe '#enable_invite_by_user!' do
    it 'enables invitations and records moderation' do
      mod = create(:user)
      u = create(:user)
      u.disable_invite_by_user_for_reason!(mod, 'temporary')

      expect(u.enable_invite_by_user!(mod)).to be(true)
      u.reload

      expect(u.disabled_invite_at).to be_nil
      expect(u.disabled_invite_by_user_id).to be_nil
      expect(u.disabled_invite_reason).to be_nil

      m = Moderation.where(user_id: u.id, moderator_user_id: mod.id).order(id: :desc).first
      expect(m).to be_present
      expect(m.action).to eq('Enabled invitations')
    end
  end

  describe '#votes_for_others' do
    it "returns votes on others' content ordered by newest first" do
      voter = create(:user)
      other = create(:user)

      # Story votes
      their_story = create(:story, user: other)
      my_story = create(:story, user: voter)

      v1 = create(:vote, user: voter, story: their_story, vote: 1)
      v2 = create(:vote, user: voter, story: my_story, vote: 1)

      # Comment votes
      their_comment = create(:comment, user: other, story: their_story)
      my_comment = create(:comment, user: voter, story: their_story)

      v3 = create(:vote, user: voter, comment: their_comment, vote: 1)
      v4 = create(:vote, user: voter, comment: my_comment, vote: 1)

      result_ids = voter.votes_for_others.pluck(:id)

      expect(result_ids).to include(v1.id, v3.id)
      expect(result_ids).not_to include(v2.id, v4.id)
      expect(result_ids).to eq([v3.id, v1.id])
    end
  end
end
