require 'rails_helper'
RSpec.describe User, type: :model do
  describe '#authenticate_totp' do
    let(:secret) { ROTP::Base32.random_base32 }
    let(:user) { create(:user, totp_secret: secret) }

    it 'returns true for a valid current code' do
      code = ROTP::TOTP.new(secret).now
      expect(user.authenticate_totp(code)).to be_truthy
    end

    it 'returns false for an invalid code' do
      expect(user.authenticate_totp('000000')).to be_falsey
    end
  end

  describe '#avatar_path' do
    let(:user) { create(:user, username: 'alice') }

    it 'returns a relative path with default size' do
      expect(user.avatar_path).to eq('/avatars/alice-100.png')
    end

    it 'returns a relative path with custom size' do
      expect(user.avatar_path(64)).to eq('/avatars/alice-64.png')
    end
  end

  describe '#avatar_url' do
    let(:user) { create(:user, username: 'bob') }

    it 'returns a full URL with default size' do
      url = user.avatar_url
      expect(url).to include('/avatars/bob-100.png')
    end

    it 'returns a full URL with custom size' do
      url = user.avatar_url(32)
      expect(url).to include('/avatars/bob-32.png')
    end
  end

  describe '#disable_invite_by_user_for_reason!' do
    let(:mod) { create(:user) }
    let(:user) { create(:user) }

    it 'disables invites, sends a message, and logs moderation' do
      expect {
        expect(user.disable_invite_by_user_for_reason!(mod, 'abuse')).to eq(true)
      }.to change { Moderation.count }.by(1)
       .and change { Message.count }.by(1)

      user.reload
      expect(user.disabled_invite_at).to be_present
      expect(user.disabled_invite_by_user_id).to eq(mod.id)
      expect(user.disabled_invite_reason).to eq('abuse')

      m = Moderation.order(:id).last
      expect(m.moderator_user_id).to eq(mod.id)
      expect(m.user_id).to eq(user.id)
      expect(m.action).to eq('Disabled invitations')
      expect(m.reason).to eq('abuse')

      msg = Message.order(:id).last
      expect(msg.author_user_id).to eq(mod.id)
      expect(msg.recipient_user_id).to eq(user.id)
      expect(msg.deleted_by_author).to be true
      expect(msg.subject).to include('invite privileges')
      expect(msg.body).to include('abuse')
    end
  end

  describe '#ban_by_user_for_reason!' do
    let(:banner) { create(:user) }
    let(:user) { create(:user) }

    before do
      mail_double = double(deliver_now: true)
      allow(BanNotificationMailer).to receive(:notify).and_return(mail_double)
      allow(FlaggedCommenters).to receive(:new).and_return(double(check_list_for: false))
    end

    it 'bans, deletes, notifies, and logs moderation' do
      expect {
        expect(user.ban_by_user_for_reason!(banner, 'spam')).to eq(true)
      }.to change { Moderation.count }.by(1)

      expect(BanNotificationMailer).to have_received(:notify).with(user, banner, 'spam')

      user.reload
      expect(user.is_banned?).to be true
      expect(user.deleted_at).to be_present

      m = Moderation.order(:id).last
      expect(m.moderator_user_id).to eq(banner.id)
      expect(m.user_id).to eq(user.id)
      expect(m.action).to eq('Banned')
      expect(m.reason).to eq('spam')
    end
  end

  describe '#banned_from_inviting?' do
    it 'is true when disabled_invite_at is set' do
      user = create(:user, disabled_invite_at: Time.current)
      expect(user.banned_from_inviting?).to be true
    end

    it 'is false when disabled_invite_at is nil' do
      user = create(:user, disabled_invite_at: nil)
      expect(user.banned_from_inviting?).to be false
    end
  end

  describe '#can_flag?' do
    let(:user) { create(:user, created_at: (User::NEW_USER_DAYS + 1).days.ago, karma: 100) }

    it 'returns false for new users' do
      new_user = create(:user, created_at: Time.current, karma: 100)
      story = create(:story)
      allow(story).to receive(:is_flaggable?).and_return(true)
      expect(new_user.can_flag?(story)).to be false
    end

    it 'allows flagging of flaggable stories' do
      story = create(:story)
      allow(story).to receive(:is_flaggable?).and_return(true)
      expect(user.can_flag?(story)).to be true
    end

    it 'allows unvoting of already flagged stories' do
      story = create(:story)
      allow(story).to receive(:is_flaggable?).and_return(false)
      allow(story).to receive(:current_flagged?).and_return(true)
      expect(user.can_flag?(story)).to be true
    end

    it 'requires minimum karma for comments' do
      low = create(:user, created_at: (User::NEW_USER_DAYS + 1).days.ago, karma: User::MIN_KARMA_TO_FLAG - 1)
      high = create(:user, created_at: (User::NEW_USER_DAYS + 1).days.ago, karma: User::MIN_KARMA_TO_FLAG)
      comment = create(:comment)
      allow(comment).to receive(:is_flaggable?).and_return(true)
      expect(low.can_flag?(comment)).to be false
      expect(high.can_flag?(comment)).to be true
    end
  end

  describe '#can_invite?' do
    it 'is false when invites are disabled' do
      user = create(:user, disabled_invite_at: Time.current, karma: 100)
      expect(user.can_invite?).to be false
    end

    it 'is false when user cannot submit stories' do
      user = create(:user, karma: User::MIN_KARMA_TO_SUBMIT_STORIES - 1)
      expect(user.can_invite?).to be false
    end

    it 'is true when invites enabled and user can submit stories' do
      user = create(:user, karma: User::MIN_KARMA_TO_SUBMIT_STORIES)
      expect(user.can_invite?).to be true
    end
  end

  describe '#can_offer_suggestions?' do
    it 'is false when user is new' do
      user = create(:user, created_at: Time.current, karma: 100)
      expect(user.can_offer_suggestions?).to be false
    end

    it 'is false when karma is below threshold' do
      user = create(:user, created_at: (User::NEW_USER_DAYS + 1).days.ago, karma: User::MIN_KARMA_TO_SUGGEST - 1)
      expect(user.can_offer_suggestions?).to be false
    end

    it 'is true when not new and karma sufficient' do
      user = create(:user, created_at: (User::NEW_USER_DAYS + 1).days.ago, karma: User::MIN_KARMA_TO_SUGGEST)
      expect(user.can_offer_suggestions?).to be true
    end
  end

  describe '#can_see_invitation_requests?' do
    it 'is true for moderators with invite ability' do
      user = create(:user, is_moderator: true, karma: 100)
      expect(user.can_see_invitation_requests?).to be true
    end

    it 'is true when can invite and has enough karma' do
      user = create(:user, karma: User::MIN_KARMA_FOR_INVITATION_REQUESTS)
      expect(user.can_see_invitation_requests?).to be true
    end

    it 'is false when cannot invite' do
      user = create(:user, karma: User::MIN_KARMA_FOR_INVITATION_REQUESTS - 1)
      expect(user.can_see_invitation_requests?).to be false
    end
  end

  describe '#can_submit_stories?' do
    it 'checks minimum karma' do
      low = create(:user, karma: User::MIN_KARMA_TO_SUBMIT_STORIES - 1)
      ok = create(:user, karma: User::MIN_KARMA_TO_SUBMIT_STORIES)
      expect(low.can_submit_stories?).to be false
      expect(ok.can_submit_stories?).to be true
    end
  end

  describe '#high_karma?' do
    it 'is false below threshold and true at/above threshold' do
      low = create(:user, karma: User::HIGH_KARMA_THRESHOLD - 1)
      high = create(:user, karma: User::HIGH_KARMA_THRESHOLD)
      expect(low.high_karma?).to be false
      expect(high.high_karma?).to be true
    end
  end

  describe '#check_session_token' do
    it 'ensures a session token is set on save' do
      user = create(:user, session_token: nil)
      expect(user.session_token).to be_present

      old = user.session_token
      user.update!(session_token: nil)
      user.reload
      expect(user.session_token).to be_present
      expect(user.session_token).not_to eq(old)
    end
  end

  describe 'token generation on create' do
    it 'creates rss_token and mailing_list_token' do
      user = create(:user)
      expect(user.rss_token).to be_present
      expect(user.rss_token.length).to eq(60)
      expect(user.mailing_list_token).to be_present
      expect(user.mailing_list_token.length).to eq(10)
    end
  end

  describe '#comments_posted_count and #comments_deleted_count' do
    let(:user) { create(:user) }

    it 'reads counts from keystore' do
      Keystore.put("user:#{user.id}:comments_posted", 5)
      Keystore.put("user:#{user.id}:comments_deleted", 2)
      expect(user.comments_posted_count).to eq(5)
      expect(user.comments_deleted_count).to eq(2)
    end
  end

  describe '#refresh_counts!' do
    let(:user) { create(:user) }
    let!(:story) { create(:story, user: user, is_deleted: false) }
    let!(:comment_active) { create(:comment, user: user, is_deleted: false) }
    let!(:comment_deleted) { create(:comment, user: user, is_deleted: true) }

    it 'updates keystore counts for stories and comments' do
      user.refresh_counts!
      expect(Keystore.value_for("user:#{user.id}:stories_submitted").to_i).to eq(1)
      expect(Keystore.value_for("user:#{user.id}:comments_posted").to_i).to eq(1)
      expect(Keystore.value_for("user:#{user.id}:comments_deleted").to_i).to eq(1)
    end
  end

  describe '#delete!' do
    let(:user) { create(:user, karma: 1, email: 'user@example.com') }
    let!(:invitation) { create(:invitation, user: user, used_at: nil) }

    before do
      allow(FlaggedCommenters).to receive(:new).and_return(double(check_list_for: false))
    end

    it 'marks invitations used, sets deleted_at, and rolls session token' do
      old_token = user.session_token
      user.delete!
      user.reload

      expect(user.deleted_at).to be_present
      expect(user.session_token).to be_present
      expect(user.session_token).not_to eq(old_token)

      expect(invitation.reload.used_at).to be_present
      expect(user.email).to eq('user@example.com')
    end
  end

  describe '#undelete!' do
    it 'clears deleted_at' do
      user = create(:user, deleted_at: Time.current)
      user.undelete!
      expect(user.reload.deleted_at).to be_nil
    end
  end

  describe '#disable_2fa!' do
    it 'clears totp_secret and saves' do
      user = create(:user, totp_secret: ROTP::Base32.random_base32)
      user.disable_2fa!
      expect(user.reload.totp_secret).to be_nil
    end
  end

  describe '#good_riddance?' do
    it 'replaces email for users with negative karma' do
      user = build(:user, karma: -1, username: 'neguser', email: 'neg@example.com')
      user.good_riddance?
      expect(user.email).to eq('neguser@lobsters.example')
    end

    it 'does nothing if banned' do
      user = build(:user, :banned, karma: -10, username: 'banned', email: 'banned@example.com')
      user.good_riddance?
      expect(user.email).to eq('banned@example.com')
    end
  end

  describe '#grant_moderatorship_by_user!' do
    let(:grantor) { create(:user) }
    let(:grantee) { create(:user) }

    it 'grants moderator status, creates moderation and a Sysop hat' do
      expect {
        expect(grantee.grant_moderatorship_by_user!(grantor)).to eq(true)
      }.to change { Moderation.count }.by(1)
       .and change { Hat.count }.by(1)

      grantee.reload
      expect(grantee.is_moderator).to be true

      m = Moderation.order(:id).last
      expect(m.moderator_user_id).to eq(grantor.id)
      expect(m.user_id).to eq(grantee.id)
      expect(m.action).to eq('Granted moderator status')

      h = Hat.order(:id).last
      expect(h.user_id).to eq(grantee.id)
      expect(h.granted_by_user_id).to eq(grantor.id)
      expect(h.hat).to eq('Sysop')
    end
  end

  describe '#initiate_password_reset_for_ip' do
    let(:user) { create(:user) }

    it 'sets a reset token and sends email' do
      mail_double = double(deliver_now: true)
      expect(PasswordResetMailer).to receive(:password_reset_link).with(user, '1.2.3.4').and_return(mail_double)
      expect {
        user.initiate_password_reset_for_ip('1.2.3.4')
      }.to change { user.reload.password_reset_token.present? }.from(false).to(true)
    end
  end

  describe '#has_2fa?' do
    it 'is true when totp_secret present' do
      user = build(:user, totp_secret: 'secret')
      expect(user.has_2fa?).to be true
    end

    it 'is false when totp_secret missing' do
      user = build(:user, totp_secret: nil)
      expect(user.has_2fa?).to be false
    end
  end

  describe '#as_json' do
    let(:user) { create(:user, about: 'About me', homepage: 'https://lobste.rs', github_username: 'gh', mastodon_username: 'md', mastodon_instance: 'example.social') }

    before do
      allow(Markdowner).to receive(:to_html).and_return('<p>About me</p>')
    end

    it 'includes public attributes for non-admin users' do
      h = user.as_json
      expect(h[:username]).to eq(user.username)
      expect(h[:homepage]).to eq('https://lobste.rs')
      expect(h[:about]).to eq('<p>About me</p>')
      expect(h[:avatar_url]).to include("/avatars/#{user.username}-100.png")
      expect(h[:karma]).to eq(user.karma)
      expect(h[:github_username]).to eq('gh')
      expect(h[:mastodon_username]).to eq('md')
    end
  end

  describe '#mastodon_acct' do
    it 'returns full acct when username and instance present' do
      user = build(:user, mastodon_username: 'alice', mastodon_instance: 'example.com')
      expect(user.mastodon_acct).to eq('@alice@example.com')
    end

    it 'raises when missing fields' do
      user = build(:user, mastodon_username: nil, mastodon_instance: 'example.com')
      expect { user.mastodon_acct }.to raise_error(RuntimeError)
    end
  end

  describe '#pushover!' do
    it 'pushes when user_key present' do
      user = create(:user, pushover_user_key: 'key123')
      expect(Pushover).to receive(:push).with('key123', hash_including(title: 'Hello'))
      user.pushover!(title: 'Hello', message: 'World')
    end

    it 'does nothing when user_key missing' do
      user = create(:user, pushover_user_key: nil)
      expect(Pushover).not_to receive(:push)
      user.pushover!(title: 'Hello')
    end
  end

  describe '#stories_submitted_count and #stories_deleted_count' do
    let(:user) { create(:user) }

    it 'reads counts from keystore' do
      Keystore.put("user:#{user.id}:stories_submitted", 7)
      Keystore.put("user:#{user.id}:stories_deleted", 3)
      expect(user.stories_submitted_count).to eq(7)
      expect(user.stories_deleted_count).to eq(3)
    end
  end

  describe '#to_param' do
    it 'returns username' do
      user = create(:user, username: 'paramuser')
      expect(user.to_param).to eq('paramuser')
    end
  end

  describe '#enable_invite_by_user!' do
    let(:mod) { create(:user) }
    let(:user) { create(:user, disabled_invite_at: Time.current, disabled_invite_by_user_id: mod.id, disabled_invite_reason: 'abuse') }

    it 'clears invite disable fields and logs moderation' do
      expect {
        expect(user.enable_invite_by_user!(mod)).to eq(true)
      }.to change { Moderation.count }.by(1)

      user.reload
      expect(user.disabled_invite_at).to be_nil
      expect(user.disabled_invite_by_user_id).to be_nil
      expect(user.disabled_invite_reason).to be_nil

      m = Moderation.order(:id).last
      expect(m.moderator_user_id).to eq(mod.id)
      expect(m.user_id).to eq(user.id)
      expect(m.action).to eq('Enabled invitations')
    end
  end

  describe '#inbox_count' do
    let(:user) { create(:user) }
    let!(:n1) { create(:notification, user: user, read_at: nil) }
    let!(:n2) { create(:notification, user: user, read_at: 1.day.ago) }

    it 'counts unread notifications' do
      expect(user.inbox_count).to eq(1)
      n1.update!(read_at: Time.current)
      expect(user.inbox_count).to eq(0)
    end
  end
end