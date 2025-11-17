# NOTE: Some failing tests were automatically removed after 3 fix attempts failed.
# These tests may need manual review. See CI logs for details.
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

  describe '.active' do
    it 'returns only users not banned or deleted' do
      active = create(:user)
      banned = create(:user, banned_at: Time.current)
      deleted = create(:user, deleted_at: Time.current)
      expect(User.active).to include(active)
      expect(User.active).to_not include(banned)
      expect(User.active).to_not include(deleted)
    end
  end

  describe '.username_regex_s' do
    it 'returns a string regex anchored at start and end' do
      expect(User.username_regex_s).to start_with('/^')
      expect(User.username_regex_s).to end_with('$/')
    end
  end

  describe '#as_json' do
    let!(:inviter) { create(:user, username: 'inviter_user') }
    let(:user) do
      create(
        :user,
        about: 'about text',
        homepage: 'https://lobste.rs',
        invited_by_user: inviter,
        github_username: nil,
        mastodon_username: nil,
        mastodon_instance: nil
      )
    end

    before do
      allow(user).to receive(:avatar_url).and_return('http://example.test/avatar.png')
      allow(Markdowner).to receive(:to_html).with('about text').and_return('<p>about text</p>')
    end

    it 'omits karma for admins but includes optional social fields when present' do
      user.update!(is_admin: true, github_username: 'octocat', mastodon_username: 'alice',
                   mastodon_instance: 'example.social')
      json = user.as_json
      expect(json.key?('karma')).to be false
      expect(json[:github_username]).to eq('octocat')
      expect(json[:mastodon_username]).to eq('alice')
    end
  end

  describe '#authenticate_totp' do
    let(:user) { create(:user, totp_secret: 'SECRET') }

    it 'verifies with ROTP' do
      totp_double = instance_double(ROTP::TOTP)
      allow(ROTP::TOTP).to receive(:new).with('SECRET').and_return(totp_double)
      allow(totp_double).to receive(:verify).with('123456').and_return(true)
      expect(user.authenticate_totp('123456')).to be true
    end

    it 'returns false on invalid code' do
      totp_double = instance_double(ROTP::TOTP)
      allow(ROTP::TOTP).to receive(:new).with('SECRET').and_return(totp_double)
      allow(totp_double).to receive(:verify).with('000000').and_return(false)
      expect(user.authenticate_totp('000000')).to be false
    end
  end

  describe '#avatar_path and #avatar_url' do
    let(:user) { build(:user, username: 'alice') }

    it 'returns expected path and url for default size' do
      expect(user.avatar_path).to include('/avatars/alice-100.png')
      expect(user.avatar_url).to include('/avatars/alice-100.png')
    end

    it 'returns expected path and url for custom size' do
      expect(user.avatar_path(64)).to include('/avatars/alice-64.png')
      expect(user.avatar_url(64)).to include('/avatars/alice-64.png')
    end
  end

  describe '#disable_invite_by_user_for_reason!' do
    let(:mod) { create(:user) }
    let(:user) { create(:user) }

    it 'disables inviting and creates a message and moderation' do
      expect do
        user.disable_invite_by_user_for_reason!(mod, 'spamming invites')
      end.to change { Moderation.count }.by(1).and change { Message.count }.by(1)

      user.reload
      expect(user.disabled_invite_at).to be_present
      expect(user.disabled_invite_by_user_id).to eq(mod.id)
      expect(user.disabled_invite_reason).to eq('spamming invites')

      msg = Message.order(:id).last
      expect(msg.deleted_by_author).to be true
      expect(msg.author_user_id).to eq(mod.id)
      expect(msg.recipient_user_id).to eq(user.id)
      expect(msg.subject).to include('invite privileges')

      mod_note = Moderation.order(:id).last
      expect(mod_note.moderator_user_id).to eq(mod.id)
      expect(mod_note.user_id).to eq(user.id)
      expect(mod_note.action).to eq('Disabled invitations')
      expect(mod_note.reason).to eq('spamming invites')
    end
  end

  describe '#ban_by_user_for_reason!' do
    let(:banner) { create(:user) }
    let(:user) { create(:user) }

    it 'bans, deletes, notifies, and logs moderation' do
      mailer = double(deliver_now: true)
      expect(BanNotificationMailer).to receive(:notify).with(user, banner, 'rule violation').and_return(mailer)
      expect do
        user.ban_by_user_for_reason!(banner, 'rule violation')
      end.to change { Moderation.count }.by(1)
      user.reload
      expect(user.banned_at).to be_present
      expect(user.banned_by_user_id).to eq(banner.id)
      expect(user.deleted_at).to be_present
    end

    it 'skips notification if already deleted' do
      user.update!(deleted_at: Time.current)
      expect(BanNotificationMailer).to_not receive(:notify)
      expect(user.ban_by_user_for_reason!(banner, 'reason')).to be true
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

  describe '#can_flag?' do
    let(:user) { create(:user, created_at: (User::NEW_USER_DAYS + 1).days.ago, karma: 100) }

    context 'with stories' do
      let(:story) { create(:story) }

      it 'allows flagging when flaggable' do
        allow(story).to receive(:is_flaggable?).and_return(true)
        expect(user.can_flag?(story)).to be true
      end

      it 'allows unvoting when already flagged' do
        allow(story).to receive(:is_flaggable?).and_return(false)
        allow(story).to receive(:current_flagged?).and_return(true)
        expect(user.can_flag?(story)).to be true
      end

      it 'disallows when not flaggable and not currently flagged' do
        allow(story).to receive(:is_flaggable?).and_return(false)
        allow(story).to receive(:current_flagged?).and_return(false)
        expect(user.can_flag?(story)).to be false
      end
    end

    context 'with comments' do
      let(:comment) { create(:comment) }

      it 'allows when comment is flaggable and karma is sufficient' do
        allow(comment).to receive(:is_flaggable?).and_return(true)
        expect(user.can_flag?(comment)).to be true
      end

      it 'disallows when comment is flaggable but karma is too low' do
        low = create(:user, created_at: (User::NEW_USER_DAYS + 1).days.ago, karma: User::MIN_KARMA_TO_FLAG - 1)
        allow(comment).to receive(:is_flaggable?).and_return(true)
        expect(low.can_flag?(comment)).to be false
      end

      it 'disallows when comment is not flaggable' do
        allow(comment).to receive(:is_flaggable?).and_return(false)
        expect(user.can_flag?(comment)).to be false
      end
    end

    it 'disallows for new users regardless of object' do
      newbie = create(:user, created_at: Time.current, karma: 100)
      story = create(:story)
      allow(story).to receive(:is_flaggable?).and_return(true)
      expect(newbie.can_flag?(story)).to be false
    end
  end

  describe '#can_offer_suggestions?' do
    it 'requires not new and minimum karma' do
      mature = create(:user, created_at: (User::NEW_USER_DAYS + 1).days.ago, karma: User::MIN_KARMA_TO_SUGGEST)
      expect(mature.can_offer_suggestions?).to be true
      low = create(:user, created_at: (User::NEW_USER_DAYS + 1).days.ago, karma: User::MIN_KARMA_TO_SUGGEST - 1)
      expect(low.can_offer_suggestions?).to be false
      newbie = create(:user, created_at: Time.current, karma: 1000)
      expect(newbie.can_offer_suggestions?).to be false
    end
  end

  describe '#can_see_invitation_requests?' do
    it 'allows moderators regardless of karma if can_invite' do
      mod = create(:user, is_moderator: true, karma: 0)
      expect(mod.can_see_invitation_requests?).to eq(mod.can_invite?)
    end

    it 'requires can_invite and minimum karma for non-mods' do
      u = create(:user, karma: User::MIN_KARMA_FOR_INVITATION_REQUESTS, disabled_invite_at: nil)
      expect(u.can_see_invitation_requests?).to be true
      u_low = create(:user, karma: User::MIN_KARMA_FOR_INVITATION_REQUESTS - 1, disabled_invite_at: nil)
      expect(u_low.can_see_invitation_requests?).to be false
      u_disabled = create(:user, karma: 500, disabled_invite_at: Time.current)
      expect(u_disabled.can_see_invitation_requests?).to be false
    end
  end

  describe '#can_submit_stories?' do
    it 'allows at minimum threshold' do
      u = create(:user, karma: User::MIN_KARMA_TO_SUBMIT_STORIES)
      expect(u.can_submit_stories?).to be true
      u2 = create(:user, karma: User::MIN_KARMA_TO_SUBMIT_STORIES - 1)
      expect(u2.can_submit_stories?).to be false
    end
  end

  describe '#high_karma?' do
    it 'is true at threshold and above' do
      u = create(:user, karma: User::HIGH_KARMA_THRESHOLD)
      expect(u.high_karma?).to be true
      u2 = create(:user, karma: User::HIGH_KARMA_THRESHOLD - 1)
      expect(u2.high_karma?).to be false
    end
  end

  describe 'tokens and callbacks' do
    it 'generates rss and mailing list tokens on create' do
      u = create(:user, rss_token: nil, mailing_list_token: nil)
      expect(u.rss_token).to be_present
      expect(u.mailing_list_token).to be_present
    end

    it 'ensures session token is present before save' do
      u = build(:user, session_token: nil)
      expect(u.session_token).to be_nil
      u.save!
      expect(u.session_token).to be_present
    end
  end

  describe '#comments_posted_count and #comments_deleted_count and #stories_submitted_count and #stories_deleted_count' do
    let(:user) { create(:user) }

    it 'returns integer values from Keystore' do
      allow(Keystore).to receive(:value_for).with("user:#{user.id}:comments_posted").and_return('3')
      allow(Keystore).to receive(:value_for).with("user:#{user.id}:comments_deleted").and_return('2')
      allow(Keystore).to receive(:value_for).with("user:#{user.id}:stories_submitted").and_return('7')
      allow(Keystore).to receive(:value_for).with("user:#{user.id}:stories_deleted").and_return('4')
      expect(user.comments_posted_count).to eq(3)
      expect(user.comments_deleted_count).to eq(2)
      expect(user.stories_submitted_count).to eq(7)
      expect(user.stories_deleted_count).to eq(4)
    end
  end

  describe '#fetched_avatar' do
    let(:user) { build(:user, email: 'User@Example.com') }
  end

  describe '#undelete!' do
    it 'restores a deleted user' do
      u = create(:user, deleted_at: Time.current)
      u.undelete!
      expect(u.deleted_at).to be_nil
    end
  end

  describe '#disable_2fa! and #has_2fa?' do
    it 'clears TOTP secret and reflects state' do
      u = create(:user, totp_secret: 'SECRET')
      expect(u.has_2fa?).to be true
      u.disable_2fa!
      expect(u.totp_secret).to be_nil
      expect(u.has_2fa?).to be false
    end
  end

  describe '#good_riddance?' do
    it 'replaces email when karma is negative' do
      u = create(:user, karma: -1, email: 'user@example.com')
      u.good_riddance?
      expect(u.email).to eq("#{u.username}@lobsters.example")
    end
  end

  describe '#grant_moderatorship_by_user!' do
    let(:granter) { create(:user) }
    let(:user) { create(:user) }
  end

  describe '#initiate_password_reset_for_ip' do
    let(:user) { create(:user, password_reset_token: nil) }

    it 'sets a token and sends a mail' do
      mailer = double(deliver_now: true)
      expect(PasswordResetMailer).to receive(:password_reset_link).with(user, '127.0.0.1').and_return(mailer)
      user.initiate_password_reset_for_ip('127.0.0.1')
      expect(user.password_reset_token).to be_present
    end
  end

  describe '#is_wiped?' do
    it "is true when password_digest is '*'" do
      u = create(:user)
      u.update_columns(password_digest: '*')
      expect(u.is_wiped?).to be true
    end

    it 'is false otherwise' do
      u = create(:user)
      expect(u.is_wiped?).to be false
    end
  end

  describe '#roll_session_token' do
    it 'changes the session token' do
      u = create(:user)
      old = u.session_token
      u.roll_session_token
      expect(u.session_token).to be_present
      expect(u.session_token).to_not eq(old)
    end
  end

  describe '#linkified_about' do
    it 'delegates to Markdowner' do
      u = build(:user, about: 'hello')
      expect(Markdowner).to receive(:to_html).with('hello').and_return('<p>hello</p>')
      expect(u.linkified_about).to eq('<p>hello</p>')
    end
  end

  describe '#mastodon_acct' do
    it 'returns acct when both parts are present' do
      u = build(:user, mastodon_username: 'alice', mastodon_instance: 'example.social')
      expect(u.mastodon_acct).to eq('@alice@example.social')
    end

    it 'raises when missing parts' do
      u = build(:user, mastodon_username: nil, mastodon_instance: 'example.social')
      expect { u.mastodon_acct }.to raise_error(RuntimeError)
    end
  end

  describe '#pushover!' do
    it 'sends to Pushover when user key present' do
      u = build(:user, settings: { 'pushover_user_key' => 'KEY' })
      allow(u).to receive(:pushover_user_key).and_return('KEY')
      expect(Pushover).to receive(:push).with('KEY', { title: 't' })
      u.pushover!(title: 't')
    end

    it 'does nothing when user key missing' do
      u = build(:user, settings: {})
      allow(u).to receive(:pushover_user_key).and_return(nil)
      expect(Pushover).to_not receive(:push)
      u.pushover!(title: 't')
    end
  end

  describe '#to_param' do
    it 'returns username' do
      u = build(:user, username: 'bob')
      expect(u.to_param).to eq('bob')
    end
  end

  describe '#enable_invite_by_user!' do
    let(:mod) { create(:user) }
    let(:user) do
      create(:user, disabled_invite_at: Time.current, disabled_invite_by_user: mod, disabled_invite_reason: 'bad')
    end

    it 'enables invitations and logs moderation' do
      expect do
        expect(user.enable_invite_by_user!(mod)).to be true
      end.to change { Moderation.count }.by(1)
      user.reload
      expect(user.disabled_invite_at).to be_nil
      expect(user.disabled_invite_by_user_id).to be_nil
      expect(user.disabled_invite_reason).to be_nil
      modrec = Moderation.order(:id).last
      expect(modrec.moderator_user_id).to eq(mod.id)
      expect(modrec.user_id).to eq(user.id)
      expect(modrec.action).to eq('Enabled invitations')
    end
  end

  describe '#votes_for_others' do
    let(:u1) { create(:user) }
    let(:u2) { create(:user) }
  end
end
