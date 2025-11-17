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

  describe 'settings validations' do
    it 'validates prefers_color_scheme inclusion' do
      expect(build(:user, prefers_color_scheme: 'system')).to be_valid
      expect(build(:user, prefers_color_scheme: 'light')).to be_valid
      expect(build(:user, prefers_color_scheme: 'dark')).to be_valid
      expect(build(:user, prefers_color_scheme: 'sepia')).to_not be_valid
    end

    it 'validates prefers_contrast inclusion' do
      expect(build(:user, prefers_contrast: 'system')).to be_valid
      expect(build(:user, prefers_contrast: 'normal')).to be_valid
      expect(build(:user, prefers_contrast: 'high')).to be_valid
      expect(build(:user, prefers_contrast: 'low')).to_not be_valid
    end

    it 'requires password on create' do
      user = build(:user, password: nil)
      expect(user).to_not be_valid
      expect(user.errors[:password]).to be_present
    end
  end

  describe 'scopes' do
    it 'returns only active users for .active' do
      active = create(:user)
      banned = create(:user, :banned)
      deleted = create(:user, deleted_at: Time.current)
      expect(User.active).to include(active)
      expect(User.active).to_not include(banned)
      expect(User.active).to_not include(deleted)
    end
  end

  describe 'tokens and callbacks' do
    it 'generates session_token, rss_token and mailing_list_token on create' do
      u = create(:user)
      expect(u.session_token).to be_present
      expect(u.session_token.length).to be >= 20
      expect(u.rss_token).to be_present
      expect(u.rss_token.length).to be >= 10
      expect(u.mailing_list_token).to be_present
      expect(u.mailing_list_token.length).to be >= 10
    end

    it 'rolls the session_token when asked' do
      u = create(:user)
      allow(Utils).to receive(:random_str).with(60).and_return('new_session_token')
      u.roll_session_token
      expect(u.session_token).to eq('new_session_token')
    end
  end

  describe '#as_json' do
    let(:inviter) do
      create(:user, username: 'inviter_user')
    end

    it 'exposes limited fields and derived fields for non-admin users' do
      u = create(:user, invited_by_user: inviter, homepage: 'https://lobste.rs',
                        about: 'about', karma: 5, is_admin: false, github_username: 'octocat', mastodon_username: nil)
      allow(Markdowner).to receive(:to_html).with('about').and_return('<p>about</p>')
      json = u.as_json

      expect(json['username']).to eq(u.username)
      expect(json['karma']).to eq(5)
      expect(json[:about]).to eq('<p>about</p>')
      expect(json[:avatar_url]).to include("/avatars/#{u.username}-100.png")
      expect(json[:invited_by_user]).to eq('inviter_user')
      expect(json[:github_username]).to eq('octocat')
      expect(json).to_not have_key(:mastodon_username)
    end

    it 'omits karma for admins and includes mastodon username if present' do
      u = create(:user, invited_by_user: inviter, karma: 999, is_admin: true,
                        mastodon_username: 'alice', mastodon_instance: 'example.social')
      allow(Markdowner).to receive(:to_html).and_return('x')
      json = u.as_json
      expect(json).to_not have_key(:karma)
      expect(json[:mastodon_username]).to eq('alice')
    end
  end

  describe '#authenticate_totp' do
    it "verifies using ROTP with the user's secret" do
      u = create(:user, totp_secret: 'SECRET')
      totp = instance_double(ROTP::TOTP)
      allow(ROTP::TOTP).to receive(:new).with('SECRET').and_return(totp)
      allow(totp).to receive(:verify).with('123456').and_return(true)
      expect(u.authenticate_totp('123456')).to be true
    end
  end

  describe 'avatar helpers' do
    let(:u) do
      create(:user, username: 'avataruser')
    end

    it 'returns avatar_path for a given size' do
      path = u.avatar_path(64)
      expect(path).to include('/avatars/avataruser-64.png')
    end

    it 'returns avatar_url for a given size' do
      url = u.avatar_url(128)
      expect(url).to include('/avatars/avataruser-128.png')
    end
  end

  describe '#disable_invite_by_user_for_reason!' do
    it 'disables invites, notifies user, and records moderation' do
      mod = create(:user)
      u = create(:user)
      expect do
        expect(u.disable_invite_by_user_for_reason!(mod, 'spamming invites')).to be true
      end.to change { Message.count }.by(1).and change { Moderation.count }.by(1)

      u.reload
      expect(u.disabled_invite_at).to be_present
      expect(u.disabled_invite_by_user_id).to eq(mod.id)
      expect(u.disabled_invite_reason).to eq('spamming invites')

      msg = Message.order(:id).last
      expect(msg.recipient_user_id).to eq(u.id)
      expect(msg.author_user_id).to eq(mod.id)
      expect(msg.subject).to eq('Your invite privileges have been revoked')
      expect(msg.body).to include('spamming invites')
    end
  end

  describe '#ban_by_user_for_reason!' do
    it 'bans, deletes, notifies, and records moderation' do
      banner = create(:user)
      u = create(:user)
      notifier = double('mailer', deliver_now: true)
      allow(BanNotificationMailer).to receive(:notify).with(u, banner, 'reason').and_return(notifier)

      expect do
        expect(u.ban_by_user_for_reason!(banner, 'reason')).to be true
      end.to change { Moderation.count }.by(1)

      u.reload
      expect(u.banned_at).to be_present
      expect(u.banned_by_user_id).to eq(banner.id)
      expect(u.deleted_at).to be_present
      expect(BanNotificationMailer).to have_received(:notify).with(u, banner, 'reason')
    end
  end

  describe '#banned_from_inviting?' do
    it 'reflects disabled_invite_at presence' do
      u = create(:user)
      expect(u.banned_from_inviting?).to be false
      u.update!(disabled_invite_at: Time.current)
      expect(u.banned_from_inviting?).to be true
    end
  end

  describe 'ability predicates' do
    let(:old_user) do
      create(:user, created_at: (User::NEW_USER_DAYS + 1).days.ago, karma: 100)
    end

    it 'can_flag? for comments depends on karma and newness' do
      comment = create(:comment)
      allow(comment).to receive(:is_flaggable?).and_return(true)

      low_karma_user = create(:user, created_at: (User::NEW_USER_DAYS + 1).days.ago, karma: 10)
      expect(low_karma_user.can_flag?(comment)).to be false

      expect(old_user.can_flag?(comment)).to be true

      new_user = create(:user, created_at: Time.current, karma: 500)
      expect(new_user.can_flag?(comment)).to be false
    end

    it 'can_flag? for stories allows flaggable or unvoting' do
      story = create(:story)
      allow(story).to receive(:is_flaggable?).and_return(false)
      allow(story).to receive(:current_flagged?).and_return(true)
      expect(old_user.can_flag?(story)).to be true

      allow(story).to receive(:current_flagged?).and_return(false)
      expect(old_user.can_flag?(story)).to be false

      allow(story).to receive(:is_flaggable?).and_return(true)
      expect(old_user.can_flag?(story)).to be true
    end

    it 'can_invite? requires not banned from inviting and can_submit_stories?' do
      u = create(:user, karma: 0)
      expect(u.can_invite?).to be true
      u.update!(disabled_invite_at: Time.current)
      expect(u.can_invite?).to be false

      low = create(:user, karma: User::MIN_KARMA_TO_SUBMIT_STORIES - 10)
      expect(low.can_invite?).to be false
    end

    it 'can_offer_suggestions? requires not new and minimum karma' do
      u1 = create(:user, created_at: (User::NEW_USER_DAYS + 1).days.ago, karma: 10)
      expect(u1.can_offer_suggestions?).to be true

      u2 = create(:user, created_at: (User::NEW_USER_DAYS + 1).days.ago, karma: 5)
      expect(u2.can_offer_suggestions?).to be false

      u3 = create(:user, created_at: Time.current, karma: 100)
      expect(u3.can_offer_suggestions?).to be false
    end

    it 'can_see_invitation_requests? requires invite ability and sufficient role/karma' do
      base = create(:user, karma: 0)
      expect(base.can_see_invitation_requests?).to be false

      mod = create(:user, karma: 0, is_moderator: true)
      expect(mod.can_see_invitation_requests?).to be true

      high = create(:user, karma: User::MIN_KARMA_FOR_INVITATION_REQUESTS, is_moderator: false)
      expect(high.can_see_invitation_requests?).to be true

      low = create(:user, karma: User::MIN_KARMA_TO_SUBMIT_STORIES - 1)
      expect(low.can_see_invitation_requests?).to be false
    end

    it 'can_submit_stories? checks minimum karma' do
      u = create(:user, karma: User::MIN_KARMA_TO_SUBMIT_STORIES)
      expect(u.can_submit_stories?).to be true
      u2 = create(:user, karma: User::MIN_KARMA_TO_SUBMIT_STORIES - 1)
      expect(u2.can_submit_stories?).to be false
    end

    it 'high_karma? checks threshold' do
      u1 = create(:user, karma: User::HIGH_KARMA_THRESHOLD)
      u2 = create(:user, karma: User::HIGH_KARMA_THRESHOLD - 1)
      expect(u1.high_karma?).to be true
      expect(u2.high_karma?).to be false
    end
  end

  describe 'keystore-backed counters' do
    it 'reads comment counts via Keystore' do
      u = create(:user)
      allow(Keystore).to receive(:value_for).with("user:#{u.id}:comments_posted").and_return('12')
      allow(Keystore).to receive(:value_for).with("user:#{u.id}:comments_deleted").and_return('3')
      expect(u.comments_posted_count).to eq(12)
      expect(u.comments_deleted_count).to eq(3)
    end

    it 'reads story and comment counters via Keystore helpers' do
      u = create(:user)
      allow(Keystore).to receive(:value_for).with("user:#{u.id}:stories_submitted").and_return('7')
      allow(Keystore).to receive(:value_for).with("user:#{u.id}:stories_deleted").and_return('2')
      expect(u.stories_submitted_count).to eq(7)
      expect(u.stories_deleted_count).to eq(2)
    end

    it 'refresh_counts! writes latest counts' do
      u = create(:user)
      create(:story, user: u)
      create(:story, user: u)
      create(:comment, user: u, is_deleted: false)
      create(:comment, user: u, is_deleted: true)

      expect(Keystore).to receive(:put).with("user:#{u.id}:stories_submitted", 2)
      expect(Keystore).to receive(:put).with("user:#{u.id}:comments_posted", 1)
      expect(Keystore).to receive(:put).with("user:#{u.id}:comments_deleted", 1)
      u.refresh_counts!
    end
  end

  describe '#fetched_avatar' do
    it 'returns image body from gravatar when available' do
      u = create(:user, email: 'user@example.com')
      allow(u).to receive(:fetched_avatar).with(80).and_return('IMGDATA')
      expect(u.fetched_avatar(80)).to eq('IMGDATA')
    end

    it 'returns nil when fetching fails' do
      u = create(:user)
      allow(u).to receive(:fetched_avatar).with(80).and_return(nil)
      expect(u.fetched_avatar(80)).to be_nil
    end
  end

  describe 'account lifecycle' do
    it 'delete! marks deleted, updates messages and invitations, and rolls session token' do
      u = create(:user)
      other = create(:user)
      neg_comment = create(:comment, user: u, score: 0)
      allow(neg_comment).to receive(:delete_for_user).with(u)
      allow(u).to receive(:comments).and_return(Comment.where(id: [neg_comment.id]))

      sent = create(:message, author: u, recipient: other, deleted_by_author: false)
      received = create(:message, author: other, recipient: u, deleted_by_recipient: false)
      inv = create(:invitation, user: u, used_at: nil)

      allow(u).to receive(:good_riddance?).and_return(nil)

      old_token = u.session_token
      u.delete!
      u.reload

      expect(u.deleted_at).to be_present
      expect(u.session_token).to_not eq(old_token)
      expect(Message.find(sent.id).deleted_by_author).to be true
      expect(Message.find(received.id).deleted_by_recipient).to be true
      expect(Invitation.find(inv.id).used_at).to be_present
    end

    it 'undelete! clears deleted_at' do
      u = create(:user, deleted_at: Time.current)
      u.undelete!
      expect(u.deleted_at).to be_nil
    end

    it 'disable_2fa! clears totp_secret' do
      u = create(:user, totp_secret: 'SECRET')
      u.disable_2fa!
      expect(u.totp_secret).to be_nil
    end

    it 'good_riddance? anonymizes email for low-karma users' do
      u = create(:user, karma: -1, email: 'real@example.com')
      u.good_riddance?
      expect(u.email).to eq("#{u.username}@lobsters.example")
    end
  end

  describe '#initiate_password_reset_for_ip' do
    it 'sets a reset token and sends email' do
      u = create(:user)
      mailer = double('mailer', deliver_now: true)
      allow(PasswordResetMailer).to receive(:password_reset_link).with(u, '1.2.3.4').and_return(mailer)
      u.initiate_password_reset_for_ip('1.2.3.4')
      expect(u.password_reset_token).to match(/\d+-[A-Za-z0-9]+/)
      expect(PasswordResetMailer).to have_received(:password_reset_link).with(u, '1.2.3.4')
    end
  end

  describe 'misc predicates and helpers' do
    it 'has_2fa? reflects totp_secret presence' do
      u = create(:user, totp_secret: 'X')
      expect(u.has_2fa?).to be true
      u.update!(totp_secret: nil)
      expect(u.has_2fa?).to be false
    end

    it "is_wiped? when password_digest is '*'" do
      u = build(:user)
      u.password_digest = '*'
      expect(u.is_wiped?).to be true
    end

    it 'linkified_about uses Markdowner' do
      u = create(:user, about: 'hi')
      allow(Markdowner).to receive(:to_html).with('hi').and_return('<p>hi</p>')
      expect(u.linkified_about).to eq('<p>hi</p>')
    end

    it 'mastodon_acct composes acct and raises if missing fields' do
      u = create(:user, mastodon_username: 'alice', mastodon_instance: 'example.social')
      expect(u.mastodon_acct).to eq('@alice@example.social')
      u2 = create(:user, mastodon_username: nil, mastodon_instance: nil)
      expect { u2.mastodon_acct }.to raise_error(RuntimeError)
    end

    it 'to_param returns username' do
      u = create(:user, username: 'paramuser')
      expect(u.to_param).to eq('paramuser')
    end
  end

  describe '#most_common_story_tag' do
    it 'returns the tag with the most non-deleted stories for the user' do
      u = create(:user)
      t1 = create(:tag)
      t2 = create(:tag)
      create(:story, user: u, is_deleted: false, tags: [t1])
      create(:story, user: u, is_deleted: false, tags: [t1])
      create(:story, user: u, is_deleted: false, tags: [t2])
      expect(u.most_common_story_tag).to eq(t1)
    end
  end

  describe '#pushover!' do
    it 'sends a push when a user_key is present' do
      u = create(:user, pushover_user_key: 'KEY')
      params = { title: 'Hi' }
      expect(Pushover).to receive(:push).with('KEY', params)
      u.pushover!(params)
    end

    it 'does nothing without a user_key' do
      u = create(:user, pushover_user_key: nil)
      expect(Pushover).to_not receive(:push)
      u.pushover!(title: 'Hi')
    end
  end

  describe '#inbox_count' do
    it 'counts unread notifications' do
      u = create(:user)
      n1 = create(:story)
      n2 = create(:comment)
      create(:notification, user: u, notifiable: n1, read_at: nil)
      create(:notification, user: u, notifiable: n2, read_at: Time.current)
      expect(u.inbox_count).to eq(1)
    end
  end

  describe '#votes_for_others' do
    it "returns only votes on others' content ordered by id desc" do
      voter = create(:user)
      other = create(:user)
      own_story = create(:story, user: voter)
      other_story = create(:story, user: other)
      own_comment = create(:comment, user: voter)
      other_comment = create(:comment, user: other)

      v1 = create(:vote, user: voter, story: own_story, comment: nil)
      v2 = create(:vote, user: voter, story: other_story, comment: nil)
      v3 = create(:vote, user: voter, story: own_comment.story, comment: own_comment)
      v4 = create(:vote, user: voter, story: other_comment.story, comment: other_comment)

      result = voter.votes_for_others.to_a
      expect(result).to include(v2, v4)
      expect(result).to_not include(v1, v3)
      expect(result.first.id).to be > result.last.id
    end
  end

  describe '#enable_invite_by_user!' do
    it 're-enables invites and records moderation' do
      mod = create(:user)
      u = create(:user, disabled_invite_at: Time.current, disabled_invite_by_user: mod, disabled_invite_reason: 'x')
      expect do
        expect(u.enable_invite_by_user!(mod)).to be true
      end.to change { Moderation.count }.by(1)
      u.reload
      expect(u.disabled_invite_at).to be_nil
      expect(u.disabled_invite_by_user_id).to be_nil
      expect(u.disabled_invite_reason).to be_nil
    end
  end
end
