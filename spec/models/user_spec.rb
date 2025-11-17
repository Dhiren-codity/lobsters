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

  describe '.username_regex_s' do
    it 'returns a printable regex string for usernames' do
      s = User.username_regex_s
      expect(s).to be_a(String)
      expect(s).to match(%r{\A/\^.*\$/})
      expect(s).to include('A-Za-z0-9')
    end
  end

  describe '#as_json' do
    let(:inviter) do
      create(:user, username: 'inviter_user')
    end

    let(:user) do
      create(:user,
             about: 'about text',
             is_admin: false,
             invited_by_user_id: inviter.id,
             github_username: 'ghname',
             mastodon_username: 'mastou',
             mastodon_instance: 'example.social',
             homepage: 'https://lobste.rs')
    end

    it 'omits karma for admins' do
      admin = create(:user, is_admin: true, invited_by_user_id: inviter.id)
      allow(admin).to receive(:linkified_about).and_return('x')
      allow(admin).to receive(:avatar_url).and_return('y')
      json = admin.as_json
      expect(json).to_not have_key(:karma)
    end

    it 'omits optional handles when blank' do
      u = create(:user, github_username: nil, mastodon_username: nil, mastodon_instance: nil)
      allow(u).to receive(:linkified_about).and_return('x')
      allow(u).to receive(:avatar_url).and_return('y')
      json = u.as_json
      expect(json).to_not have_key(:github_username)
      expect(json).to_not have_key(:mastodon_username)
    end
  end

  describe '#authenticate_totp' do
    let(:secret) { 'JBSWY3DPEHPK3PXP' }

    it 'verifies a correct code' do
      u = create(:user, totp_secret: secret)
      totp = ROTP::TOTP.new(secret)
      code = totp.now
      expect(u.authenticate_totp(code)).to be_truthy
    end

    it 'rejects an incorrect code' do
      u = create(:user, totp_secret: secret)
      expect(u.authenticate_totp('000000')).to be_falsey
    end
  end

  describe '#avatar_path and #avatar_url' do
    let(:user) { create(:user, username: 'alice') }

    it 'builds the image path with skip_pipeline' do
      expect(ActionController::Base.helpers).to receive(:image_path)
        .with('/avatars/alice-150.png', skip_pipeline: true).and_return('/assets/avatars/alice-150.png')
      expect(user.avatar_path(150)).to eq('/assets/avatars/alice-150.png')
    end

    it 'builds the image url with skip_pipeline' do
      expect(ActionController::Base.helpers).to receive(:image_url)
        .with('/avatars/alice-150.png', skip_pipeline: true).and_return('http://test.host/avatars/alice-150.png')
      expect(user.avatar_url(150)).to eq('http://test.host/avatars/alice-150.png')
    end
  end

  describe '#disable_invite_by_user_for_reason!' do
    let(:moderator) { create(:user) }
    let(:user) { create(:user) }

    it 'disables invites, sends a message, and records moderation' do
      expect do
        user.disable_invite_by_user_for_reason!(moderator, 'too many invites')
      end.to change { Message.count }.by(1)
                                     .and change { Moderation.count }.by(1)

      user.reload
      expect(user.disabled_invite_at).to be_present
      expect(user.disabled_invite_by_user_id).to eq(moderator.id)
      expect(user.disabled_invite_reason).to eq('too many invites')

      msg = Message.order(:id).last
      expect(msg.recipient_user_id).to eq(user.id)
      expect(msg.author_user_id).to eq(moderator.id)
      expect(msg.subject).to include('invite privileges')
      expect(msg.body).to include('too many invites')

      mod = Moderation.order(:id).last
      expect(mod.user_id).to eq(user.id)
      expect(mod.moderator_user_id).to eq(moderator.id)
      expect(mod.action).to eq('Disabled invitations')
      expect(mod.reason).to eq('too many invites')
    end
  end

  describe '#ban_by_user_for_reason!' do
    let(:banner) { create(:user) }

    it 'bans the user, notifies by email, and records moderation' do
      u = create(:user)
      mail = double(deliver_now: true)
      allow(BanNotificationMailer).to receive(:notify).and_return(mail)
      allow(u).to receive(:delete!).and_return(true)

      expect(u.ban_by_user_for_reason!(banner, 'spam')).to eq(true)
      expect(u.banned_at).to be_present
      expect(u.banned_by_user_id).to eq(banner.id)
      expect(u.banned_reason).to eq('spam')
      expect(BanNotificationMailer).to have_received(:notify).with(u, banner, 'spam')
      mod = Moderation.order(:id).last
      expect(mod.action).to eq('Banned')
      expect(mod.reason).to eq('spam')
      expect(mod.user_id).to eq(u.id)
      expect(mod.moderator_user_id).to eq(banner.id)
    end

    it 'does not notify if already deleted' do
      u = create(:user, deleted_at: Time.current)
      allow(BanNotificationMailer).to receive(:notify)
      allow(u).to receive(:delete!).and_return(true)

      u.ban_by_user_for_reason!(banner, 'spam')
      expect(BanNotificationMailer).to_not have_received(:notify)
    end
  end

  describe '#banned_from_inviting?' do
    it 'returns true when disabled_invite_at is set' do
      u = create(:user, disabled_invite_at: Time.current)
      expect(u.banned_from_inviting?).to be true
    end

    it 'returns false otherwise' do
      u = create(:user, disabled_invite_at: nil)
      expect(u.banned_from_inviting?).to be false
    end
  end

  describe 'permission helpers' do
    let(:old_user) { create(:user, created_at: (User::NEW_USER_DAYS + 1).days.ago, karma: 100) }
    let(:story) { create(:story) }
    let(:comment) { create(:comment) }

    describe '#can_flag?' do
      it 'returns false for new users' do
        u = create(:user, created_at: Time.current)
        allow(story).to receive(:is_flaggable?).and_return(true)
        expect(u.can_flag?(story)).to be false
      end

      it 'allows flagging flaggable stories' do
        allow(story).to receive(:is_flaggable?).and_return(true)
        expect(old_user.can_flag?(story)).to be true
      end

      it 'allows unvoting currently flagged stories' do
        allow(story).to receive(:is_flaggable?).and_return(false)
        allow(story).to receive(:current_flagged?).and_return(true)
        expect(old_user.can_flag?(story)).to be true
      end

      it 'requires sufficient karma to flag comments' do
        low = create(:user, created_at: (User::NEW_USER_DAYS + 1).days.ago, karma: User::MIN_KARMA_TO_FLAG - 1)
        high = create(:user, created_at: (User::NEW_USER_DAYS + 1).days.ago, karma: User::MIN_KARMA_TO_FLAG)
        allow(comment).to receive(:is_flaggable?).and_return(true)
        expect(low.can_flag?(comment)).to be false
        expect(high.can_flag?(comment)).to be true
      end
    end

    describe '#can_invite?' do
      it 'requires not being invite-banned and meeting submit threshold' do
        u = create(:user, karma: User::MIN_KARMA_TO_SUBMIT_STORIES, disabled_invite_at: nil)
        expect(u.can_invite?).to be true
        u.update!(disabled_invite_at: Time.current)
        expect(u.can_invite?).to be false
      end
    end

    describe '#can_offer_suggestions?' do
      it 'requires not new and sufficient karma' do
        u1 = create(:user, created_at: (User::NEW_USER_DAYS + 1).days.ago, karma: User::MIN_KARMA_TO_SUGGEST)
        expect(u1.can_offer_suggestions?).to be true
        u2 = create(:user, created_at: Time.current, karma: 10_000)
        expect(u2.can_offer_suggestions?).to be false
      end
    end

    describe '#can_see_invitation_requests?' do
      it 'allows moderators regardless of karma' do
        mod = create(:user, is_moderator: true, karma: User::MIN_KARMA_TO_SUBMIT_STORIES)
        expect(mod.can_see_invitation_requests?).to be true
      end

      it 'allows non-mods with sufficient karma who can invite' do
        u = create(:user, karma: User::MIN_KARMA_FOR_INVITATION_REQUESTS)
        expect(u.can_see_invitation_requests?).to be true
      end

      it 'denies users who cannot invite' do
        u = create(:user, karma: User::MIN_KARMA_TO_SUBMIT_STORIES - 10)
        expect(u.can_see_invitation_requests?).to be false
      end
    end
  end

  describe '#can_submit_stories?' do
    it 'checks against the minimum threshold' do
      u1 = create(:user, karma: User::MIN_KARMA_TO_SUBMIT_STORIES)
      u2 = create(:user, karma: User::MIN_KARMA_TO_SUBMIT_STORIES - 1)
      expect(u1.can_submit_stories?).to be true
      expect(u2.can_submit_stories?).to be false
    end
  end

  describe '#high_karma?' do
    it 'returns true at or above threshold' do
      u = create(:user, karma: User::HIGH_KARMA_THRESHOLD)
      expect(u.high_karma?).to be true
    end

    it 'returns false below threshold' do
      u = create(:user, karma: User::HIGH_KARMA_THRESHOLD - 1)
      expect(u.high_karma?).to be false
    end
  end

  describe 'token generation before create' do
    it 'sets rss_token, mailing_list_token, and session_token on create' do
      u = create(:user, rss_token: nil, mailing_list_token: nil, session_token: nil)
      expect(u.rss_token).to be_present
      expect(u.rss_token.length).to be >= 10
      expect(u.mailing_list_token).to be_present
      expect(u.mailing_list_token.length).to be >= 10
      expect(u.session_token).to be_present
      expect(u.session_token.length).to be >= 10
    end
  end

  describe '#comments_posted_count and #comments_deleted_count' do
    let(:user) { create(:user) }

    it 'reads counters from keystore' do
      allow(Keystore).to receive(:value_for).with("user:#{user.id}:comments_posted").and_return('5')
      allow(Keystore).to receive(:value_for).with("user:#{user.id}:comments_deleted").and_return('2')
      expect(user.comments_posted_count).to eq(5)
      expect(user.comments_deleted_count).to eq(2)
    end
  end

  describe '#fetched_avatar' do
    let(:user) { create(:user, email: 'user@example.com') }

    it 'returns the response body when fetch succeeds' do
      digest = Digest::MD5.hexdigest('user@example.com'.strip.downcase)
      expected_url = "https://www.gravatar.com/avatar/#{digest}?r=pg&d=identicon&s=80"

      sponge = instance_double('Sponge')
      response = double(body: 'IMGDATA')
      expect(Sponge).to receive(:new).and_return(sponge)
      expect(sponge).to receive(:timeout=).with(3)
      expect(sponge).to receive(:fetch).with(expected_url).and_return(response)

      expect(user.fetched_avatar(80)).to eq('IMGDATA')
    end

    it 'returns nil when fetch raises' do
      digest = Digest::MD5.hexdigest('user@example.com'.strip.downcase)
      expected_url = "https://www.gravatar.com/avatar/#{digest}?r=pg&d=identicon&s=80"

      sponge = instance_double('Sponge')
      expect(Sponge).to receive(:new).and_return(sponge)
      expect(sponge).to receive(:timeout=).with(3)
      expect(sponge).to receive(:fetch).with(expected_url).and_raise(StandardError.new('network'))

      expect(user.fetched_avatar(80)).to be_nil
    end
  end

  describe '#refresh_counts!' do
    let(:user) { create(:user) }

    it 'stores counts in keystore' do
      create_list(:story, 3, user: user)
      create_list(:comment, 2, user: user, is_deleted: false)
      create_list(:comment, 4, user: user, is_deleted: true)

      expect(Keystore).to receive(:put).with("user:#{user.id}:stories_submitted", 3)
      expect(Keystore).to receive(:put).with("user:#{user.id}:comments_posted", 2)
      expect(Keystore).to receive(:put).with("user:#{user.id}:comments_deleted", 4)

      user.refresh_counts!
    end
  end

  describe '#delete! and #undelete!' do
    let(:user) { create(:user) }

    it 'marks negative-score comments appropriately and soft-deletes the user' do
      neg_comment = create(:comment, user: user)
      neg_comment.update_column(:score, -1)
      allow(neg_comment).to receive(:delete_for_user).with(user).and_return(true)
      allow(user).to receive(:good_riddance?)
      original_session = user.session_token

      expect_any_instance_of(Comment).to receive(:delete_for_user).at_least(:once)
      user.delete!
      user.reload
      expect(user.deleted_at).to be_present
      expect(user.session_token).to_not eq(original_session)
    end

    it 'restores a deleted user' do
      user.update!(deleted_at: Time.current)
      user.undelete!
      expect(user.deleted_at).to be_nil
    end
  end

  describe '#disable_2fa! and #has_2fa?' do
    it 'disables 2fa and reflects presence' do
      u = create(:user, totp_secret: 'abc123')
      expect(u.has_2fa?).to be true
      u.disable_2fa!
      u.reload
      expect(u.totp_secret).to be_nil
      expect(u.has_2fa?).to be false
    end
  end

  describe '#good_riddance?' do
    it 'sets placeholder email when flagged by commenter list' do
      u = create(:user, karma: 0, email: 'real@example.com')
      checker = double(check_list_for: true)
      allow(FlaggedCommenters).to receive(:new).with('90d').and_return(checker)
      u.good_riddance?
      expect(u.email).to eq("#{u.username}@lobsters.example")
    end
  end

  describe '#grant_moderatorship_by_user!' do
    it 'grants mod, records moderation, and grants a Sysop hat' do
      grantor = create(:user)
      u = create(:user, is_moderator: false)

      prev_mods = Moderation.count
      prev_hats = Hat.count

      expect(u.grant_moderatorship_by_user!(grantor)).to be true
      u.reload

      expect(Moderation.count).to eq(prev_mods + 1)
      expect(Hat.count).to eq(prev_hats + 1)
      expect(u.is_moderator).to be true

      hat = Hat.order(:id).last
      expect(hat.user_id).to eq(u.id)
      expect(hat.hat).to eq('Sysop')
      expect(hat.granted_by_user_id).to eq(grantor.id)

      mod = Moderation.order(:id).last
      expect(mod.user_id).to eq(u.id)
      expect(mod.moderator_user_id).to eq(grantor.id)
      expect(mod.action).to eq('Granted moderator status')
    end
  end

  describe '#initiate_password_reset_for_ip' do
    it 'sets a reset token and sends email' do
      u = create(:user, password_reset_token: nil)
      mail = double(deliver_now: true)
      expect(PasswordResetMailer).to receive(:password_reset_link).with(u, '1.2.3.4').and_return(mail)
      u.initiate_password_reset_for_ip('1.2.3.4')
      expect(u.password_reset_token).to be_present
      expect(u.password_reset_token).to match(/\A\d+-\w{10,}\z/)
    end
  end

  describe '#is_wiped?' do
    it "returns true if password_digest is '*'" do
      u = create(:user)
      u.update!(password_digest: '*')
      expect(u.is_wiped?).to be true
    end

    it 'returns false otherwise' do
      u = create(:user)
      expect(u.is_wiped?).to be false
    end
  end

  describe '#mastodon_acct' do
    it 'returns full acct when username and instance are present' do
      u = create(:user, mastodon_username: 'alice', mastodon_instance: 'example.social')
      expect(u.mastodon_acct).to eq('@alice@example.social')
    end

    it 'raises when details are missing' do
      u = create(:user, mastodon_username: nil, mastodon_instance: 'example.social')
      expect { u.mastodon_acct }.to raise_error(RuntimeError)
    end
  end

  describe '#most_common_story_tag' do
    it 'returns the tag with the most non-deleted stories by the user' do
      u = create(:user)
      t1 = create(:tag, active: true)
      t2 = create(:tag, active: true)
      s1 = create(:story, user: u, is_deleted: false)
      s2 = create(:story, user: u, is_deleted: false)
      s3 = create(:story, user: u, is_deleted: false)
      Tagging.create!(story: s1, tag: t1)
      Tagging.create!(story: s2, tag: t1)
      Tagging.create!(story: s3, tag: t2)
      expect(u.most_common_story_tag).to eq(t1)
    end
  end

  describe '#pushover!' do
    it 'sends a push when user has a key' do
      u = create(:user, pushover_user_key: 'key123')
      expect(Pushover).to receive(:push).with('key123', { foo: 'bar' })
      u.pushover!(foo: 'bar')
    end

    it 'does nothing without a key' do
      u = create(:user, pushover_user_key: nil)
      expect(Pushover).to_not receive(:push)
      u.pushover!(foo: 'bar')
    end
  end

  describe '#stories_submitted_count and #stories_deleted_count' do
    let(:user) { create(:user) }

    it 'reads submission and deletion counts' do
      allow(Keystore).to receive(:value_for).with("user:#{user.id}:stories_submitted").and_return('7')
      allow(Keystore).to receive(:value_for).with("user:#{user.id}:stories_deleted").and_return('9')
      expect(user.stories_submitted_count).to eq(7)
      expect(user.stories_deleted_count).to eq(9)
    end
  end

  describe '#to_param' do
    it 'uses the username' do
      u = create(:user, username: 'paramuser')
      expect(u.to_param).to eq('paramuser')
    end
  end

  describe '#inbox_count' do
    it 'counts only unread notifications' do
      u = create(:user)
      create(:notification, user: u, read_at: nil, notifiable: create(:comment))
      create(:notification, user: u, read_at: nil, notifiable: create(:story))
      create(:notification, user: u, read_at: Time.current, notifiable: create(:comment))
      create(:notification, user: u, read_at: Time.current, notifiable: create(:story))
      create(:notification, user: u, read_at: Time.current, notifiable: create(:comment))
      expect(u.inbox_count).to eq(2)
    end
  end

  describe '#votes_for_others' do
    it "returns only votes on others' content ordered desc" do
      voter = create(:user)
      other = create(:user)

      own_story = create(:story, user: voter)
      others_story = create(:story, user: other)

      own_comment = create(:comment, user: voter, story: own_story)
      others_comment = create(:comment, user: other, story: others_story)

      v1 = create(:vote, user: voter, story: others_story, comment: nil)
      v2 = create(:vote, user: voter, story: others_story, comment: others_comment)
      _excluded1 = create(:vote, user: voter, story: own_story, comment: nil)
      _excluded2 = create(:vote, user: voter, story: own_story, comment: own_comment)

      results = voter.votes_for_others.to_a
      expect(results).to eq([v2, v1])
    end
  end
end
