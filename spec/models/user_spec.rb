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
    let(:user) do
      create(:user)
    end

    it 'associates stories to user' do
      story = create(:story, user: user)
      expect(user.stories).to include(story)
    end

    it 'associates comments to user' do
      story = create(:story)
      comment = create(:comment, user: user, story: story)
      expect(user.comments).to include(comment)
    end

    it 'associates tag_filters and tag_filter_tags' do
      tag = create(:tag)
      user.tag_filters.create!(tag: tag)
      expect(user.tag_filters.count).to eq(1)
      expect(user.tag_filter_tags).to include(tag)
    end

    it 'associates notifications and inbox_count reflects unread count' do
      story1 = create(:story)
      story2 = create(:story)
      create(:notification, user: user, notifiable: story1, read_at: nil)
      create(:notification, user: user, notifiable: story2, read_at: Time.current)
      expect(user.inbox_count).to eq(1)
    end
  end

  describe 'scopes' do
    it 'returns only active users from .active' do
      active = create(:user)
      banned = create(:user, banned_at: Time.current)
      deleted = create(:user, deleted_at: Time.current)
      expect(User.active).to include(active)
      expect(User.active).to_not include(banned)
      expect(User.active).to_not include(deleted)
    end
  end

  describe '#as_json' do
    let!(:inviter) do
      create(:user, username: 'inviter_user')
    end

    it 'includes expected fields and excludes karma for admins' do
      admin = create(:user, is_admin: true, invited_by_user: inviter, about: 'Hi')
      allow(admin).to receive(:linkified_about).and_return('<p>Hi</p>')
      allow(admin).to receive(:avatar_url).and_return('http://example.com/avatar.png')

      json = admin.as_json

      expect(json).to_not have_key('karma')
      expect(json).to include('username' => admin.username)
      expect(json).to include('is_admin' => true, 'is_moderator' => false)
      expect(json).to include('homepage' => admin.homepage)
      expect(json[:invited_by_user]).to eq('inviter_user')
      expect(json[:about]).to eq('<p>Hi</p>')
      expect(json[:avatar_url]).to eq('http://example.com/avatar.png')
    end

    it 'includes karma for non-admins and provider usernames if present' do
      user = create(:user, invited_by_user: inviter, github_username: 'octo', mastodon_username: 'alice',
                           mastodon_instance: 'fosstodon.org')
      allow(user).to receive(:linkified_about).and_return('about')
      allow(user).to receive(:avatar_url).and_return('url')

      json = user.as_json

      expect(json).to have_key('karma')
      expect(json[:github_username]).to eq('octo')
      expect(json[:mastodon_username]).to eq('alice')
    end
  end

  describe '#authenticate_totp' do
    let(:user) do
      create(:user, totp_secret: 'secret')
    end

    it 'verifies codes via ROTP' do
      totp = instance_double(ROTP::TOTP)
      allow(ROTP::TOTP).to receive(:new).with('secret').and_return(totp)
      allow(totp).to receive(:verify).with('123456').and_return(true)
      expect(user.authenticate_totp('123456')).to be true
    end

    it 'returns false when verification fails' do
      totp = instance_double(ROTP::TOTP)
      allow(ROTP::TOTP).to receive(:new).with('secret').and_return(totp)
      allow(totp).to receive(:verify).with('000000').and_return(false)
      expect(user.authenticate_totp('000000')).to be false
    end
  end

  describe 'avatar helpers' do
    let(:user) do
      create(:user, username: 'alice')
    end

    it 'returns avatar_path with default size and custom size' do
      expect(user.avatar_path).to include('/avatars/alice-100.png')
      expect(user.avatar_path(50)).to include('/avatars/alice-50.png')
    end

    it 'returns avatar_url with default size and custom size' do
      expect(user.avatar_url).to include('/avatars/alice-100.png')
      expect(user.avatar_url(32)).to include('/avatars/alice-32.png')
    end
  end

  describe '#disable_invite_by_user_for_reason!' do
    let(:mod) do
      create(:user)
    end
    let(:user) do
      create(:user)
    end

    it 'disables invites, sends an internal message, and records a moderation' do
      expect do
        expect(user.disable_invite_by_user_for_reason!(mod, 'spam')).to be true
      end.to change(Message, :count).by(1).and change(Moderation, :count).by(1)

      user.reload
      expect(user.disabled_invite_at).to be_present
      expect(user.disabled_invite_by_user_id).to eq(mod.id)
      expect(user.disabled_invite_reason).to eq('spam')
      msg = Message.order(:id).last
      expect(msg.recipient_user_id).to eq(user.id)
      expect(msg.author_user_id).to eq(mod.id)
      expect(msg.deleted_by_author).to be true
      expect(msg.subject).to include('invite privileges')
      expect(Moderation.order(:id).last.action).to eq('Disabled invitations')
    end
  end

  describe '#ban_by_user_for_reason!' do
    let(:banner) do
      create(:user)
    end
    let(:user) do
      create(:user)
    end

    it 'bans the user, notifies via mailer, calls delete!, and records a moderation' do
      mailer = double(deliver_now: true)
      expect(BanNotificationMailer).to receive(:notify).with(user, banner, 'rulez').and_return(mailer)
      expect(user).to receive(:delete!).and_call_original

      expect do
        expect(user.ban_by_user_for_reason!(banner, 'rulez')).to be true
      end.to change(Moderation, :count).by(1)

      user.reload
      expect(user.banned_at).to be_present
      expect(user.banned_by_user_id).to eq(banner.id)
      expect(user.banned_reason).to eq('rulez')
      expect(Moderation.order(:id).last.action).to eq('Banned')
    end

    it 'does not notify when already deleted' do
      user.update!(deleted_at: Time.current)
      expect(BanNotificationMailer).to_not receive(:notify)
      expect(user).to receive(:delete!).and_return(true)
      expect(user.ban_by_user_for_reason!(banner, 'silent')).to be true
    end
  end

  describe '#banned_from_inviting?' do
    it 'reflects disabled_invite_at' do
      user = create(:user, disabled_invite_at: nil)
      expect(user.banned_from_inviting?).to be false
      user.update!(disabled_invite_at: Time.current)
      expect(user.banned_from_inviting?).to be true
    end
  end

  describe 'capabilities' do
    let(:user) do
      create(:user, created_at: (User::NEW_USER_DAYS + 1).days.ago, karma: 100)
    end

    it 'evaluates can_flag? for stories and comments' do
      story = create(:story)
      allow(story).to receive(:is_flaggable?).and_return(true)
      expect(user.can_flag?(story)).to be true

      allow(story).to receive(:is_flaggable?).and_return(false)
      allow(story).to receive(:current_flagged?).and_return(true)
      expect(user.can_flag?(story)).to be true

      allow(story).to receive(:current_flagged?).and_return(false)
      expect(user.can_flag?(story)).to be false

      comment = create(:comment)
      allow(comment).to receive(:is_flaggable?).and_return(true)
      low_karma_user = create(:user, created_at: (User::NEW_USER_DAYS + 1).days.ago, karma: User::MIN_KARMA_TO_FLAG - 1)
      expect(low_karma_user.can_flag?(comment)).to be false
      expect(user.can_flag?(comment)).to be true
    end

    it 'disallows can_flag? for new users' do
      newbie = create(:user, created_at: Time.current, karma: 100)
      story = create(:story)
      allow(story).to receive(:is_flaggable?).and_return(true)
      expect(newbie.can_flag?(story)).to be false
    end

    it 'evaluates can_invite? based on invite ban and story submission ability' do
      u = create(:user, karma: User::MIN_KARMA_TO_SUBMIT_STORIES)
      expect(u.can_invite?).to be true
      u.update!(disabled_invite_at: Time.current)
      expect(u.can_invite?).to be false
      low_karma = create(:user, karma: User::MIN_KARMA_TO_SUBMIT_STORIES - 10)
      expect(low_karma.can_invite?).to be false
    end

    it 'evaluates can_offer_suggestions?' do
      old_user = create(:user, created_at: (User::NEW_USER_DAYS + 1).days.ago, karma: User::MIN_KARMA_TO_SUGGEST)
      expect(old_user.can_offer_suggestions?).to be true
      newbie = create(:user, created_at: Time.current, karma: 999)
      expect(newbie.can_offer_suggestions?).to be false
      low_karma = create(:user, created_at: (User::NEW_USER_DAYS + 1).days.ago, karma: User::MIN_KARMA_TO_SUGGEST - 1)
      expect(low_karma.can_offer_suggestions?).to be false
    end

    it 'evaluates can_see_invitation_requests?' do
      mod = create(:user, created_at: (User::NEW_USER_DAYS + 1).days.ago, karma: 0, is_moderator: true)
      expect(mod.can_see_invitation_requests?).to be true

      inviter = create(:user, created_at: (User::NEW_USER_DAYS + 1).days.ago, karma: User::MIN_KARMA_TO_SUBMIT_STORIES)
      expect(inviter.can_invite?).to be true
      high_karma_inviter = create(:user, created_at: (User::NEW_USER_DAYS + 1).days.ago, karma: User::MIN_KARMA_FOR_INVITATION_REQUESTS)
      expect(high_karma_inviter.can_see_invitation_requests?).to be true

      mod_and_inviter = create(:user, created_at: (User::NEW_USER_DAYS + 1).days.ago,
                                      karma: User::MIN_KARMA_TO_SUBMIT_STORIES, is_moderator: true)
      expect(mod_and_inviter.can_see_invitation_requests?).to be true

      cannot_invite = create(:user, created_at: (User::NEW_USER_DAYS + 1).days.ago,
                                    karma: User::MIN_KARMA_TO_SUBMIT_STORIES - 10)
      expect(cannot_invite.can_see_invitation_requests?).to be false
    end

    it 'evaluates can_submit_stories? and high_karma?' do
      u = create(:user, karma: User::MIN_KARMA_TO_SUBMIT_STORIES)
      expect(u.can_submit_stories?).to be true
      low = create(:user, karma: User::MIN_KARMA_TO_SUBMIT_STORIES - 1)
      expect(low.can_submit_stories?).to be false
      hk = create(:user, karma: User::HIGH_KARMA_THRESHOLD)
      expect(hk.high_karma?).to be true
      nhk = create(:user, karma: User::HIGH_KARMA_THRESHOLD - 1)
      expect(nhk.high_karma?).to be false
    end
  end

  describe 'tokens and callbacks' do
    it 'rolls session token before save if blank' do
      user = build(:user, session_token: nil)
      expect(user.session_token).to be_nil
      user.save!
      expect(user.session_token).to be_present
      expect(user.session_token.length).to be >= 10
    end

    it 'generates rss and mailing list tokens on create if blank' do
      user = create(:user, rss_token: nil, mailing_list_token: nil)
      expect(user.rss_token).to be_present
      expect(user.rss_token.length).to eq(60)
      expect(user.mailing_list_token).to be_present
      expect(user.mailing_list_token.length).to eq(10)
    end

    it 'can manually roll_session_token to 60 chars' do
      user = create(:user)
      user.roll_session_token
      expect(user.session_token.length).to eq(60)
    end
  end

  describe 'keystore-backed counters' do
    it 'returns comments_posted_count and comments_deleted_count from Keystore' do
      user = create(:user)
      allow(Keystore).to receive(:value_for).with("user:#{user.id}:comments_posted").and_return('7')
      allow(Keystore).to receive(:value_for).with("user:#{user.id}:comments_deleted").and_return('3')
      expect(user.comments_posted_count).to eq(7)
      expect(user.comments_deleted_count).to eq(3)
    end

    it 'refresh_counts! writes to Keystore' do
      user = create(:user)
      story = create(:story, user: user)
      create(:comment, user: user, story: story, is_deleted: false)
      create(:comment, user: user, story: story, is_deleted: true)

      expect(Keystore).to receive(:put).with("user:#{user.id}:stories_submitted", 1)
      expect(Keystore).to receive(:put).with("user:#{user.id}:comments_posted", 1)
      expect(Keystore).to receive(:put).with("user:#{user.id}:comments_deleted", 1)

      user.refresh_counts!
    end
  end

  describe '#fetched_avatar' do
    let(:user) do
      create(:user, email: 'user@example.com')
    end

    it 'returns avatar bytes when fetch succeeds' do
      allow(user).to receive(:fetched_avatar).with(40).and_return('PNGDATA')
      expect(user.fetched_avatar(40)).to eq('PNGDATA')
    end

    it 'returns nil on error' do
      allow(user).to receive(:fetched_avatar).with(40).and_return(nil)
      expect(user.fetched_avatar(40)).to be_nil
    end
  end

  describe '#delete! and #undelete!' do
    let(:user) do
      create(:user, session_token: 'original_token')
    end
    let(:other_user) do
      create(:user)
    end

    it 'marks messages deleted, uses invitations, rolls token, sets deleted_at' do
      sent = create(:message, author: user, recipient: other_user, deleted_by_author: false)
      received = create(:message, author: other_user, recipient: user, deleted_by_recipient: false)
      invite = create(:invitation, user: user, used_at: nil)

      allow_any_instance_of(User).to receive(:good_riddance?)

      user.delete!
      user.reload
      expect(user.deleted_at).to be_present
      expect(user.session_token).to_not eq('original_token')

      expect(sent.reload.deleted_by_author).to be true
      expect(received.reload.deleted_by_recipient).to be true
      expect(invite.reload.used_at).to be_present

      user.undelete!
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
    it 'does nothing if banned' do
      user = create(:user, banned_at: Time.current, karma: -5, email: 'x@y.com')
      user.good_riddance?
      expect(user.email).to eq('x@y.com')
    end

    it 'scrubs email for negative karma users' do
      user = create(:user, karma: -1, username: 'scrub', email: 'real@example.com')
      user.good_riddance?
      expect(user.email).to eq('scrub@lobsters.example')
    end
  end

  describe '#grant_moderatorship_by_user!' do
    it 'grants mod, creates moderation and hat' do
      mod = create(:user)
      user = create(:user)
      expect { user.grant_moderatorship_by_user!(mod) }.to change(Moderation, :count).by(1)
      expect(user.reload.is_moderator).to be true
      expect(user.hats.pluck(:hat)).to include('Sysop')
    end
  end

  describe '#initiate_password_reset_for_ip' do
    it 'sets token and sends mail' do
      user = create(:user, password_reset_token: nil)
      mailer = double(deliver_now: true)
      expect(PasswordResetMailer).to receive(:password_reset_link).with(user, '127.0.0.1').and_return(mailer)
      user.initiate_password_reset_for_ip('127.0.0.1')
      expect(user.reload.password_reset_token).to be_present
      expect(user.password_reset_token).to include('-')
    end
  end

  describe '#has_2fa?, #is_wiped?' do
    it 'reflects 2fa and wiped status' do
      user = create(:user, totp_secret: 'sec')
      expect(user.has_2fa?).to be true
      user.update!(totp_secret: nil)
      expect(user.has_2fa?).to be false

      wiped = create(:user)
      wiped.update_columns(password_digest: '*')
      expect(wiped.is_wiped?).to be true
    end
  end

  describe '#linkified_about' do
    it 'delegates to Markdowner' do
      user = create(:user, about: 'hello')
      expect(Markdowner).to receive(:to_html).with('hello').and_return('<p>hello</p>')
      expect(user.linkified_about).to eq('<p>hello</p>')
    end
  end

  describe '#mastodon_acct' do
    it 'raises unless fields present' do
      user = create(:user, mastodon_username: nil, mastodon_instance: nil)
      expect do
        user.mastodon_acct
      end.to raise_error(RuntimeError)
    end

    it 'formats acct when present' do
      user = create(:user, mastodon_username: 'alice', mastodon_instance: 'fosstodon.org')
      expect(user.mastodon_acct).to eq('@alice@fosstodon.org')
    end
  end

  describe '#pushover!' do
    it 'sends when key present' do
      user = create(:user, pushover_user_key: 'key123')
      expect(Pushover).to receive(:push).with('key123', hash_including(title: 't'))
      user.pushover!(title: 't')
    end

    it 'does nothing when key missing' do
      user = create(:user, pushover_user_key: nil)
      expect(Pushover).to_not receive(:push)
      user.pushover!(title: 't')
    end
  end

  describe '#to_param' do
    it 'returns username' do
      user = create(:user, username: 'paramname')
      expect(user.to_param).to eq('paramname')
    end
  end

  describe '#enable_invite_by_user!' do
    it 're-enables invites and records moderation' do
      mod = create(:user)
      user = create(:user, disabled_invite_at: Time.current, disabled_invite_by_user: mod, disabled_invite_reason: 'x')
      expect do
        expect(user.enable_invite_by_user!(mod)).to be true
      end.to change(Moderation, :count).by(1)
      user.reload
      expect(user.disabled_invite_at).to be_nil
      expect(user.disabled_invite_by_user_id).to be_nil
      expect(user.disabled_invite_reason).to be_nil
      expect(Moderation.order(:id).last.action).to eq('Enabled invitations')
    end
  end

  describe '#votes_for_others' do
    it "returns votes on others' content only" do
      voter = create(:user)
      author1 = create(:user)
      author2 = create(:user)
      s1 = create(:story, user: author1)
      s2 = create(:story, user: voter)
      c1 = create(:comment, user: author2, story: s1)
      c2 = create(:comment, user: voter, story: s2)

      v1 = create(:vote, user: voter, story: s1, comment: nil)
      v2 = create(:vote, user: voter, story: s2, comment: nil)
      v3 = create(:vote, user: voter, story: s1, comment: c1)
      v4 = create(:vote, user: voter, story: s2, comment: c2)

      result = voter.votes_for_others.to_a
      expect(result).to include(v1, v3)
      expect(result).to_not include(v2, v4)
    end
  end
end
