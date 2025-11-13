# frozen_string_literal: true

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

  # NEW TESTS

  describe 'associations' do
    it { should have_many(:stories) }
    it { should have_many(:comments) }
    it { should have_many(:sent_messages).class_name('Message').with_foreign_key('author_user_id') }
    it { should have_many(:received_messages).class_name('Message').with_foreign_key('recipient_user_id') }
    it { should have_many(:tag_filters).dependent(:destroy) }
    it { should have_many(:tag_filter_tags) }
    it { should belong_to(:invited_by_user).class_name('User').optional }
    it { should belong_to(:banned_by_user).class_name('User').optional }
    it { should belong_to(:disabled_invite_by_user).class_name('User').optional }
    it { should have_many(:invitations).dependent(:destroy) }
    it { should have_many(:mod_notes) }
    it { should have_many(:moderations) }
    it { should have_many(:votes).dependent(:destroy) }
    it { should have_many(:voted_stories) }
    it { should have_many(:upvoted_stories) }
    it { should have_many(:hats).dependent(:destroy) }
    it { should have_many(:wearable_hats).class_name('Hat') }
    it { should have_many(:notifications) }
    it { should have_many(:hidings).class_name('HiddenStory').dependent(:destroy) }
  end

  describe 'scopes' do
    describe '.active' do
      it 'returns users without banned_at and deleted_at' do
        active = create(:user, banned_at: nil, deleted_at: nil)
        banned = create(:user, banned_at: Time.current)
        deleted = create(:user, deleted_at: Time.current)
        expect(User.active).to include(active)
        expect(User.active).not_to include(banned)
        expect(User.active).not_to include(deleted)
      end
    end

    describe '.moderators' do
      it 'includes users with is_moderator true' do
        mod = create(:user, is_moderator: true)
        regular = create(:user, is_moderator: false)
        expect(User.moderators).to include(mod)
        expect(User.moderators).not_to include(regular)
      end
    end
  end

  describe '.username_regex_s' do
    it 'returns a stringified regex for usernames' do
      expected = "/^#{User::VALID_USERNAME.to_s.gsub(/(\?-mix:|\(|\))/, '')}$/"
      expect(User.username_regex_s).to eq(expected)
    end
  end

  describe '.\/ (finder by username)' do
    it 'finds a user by username using the slash method' do
      u = create(:user, username: 'finder')
      expect(User./('finder')).to eq(u)
    end

    it 'raises when the user is not found' do
      expect { User./('nope') }.to raise_error(ActiveRecord::RecordNotFound)
    end
  end

  describe '#high_karma?' do
    it 'returns true when karma >= threshold' do
      u = create(:user, karma: User::HIGH_KARMA_THRESHOLD)
      expect(u.high_karma?).to be true
    end

    it 'returns false when karma < threshold' do
      u = create(:user, karma: User::HIGH_KARMA_THRESHOLD - 1)
      expect(u.high_karma?).to be false
    end
  end

  describe '#check_session_token' do
    it 'rolls a session token before save if blank' do
      u = build(:user, session_token: nil)
      expect(u.session_token).to be_nil
      u.save!
      expect(u.session_token).to be_present
      expect(u.session_token.length).to be <= 75
    end
  end

  describe 'token generation on create' do
    it 'creates mailing_list_token and rss_token on create if blank' do
      u = create(:user, mailing_list_token: nil, rss_token: nil)
      expect(u.mailing_list_token).to be_present
      expect(u.rss_token).to be_present
    end
  end

  describe '#roll_session_token' do
    it 'sets a random 60 character token' do
      u = build(:user)
      u.roll_session_token
      expect(u.session_token).to be_present
      expect(u.session_token.length).to eq(60)
    end
  end

  describe '#authenticate_totp' do
    it 'verifies a correct TOTP code and rejects an incorrect one' do
      u = create(:user, totp_secret: ROTP::Base32.random_base32)
      totp = ROTP::TOTP.new(u.totp_secret)
      code = totp.now
      expect(u.authenticate_totp(code)).to be_truthy
      expect(u.authenticate_totp('000000')).to be_falsey
    end
  end

  describe '#avatar_path and #avatar_url' do
    it 'returns the expected avatar path and url with given size' do
      u = create(:user, username: 'alice')
      expect(u.avatar_path(50)).to include('/avatars/alice-50.png')
      expect(u.avatar_url(50)).to include('/avatars/alice-50.png')
    end
  end

  describe '#as_json' do
    it 'includes karma for non-admin users and excludes for admins' do
      non_admin = create(:user, is_admin: false, about: 'hi', homepage: 'https://lobste.rs')
      admin = create(:user, is_admin: true, about: 'hi2', homepage: 'https://lobste.rs')

      allow(non_admin).to receive(:avatar_url).and_return('http://example.com/a.png')
      allow(admin).to receive(:avatar_url).and_return('http://example.com/b.png')
      allow(Markdowner).to receive(:to_html).and_return('about-html')

      h1 = non_admin.as_json
      expect(h1[:karma]).to eq(non_admin.karma)
      expect(h1[:avatar_url]).to eq('http://example.com/a.png')
      expect(h1[:about]).to eq('about-html')

      h2 = admin.as_json
      expect(h2).not_to have_key(:karma)
      expect(h2[:avatar_url]).to eq('http://example.com/b.png')
      expect(h2[:about]).to eq('about-html')
    end

    it 'includes invited_by_user username when present' do
      inviter = create(:user, username: 'inviter')
      invitee = create(:user, invited_by_user: inviter)
      allow(invitee).to receive(:avatar_url).and_return('x')
      allow(Markdowner).to receive(:to_html).and_return('y')
      expect(invitee.as_json[:invited_by_user]).to eq('inviter')
    end

    it 'conditionally includes github and mastodon usernames' do
      u = create(:user, github_username: 'ghuser', mastodon_username: 'mduser', mastodon_instance: 'fosstodon.org')
      allow(u).to receive(:avatar_url).and_return('x')
      allow(Markdowner).to receive(:to_html).and_return('y')
      h = u.as_json
      expect(h[:github_username]).to eq('ghuser')
      expect(h[:mastodon_username]).to eq('mduser')
    end
  end

  describe '#disable_invite_by_user_for_reason! / #enable_invite_by_user!' do
    it 'disables and enables invite privileges with audit trail' do
      mod = create(:user)
      u = create(:user)
      expect(u.banned_from_inviting?).to be false

      expect do
        expect(u.disable_invite_by_user_for_reason!(mod, 'abuse')).to be true
      end.to change { Moderation.count }.by(1)
                                        .and change { Message.count }.by(1)

      u.reload
      expect(u.banned_from_inviting?).to be true
      expect(u.disabled_invite_reason).to eq('abuse')
      expect(u.disabled_invite_by_user_id).to eq(mod.id)

      expect do
        expect(u.enable_invite_by_user!(mod)).to be true
      end.to change { Moderation.count }.by(1)

      u.reload
      expect(u.banned_from_inviting?).to be false
      expect(u.disabled_invite_reason).to be_nil
    end
  end

  describe '#ban_by_user_for_reason!' do
    it 'bans user, deletes them, and notifies via mail' do
      banner = create(:user)
      u = create(:user)
      mail = double('Mail', deliver_now: true)
      expect(BanNotificationMailer).to receive(:notify).with(u, banner, 'spam').and_return(mail)

      expect do
        expect(u.ban_by_user_for_reason!(banner, 'spam')).to be true
      end.to change { Moderation.count }.by(1)

      u.reload
      expect(u.banned_at).to be_present
      expect(u.deleted_at).to be_present
      expect(u.banned_by_user_id).to eq(banner.id)
      expect(u.banned_reason).to eq('spam')
    end
  end

  describe '#can_flag?' do
    it 'prevents new users from flagging' do
      u = create(:user, created_at: Time.current)
      story = create(:story, user: create(:user))
      allow(story).to receive(:is_flaggable?).and_return(true)
      expect(u.can_flag?(story)).to be false
    end

    it 'allows flagging flaggable stories and unvoting flagged ones' do
      u = create(:user, created_at: (User::NEW_USER_DAYS + 1).days.ago)
      story = create(:story, user: create(:user))
      allow(story).to receive(:is_flaggable?).and_return(true)
      allow(story).to receive(:current_flagged?).and_return(false)
      expect(u.can_flag?(story)).to be true

      allow(story).to receive(:is_flaggable?).and_return(false)
      allow(story).to receive(:current_flagged?).and_return(true)
      expect(u.can_flag?(story)).to be true
    end

    it 'allows flagging comments only with sufficient karma' do
      low = create(:user, karma: User::MIN_KARMA_TO_FLAG - 1,
                          created_at: (User::NEW_USER_DAYS + 1).days.ago)
      high = create(:user, karma: User::MIN_KARMA_TO_FLAG,
                           created_at: (User::NEW_USER_DAYS + 1).days.ago)
      c = create(:comment)
      allow(c).to receive(:is_flaggable?).and_return(true)
      expect(low.can_flag?(c)).to be false
      expect(high.can_flag?(c)).to be true
    end
  end

  describe '#can_invite?' do
    it 'requires not banned from inviting and the ability to submit stories' do
      u = create(:user, karma: User::MIN_KARMA_TO_SUBMIT_STORIES)
      expect(u.can_invite?).to be true

      u2 = create(:user, karma: User::MIN_KARMA_TO_SUBMIT_STORIES - 1)
      expect(u2.can_invite?).to be false

      mod = create(:user)
      u3 = create(:user, karma: 100)
      u3.disable_invite_by_user_for_reason!(mod, 'abuse')
      expect(u3.can_invite?).to be false
    end
  end

  describe '#can_offer_suggestions?' do
    it 'allows non-new users above karma threshold' do
      u = create(:user, karma: User::MIN_KARMA_TO_SUGGEST,
                        created_at: (User::NEW_USER_DAYS + 1).days.ago)
      expect(u.can_offer_suggestions?).to be true
      u2 = create(:user, karma: User::MIN_KARMA_TO_SUGGEST - 1,
                         created_at: (User::NEW_USER_DAYS + 1).days.ago)
      expect(u2.can_offer_suggestions?).to be false
    end
  end

  describe '#can_see_invitation_requests?' do
    it 'is true for moderators with invite ability and for high karma users' do
      mod = create(:user, is_moderator: true, karma: 100)
      expect(mod.can_see_invitation_requests?).to be true

      capable = create(:user, karma: User::MIN_KARMA_FOR_INVITATION_REQUESTS,
                              created_at: (User::NEW_USER_DAYS + 1).days.ago)
      expect(capable.can_see_invitation_requests?).to be true

      incapable = create(:user, karma: User::MIN_KARMA_FOR_INVITATION_REQUESTS - 1,
                                created_at: (User::NEW_USER_DAYS + 1).days.ago)
      expect(incapable.can_see_invitation_requests?).to be false
    end
  end

  describe '#can_submit_stories?' do
    it 'respects minimum karma threshold' do
      ok = create(:user, karma: User::MIN_KARMA_TO_SUBMIT_STORIES)
      bad = create(:user, karma: User::MIN_KARMA_TO_SUBMIT_STORIES - 1)
      expect(ok.can_submit_stories?).to be true
      expect(bad.can_submit_stories?).to be false
    end
  end

  describe '#comments_posted_count / #comments_deleted_count and #refresh_counts!' do
    it 'refreshes and reads counts from keystore' do
      u = create(:user)
      s = create(:story, user: u)
      create(:comment, user: u, story: s, is_deleted: false)
      create(:comment, user: u, story: s, is_deleted: true)

      u.refresh_counts!
      expect(u.comments_posted_count).to eq(1)
      expect(u.comments_deleted_count).to eq(1)
    end
  end

  describe '#fetched_avatar' do
    it 'returns bytes when fetch succeeds' do
      u = create(:user, email: 'x@example.com')
      sponge = double('Sponge', timeout: nil, fetch: double('Resp', body: 'bytes'))
      expect(Sponge).to receive(:new).and_return(sponge)
      expect(u.fetched_avatar(40)).to eq('bytes')
    end

    it 'returns nil when fetch fails' do
      u = create(:user, email: 'x@example.com')
      sponge = double('Sponge')
      allow(Sponge).to receive(:new).and_return(sponge)
      allow(sponge).to receive(:timeout=)
      allow(sponge).to receive(:fetch).and_raise(StandardError.new('fail'))
      expect(u.fetched_avatar(40)).to be_nil
    end
  end

  describe '#delete! / #undelete!' do
    it 'marks user as deleted, rolls session token, and may anonymize email' do
      u = create(:user, karma: -1, email: 'real@example.com')
      old_token = u.session_token
      u.delete!
      u.reload
      expect(u.deleted_at).to be_present
      expect(u.session_token).to be_present
      expect(u.session_token).not_to eq(old_token)
      expect(u.email).to eq("#{u.username}@lobsters.example")

      u.undelete!
      u.reload
      expect(u.deleted_at).to be_nil
    end
  end

  describe '#disable_2fa! and #has_2fa?' do
    it 'clears totp_secret and reports 2fa presence' do
      u = create(:user, totp_secret: 'secret')
      expect(u.has_2fa?).to be true
      u.disable_2fa!
      u.reload
      expect(u.has_2fa?).to be false
      expect(u.totp_secret).to be_nil
    end
  end

  describe '#good_riddance?' do
    it 'anonymizes email when user has negative karma' do
      u = create(:user, karma: -5, email: 'x@y.com')
      u.good_riddance?
      expect(u.email).to eq("#{u.username}@lobsters.example")
    end
  end

  describe '#grant_moderatorship_by_user!' do
    it 'promotes user, creates moderation and a Sysop hat' do
      actor = create(:user)
      u = create(:user, is_moderator: false)

      expect do
        expect(u.grant_moderatorship_by_user!(actor)).to be true
      end.to change { Moderation.count }.by(1)
                                        .and change { Hat.count }.by(1)

      u.reload
      expect(u.is_moderator).to be true
      expect(u.hats.last.hat).to eq('Sysop')
    end
  end

  describe '#initiate_password_reset_for_ip' do
    it 'generates a token and delivers mail' do
      u = create(:user)
      mail = double('Mail', deliver_now: true)
      expect(PasswordResetMailer).to receive(:password_reset_link).with(u, '127.0.0.1').and_return(mail)
      u.initiate_password_reset_for_ip('127.0.0.1')
      u.reload
      expect(u.password_reset_token).to match(/\A\d+-[A-Za-z0-9]+\z/)
    end
  end

  describe '#is_wiped?' do
    it 'is true when password_digest is "*"' do
      u = create(:user)
      u.update_columns(password_digest: '*')
      expect(u.is_wiped?).to be true
    end

    it 'is false otherwise' do
      u = create(:user)
      expect(u.is_wiped?).to be false
    end
  end

  describe '#linkified_about' do
    it 'renders about with Markdowner' do
      u = create(:user, about: 'hello')
      expect(Markdowner).to receive(:to_html).with('hello').and_return('<p>hello</p>')
      expect(u.linkified_about).to eq('<p>hello</p>')
    end
  end

  describe '#mastodon_acct' do
    it 'returns acct when both username and instance present' do
      u = create(:user, mastodon_username: 'alice', mastodon_instance: 'example.org')
      expect(u.mastodon_acct).to eq('@alice@example.org')
    end

    it 'raises when missing data' do
      u = create(:user, mastodon_username: nil, mastodon_instance: nil)
      expect { u.mastodon_acct }.to raise_error(RuntimeError)
    end
  end

  describe '#most_common_story_tag' do
    it 'returns the most frequently used active tag for user stories' do
      u = create(:user)
      t1 = create(:tag, tag: 'ruby')
      t2 = create(:tag, tag: 'rails')
      create(:story, user: u, is_deleted: false, tags_a: [t1.tag])
      create(:story, user: u, is_deleted: false, tags_a: [t1.tag])
      create(:story, user: u, is_deleted: false, tags_a: [t2.tag])
      expect(u.most_common_story_tag).to eq(t1)
    end
  end

  describe '#pushover!' do
    it 'sends a push when user_key present and does nothing otherwise' do
      u = create(:user, pushover_user_key: 'key123')
      expect(Pushover).to receive(:push).with('key123', hash_including(title: 'Hi'))
      u.pushover!(title: 'Hi', message: 'There')

      u2 = create(:user, pushover_user_key: nil)
      expect(Pushover).not_to receive(:push)
      u2.pushover!(title: 'Hi', message: 'There')
    end
  end

  describe '#recent_threads' do
    it 'returns latest thread ids for own comments' do
      viewer = create(:user)
      u = create(:user, created_at: (User::NEW_USER_DAYS + 1).days.ago)
      s1 = create(:story)
      s2 = create(:story)
      create(:comment, user: u, story: s1)
      c2 = create(:comment, user: u, story: s2)
      # put a second comment to ensure order by MAX(created_at)
      c3 = create(:comment, user: u, story: s1, created_at: 1.minute.from_now)

      ids = u.recent_threads(5, include_submitted_stories: false, for_user: viewer)
      expect(ids).to eq([c3.thread_id, c2.thread_id])
    end

    it 'can include submitted story threads when enabled' do
      u = create(:user, show_submitted_story_threads: true)
      s = create(:story, user: u)
      other = create(:user)
      c_on_submitted = create(:comment, user: other, story: s)
      ids = u.recent_threads(5, include_submitted_stories: true, for_user: u)
      expect(ids).to include(c_on_submitted.thread_id)
    end
  end

  describe '#stories_submitted_count / #stories_deleted_count' do
    it 'reads from keystore and refreshes submitted count' do
      u = create(:user)
      create(:story, user: u)
      create(:story, user: u)
      Keystore.put("user:#{u.id}:stories_deleted", 3)

      u.refresh_counts!
      expect(u.stories_submitted_count).to eq(2)
      expect(u.stories_deleted_count).to eq(3)
    end
  end

  describe '#to_param' do
    it 'uses username' do
      u = create(:user, username: 'paramuser')
      expect(u.to_param).to eq('paramuser')
    end
  end

  describe '#inbox_count' do
    it 'counts unread notifications' do
      u = create(:user)
      create(:notification, user: u, read_at: nil)
      create(:notification, user: u, read_at: nil)
      create(:notification, user: u, read_at: Time.current)
      expect(u.inbox_count).to eq(2)
    end
  end

  describe '#votes_for_others' do
    it 'returns votes not on own content, newest first' do
      voter = create(:user)
      other = create(:user)
      own_story = create(:story, user: voter)
      others_story = create(:story, user: other)
      v1 = create(:vote, user: voter, story: own_story) # should be excluded
      v2 = create(:vote, user: voter, story: others_story) # included

      own_comment = create(:comment, user: voter)
      others_comment = create(:comment, user: other)
      v3 = create(:vote, user: voter, comment: own_comment) # excluded
      v4 = create(:vote, user: voter, comment: others_comment) # included

      result = voter.votes_for_others.to_a
      expect(result).to include(v2, v4)
      expect(result).not_to include(v1, v3)
      expect(result).to eq([v4, v2]) # order by id desc
    end
  end
end
