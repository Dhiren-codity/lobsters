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

  describe '.active' do
    it 'returns users not banned and not deleted' do
      active = create(:user)
      banned = create(:user, :banned)
      deleted = create(:user).tap { |u| u.update_column(:deleted_at, Time.current) }

      expect(User.active).to include(active)
      expect(User.active).not_to include(banned)
      expect(User.active).not_to include(deleted)
    end
  end

  describe '.moderators' do
    it 'includes users with moderator flag' do
      mod = create(:user, is_moderator: true)
      regular = create(:user)

      expect(User.moderators).to include(mod)
      expect(User.moderators).not_to include(regular)
    end
  end

  describe '#as_json' do
    it 'includes karma for non-admins and computed fields' do
      user = create(:user, about: 'hello', homepage: 'https://example.com', karma: 10)
      allow(Markdowner).to receive(:to_html).with('hello').and_return('<p>hello</p>')

      json = user.as_json

      expect(json[:username]).to eq(user.username)
      expect(json[:homepage]).to eq('https://example.com')
      expect(json[:karma]).to eq(10)
      expect(json[:about]).to eq('<p>hello</p>')
      expect(json[:avatar_url]).to include("/avatars/#{user.username}-100.png")
    end

    it 'excludes karma for admins' do
      admin = create(:user, is_admin: true, about: 'admin about')
      allow(Markdowner).to receive(:to_html).with('admin about').and_return('html')

      json = admin.as_json
      expect(json).not_to have_key(:karma)
    end

    it 'includes invited_by_user username when present' do
      inviter = create(:user)
      invitee = create(:user, invited_by_user: inviter)
      allow(Markdowner).to receive(:to_html).and_return('')

      json = invitee.as_json
      expect(json[:invited_by_user]).to eq(inviter.username)
    end

    it 'includes github and mastodon usernames when present' do
      user = create(:user, github_username: 'octo', mastodon_username: 'mastouser',
                           mastodon_instance: 'mastodon.social')
      allow(Markdowner).to receive(:to_html).and_return('')

      json = user.as_json
      expect(json[:github_username]).to eq('octo')
      expect(json[:mastodon_username]).to eq('mastouser')
    end
  end

  describe '#authenticate_totp' do
    it 'verifies a correct TOTP code and rejects invalid' do
      secret = ROTP::Base32.random_base32
      user = create(:user, totp_secret: secret)
      totp = ROTP::TOTP.new(secret)

      expect(user.authenticate_totp(totp.now)).to be_truthy
      expect(user.authenticate_totp('000000')).to be_falsey
    end
  end

  describe '#avatar_path and #avatar_url' do
    it 'returns paths including username and size' do
      user = create(:user, username: 'alice')
      expect(user.avatar_path(80)).to include('/avatars/alice-80.png')
      expect(user.avatar_url(120)).to include('/avatars/alice-120.png')
    end
  end

  describe '#disable_invite_by_user_for_reason!' do
    it 'disables invites, sends a message, and logs moderation' do
      disabler = create(:user)
      target = create(:user)

      expect do
        target.disable_invite_by_user_for_reason!(disabler, 'spam invites')
      end.to change { Message.count }.by(1)
                                     .and change { Moderation.count }.by(1)

      target.reload
      expect(target.disabled_invite_at).to be_present
      expect(target.disabled_invite_by_user_id).to eq(disabler.id)
      expect(target.disabled_invite_reason).to eq('spam invites')

      msg = Message.order(:id).last
      expect(msg.author_user_id).to eq(disabler.id)
      expect(msg.recipient_user_id).to eq(target.id)
      expect(msg.subject).to include('invite privileges')
      expect(msg.deleted_by_author).to be true
    end
  end

  describe '#ban_by_user_for_reason!' do
    it 'bans user, deletes account, notifies, and logs moderation' do
      banner = create(:user)
      target = create(:user)
      mail_double = double(deliver_now: true)
      expect(BanNotificationMailer).to receive(:notify).with(target, banner, 'TOS violation').and_return(mail_double)

      expect do
        target.ban_by_user_for_reason!(banner, 'TOS violation')
      end.to change { Moderation.count }.by(1)

      target.reload
      expect(target.banned_at).to be_present
      expect(target.banned_by_user_id).to eq(banner.id)
      expect(target.banned_reason).to eq('TOS violation')
      expect(target.deleted_at).to be_present
    end

    it 'does not notify if already deleted' do
      banner = create(:user)
      target = create(:user, deleted_at: Time.current)
      expect(BanNotificationMailer).not_to receive(:notify)
      target.ban_by_user_for_reason!(banner, 'reason')
    end
  end

  describe '#banned_from_inviting?' do
    it 'reflects disabled_invite_at presence' do
      user = create(:user)
      expect(user.banned_from_inviting?).to be false
      user.update!(disabled_invite_at: Time.current)
      expect(user.banned_from_inviting?).to be true
    end
  end

  describe 'invitation permissions' do
    it '#can_invite? checks invite ban and story submission ability' do
      user = create(:user, karma: -10)
      expect(user.can_invite?).to be false

      user2 = create(:user, karma: -1)
      expect(user2.can_invite?).to be true

      user3 = create(:user, karma: 100, disabled_invite_at: Time.current)
      expect(user3.can_invite?).to be false
    end

    it '#can_offer_suggestions? requires not new and sufficient karma' do
      new_user = create(:user, karma: 100, created_at: Time.current)
      expect(new_user.can_offer_suggestions?).to be false

      old_low_karma = create(:user, karma: 5, created_at: (User::NEW_USER_DAYS + 1).days.ago)
      expect(old_low_karma.can_offer_suggestions?).to be false

      old_sufficient_karma = create(:user, karma: User::MIN_KARMA_TO_SUGGEST,
                                           created_at: (User::NEW_USER_DAYS + 1).days.ago)
      expect(old_sufficient_karma.can_offer_suggestions?).to be true
    end

    it '#can_see_invitation_requests? for mods or high-karma inviters' do
      not_allowed = create(:user, karma: 100, disabled_invite_at: Time.current)
      expect(not_allowed.can_see_invitation_requests?).to be false

      mod = create(:user, is_moderator: true, karma: -1)
      expect(mod.can_see_invitation_requests?).to be true

      high_karma = create(:user, karma: User::MIN_KARMA_FOR_INVITATION_REQUESTS)
      expect(high_karma.can_see_invitation_requests?).to be true

      low_karma = create(:user, karma: User::MIN_KARMA_FOR_INVITATION_REQUESTS - 1)
      expect(low_karma.can_see_invitation_requests?).to be false
    end

    it '#can_submit_stories? depends on karma threshold' do
      low = create(:user, karma: User::MIN_KARMA_TO_SUBMIT_STORIES - 1)
      ok = create(:user, karma: User::MIN_KARMA_TO_SUBMIT_STORIES)
      expect(low.can_submit_stories?).to be false
      expect(ok.can_submit_stories?).to be true
    end
  end

  describe '#high_karma?' do
    it 'is true at or above threshold' do
      low = create(:user, karma: User::HIGH_KARMA_THRESHOLD - 1)
      high = create(:user, karma: User::HIGH_KARMA_THRESHOLD)
      expect(low.high_karma?).to be false
      expect(high.high_karma?).to be true
    end
  end

  describe 'tokens and callbacks' do
    it 'sets session token before save when blank' do
      user = build(:user, session_token: nil)
      expect(user.session_token).to be_nil
      user.save!
      expect(user.session_token).to be_present
      expect(user.session_token.length).to be > 30
    end

    it 'creates mailing list and rss tokens on create' do
      user = create(:user, mailing_list_token: nil, rss_token: nil)
      expect(user.mailing_list_token).to be_present
      expect(user.rss_token).to be_present
    end
  end

  describe 'comment and story counters' do
    it '#comments_posted_count, #comments_deleted_count, #stories_submitted_count read keystore' do
      user = create(:user)
      Keystore.put("user:#{user.id}:comments_posted", 3)
      Keystore.put("user:#{user.id}:comments_deleted", 2)
      Keystore.put("user:#{user.id}:stories_submitted", 5)
      expect(user.comments_posted_count).to eq(3)
      expect(user.comments_deleted_count).to eq(2)
      expect(user.stories_submitted_count).to eq(5)
    end

    it '#refresh_counts! writes counts to keystore' do
      user = create(:user)
      create_list(:story, 3, user: user)

      # active and deleted comments
      create_list(:comment, 2, user: user, is_deleted: false)
      create(:comment, user: user, is_deleted: true)

      user.refresh_counts!

      expect(Keystore.value_for("user:#{user.id}:stories_submitted").to_i).to eq(3)
      expect(Keystore.value_for("user:#{user.id}:comments_posted").to_i).to eq(2)
      expect(Keystore.value_for("user:#{user.id}:comments_deleted").to_i).to eq(1)
    end
  end

  describe '#delete! and #undelete!' do
    it 'marks messages deleted, uses unused invites, rolls session token, and sets deleted_at' do
      user = create(:user)
      old_token = user.session_token

      # messages
      sent = create(:message, author: user, recipient: create(:user), deleted_by_author: false)
      recv = create(:message, author: create(:user), recipient: user, deleted_by_recipient: false)

      # invitations
      unused_invite = create(:invitation, user: user, used_at: nil)
      used_invite = create(:invitation, user: user, used_at: 1.day.ago)

      user.delete!
      user.reload
      sent.reload
      recv.reload
      unused_invite.reload
      used_invite.reload

      expect(user.deleted_at).to be_present
      expect(user.session_token).to be_present
      expect(user.session_token).not_to eq(old_token)
      expect(sent.deleted_by_author).to be true
      expect(recv.deleted_by_recipient).to be true
      expect(unused_invite.used_at).to be_present
      expect(used_invite.used_at).to be_present
    end

    it 'clears deleted_at on undelete!' do
      user = create(:user)
      user.delete!
      expect(user.deleted_at).to be_present
      user.undelete!
      expect(user.reload.deleted_at).to be_nil
    end
  end

  describe '#disable_2fa!' do
    it 'clears totp_secret' do
      user = create(:user, totp_secret: ROTP::Base32.random_base32)
      user.disable_2fa!
      expect(user.totp_secret).to be_nil
    end
  end

  describe '#good_riddance?' do
    it 'does nothing for banned users' do
      user = create(:user, :banned, email: 'orig@example.com', karma: -5)
      user.good_riddance?
      expect(user.email).to eq('orig@example.com')
    end

    it 'sets email to placeholder for low karma users' do
      user = create(:user, karma: -1)
      user.good_riddance?
      expect(user.email).to eq("#{user.username}@lobsters.example")
    end
  end

  describe '#grant_moderatorship_by_user!' do
    it 'sets moderator flag, logs moderation, and grants Sysop hat' do
      granter = create(:user)
      target = create(:user)

      expect do
        target.grant_moderatorship_by_user!(granter)
      end.to change { Moderation.count }.by(1)
                                        .and change { Hat.count }.by(1)

      target.reload
      expect(target.is_moderator).to be true

      hat = Hat.order(:id).last
      expect(hat.user_id).to eq(target.id)
      expect(hat.granted_by_user_id).to eq(granter.id)
      expect(hat.hat).to eq('Sysop')
    end
  end

  describe '#initiate_password_reset_for_ip' do
    it 'sets a password_reset_token and sends email' do
      user = create(:user)
      mail_double = double(deliver_now: true)
      expect(PasswordResetMailer).to receive(:password_reset_link).with(user, '127.0.0.1').and_return(mail_double)

      user.initiate_password_reset_for_ip('127.0.0.1')
      expect(user.password_reset_token).to be_present
    end
  end

  describe '#has_2fa?' do
    it 'reflects presence of totp_secret' do
      user = create(:user, totp_secret: nil)
      expect(user.has_2fa?).to be false
      user.update!(totp_secret: ROTP::Base32.random_base32)
      expect(user.has_2fa?).to be true
    end
  end

  describe '#is_wiped?' do
    it "is true when password_digest is '*'" do
      user = create(:user)
      user.update_column(:password_digest, '*')
      expect(user.is_wiped?).to be true
    end
  end

  describe '#ids_replied_to' do
    it 'returns a hash keyed by parent_comment_id that user replied to' do
      user = create(:user)
      other = create(:user)

      p1 = create(:comment)
      p2 = create(:comment)
      p3 = create(:comment)

      create(:comment, user: user, parent_comment_id: p1.id)
      create(:comment, user: user, parent_comment_id: p2.id)
      create(:comment, user: other, parent_comment_id: p1.id)

      h = user.ids_replied_to([p1.id, p2.id, p3.id])
      expect(h[p1.id]).to be true
      expect(h[p2.id]).to be true
      expect(h[p3.id]).to be false
    end
  end

  describe '#roll_session_token' do
    it 'generates a new random session token' do
      user = create(:user)
      old = user.session_token
      user.roll_session_token
      expect(user.session_token).to be_present
      expect(user.session_token).not_to eq(old)
    end
  end

  describe '#linkified_about' do
    it 'delegates to Markdowner.to_html' do
      user = create(:user, about: 'markdown')
      expect(Markdowner).to receive(:to_html).with('markdown').and_return('<p>markdown</p>')
      expect(user.linkified_about).to eq('<p>markdown</p>')
    end
  end

  describe '#mastodon_acct' do
    it 'returns acct string when username and instance present' do
      user = create(:user, mastodon_username: 'alice', mastodon_instance: 'mastodon.social')
      expect(user.mastodon_acct).to eq('@alice@mastodon.social')
    end

    it 'raises when fields missing' do
      user = create(:user, mastodon_username: nil, mastodon_instance: nil)
      expect { user.mastodon_acct }.to raise_error(RuntimeError)
    end
  end

  describe '#most_common_story_tag' do
    it "returns the tag used most often on user's non-deleted stories" do
      user = create(:user)
      t1 = create(:tag)
      t2 = create(:tag)

      create(:story, user: user, tags: [t1])
      create(:story, user: user, tags: [t1])
      create(:story, user: user, tags: [t2])

      expect(user.most_common_story_tag).to eq(t1)
    end
  end

  describe '#pushover!' do
    it 'sends a push when pushover_user_key present' do
      user = create(:user, pushover_user_key: 'key123')
      expect(Pushover).to receive(:push).with('key123', { title: 'hi' })
      user.pushover!(title: 'hi')
    end

    it 'does nothing when pushover_user_key is blank' do
      user = create(:user, pushover_user_key: nil)
      expect(Pushover).not_to receive(:push)
      user.pushover!(message: 'ignored')
    end
  end

  describe '#stories_deleted_count' do
    it 'reads from keystore' do
      user = create(:user)
      Keystore.put("user:#{user.id}:stories_deleted", 7)
      expect(user.stories_deleted_count).to eq(7)
    end
  end

  describe '#to_param' do
    it 'returns username' do
      user = create(:user, username: 'bob')
      expect(user.to_param).to eq('bob')
    end
  end

  describe '#enable_invite_by_user!' do
    it 'clears disabled invite fields and logs moderation' do
      mod = create(:user)
      user = create(:user, disabled_invite_at: Time.current, disabled_invite_by_user: mod,
                           disabled_invite_reason: 'bad')

      expect do
        user.enable_invite_by_user!(mod)
      end.to change { Moderation.count }.by(1)

      user.reload
      expect(user.disabled_invite_at).to be_nil
      expect(user.disabled_invite_by_user_id).to be_nil
      expect(user.disabled_invite_reason).to be_nil
    end
  end

  describe '#inbox_count' do
    it 'counts unread notifications' do
      user = create(:user)
      create_list(:notification, 2, user: user, read_at: nil)
      create(:notification, user: user, read_at: Time.current)
      expect(user.inbox_count).to eq(2)
    end
  end

  describe '#votes_for_others' do
    it 'returns votes on content not authored by the voter' do
      voter = create(:user)
      other = create(:user)

      own_story = create(:story, user: voter)
      other_story = create(:story, user: other)

      own_comment = create(:comment, user: voter, story: other_story)
      other_comment = create(:comment, user: other, story: own_story)

      # votes
      v1 = create(:vote, user: voter, story: own_story, comment: nil) # own story
      v2 = create(:vote, user: voter, story: other_story, comment: nil) # other's story
      v3 = create(:vote, user: voter, story: own_story, comment: other_comment) # other's comment on own story
      v4 = create(:vote, user: voter, story: other_story, comment: own_comment) # own comment

      ids = voter.votes_for_others.pluck(:id)
      expect(ids).to include(v2.id, v3.id)
      expect(ids).not_to include(v1.id, v4.id)
    end
  end
end
