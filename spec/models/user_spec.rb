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

  describe '.username_regex_s' do
    it 'returns a string regex with anchors and no ruby flags' do
      s = User.username_regex_s
      expect(s).to start_with('/^')
      expect(s).to end_with('$/')
      expect(s).not_to include('?-mix')
      expect(s).not_to include('(')
      expect(s).not_to include(')')
    end
  end

  describe '#as_json' do
    it 'includes expected fields and derived values for non-admin users' do
      inviter = create(:user, username: 'inviter_user')
      user = create(:user,
                    username: 'alice',
                    karma: 42,
                    about: 'Hello',
                    homepage: 'https://lobste.rs',
                    invited_by_user_id: inviter.id,
                    github_username: 'alicegh',
                    mastodon_username: 'alicem',
                    mastodon_instance: 'example.social')
      allow(Markdowner).to receive(:to_html).with('Hello').and_return('<p>Hello</p>')
      json = user.as_json.with_indifferent_access
      expect(json[:username]).to eq('alice')
      expect(json).to have_key(:created_at)
      expect(json[:is_admin]).to eq(false)
      expect(json[:is_moderator]).to eq(false)
      expect(json[:karma]).to eq(42)
      expect(json[:about]).to eq('<p>Hello</p>')
      expect(json[:avatar_url]).to include('/avatars/alice-100.png')
      expect(json[:invited_by_user]).to eq('inviter_user')
      expect(json[:github_username]).to eq('alicegh')
      expect(json[:mastodon_username]).to eq('alicem')
    end

    it 'omits karma for admin users' do
      user = create(:user, is_admin: true, about: '')
      allow(Markdowner).to receive(:to_html).and_return('')
      json = user.as_json.with_indifferent_access
      expect(json).not_to have_key(:karma)
    end
  end

  describe '#authenticate_totp' do
    it 'verifies a correct TOTP code' do
      secret = 'JBSWY3DPEHPK3PXP'
      user = build(:user, totp_secret: secret)
      code = ROTP::TOTP.new(secret).now
      expect(user.authenticate_totp(code)).to be_truthy
    end

    it 'rejects an invalid TOTP code' do
      user = build(:user, totp_secret: 'JBSWY3DPEHPK3PXP')
      expect(user.authenticate_totp('000000')).to be_falsey
    end
  end

  describe '#avatar_path and #avatar_url' do
    it 'return expected path and url for default size' do
      user = build(:user, username: 'bob')
      expect(user.avatar_path).to include('/avatars/bob-100.png')
      expect(user.avatar_url).to include('/avatars/bob-100.png')
    end

    it 'return expected path and url for custom size' do
      user = build(:user, username: 'carol')
      expect(user.avatar_path(50)).to include('/avatars/carol-50.png')
      expect(user.avatar_url(50)).to include('/avatars/carol-50.png')
    end
  end

  describe '#disable_invite_by_user_for_reason!' do
    it 'disables invites, sends a message, and logs moderation' do
      mod = create(:user)
      user = create(:user)
      reason = 'abuse of invite privileges'
      result = user.disable_invite_by_user_for_reason!(mod, reason)
      user.reload

      expect(result).to eq(true)
      expect(user.disabled_invite_at).to be_present
      expect(user.disabled_invite_by_user_id).to eq(mod.id)
      expect(user.disabled_invite_reason).to eq(reason)

      msg = Message.where(recipient_user_id: user.id).order(:id).last
      expect(msg).to be_present
      expect(msg.author_user_id).to eq(mod.id)
      expect(msg.deleted_by_author).to eq(true)
      expect(msg.subject).to include('revoked')
      expect(msg.body).to include(reason)

      modlog = Moderation.where(user_id: user.id, moderator_user_id: mod.id).order(:id).last
      expect(modlog).to be_present
      expect(modlog.action).to eq('Disabled invitations')
      expect(modlog.reason).to eq(reason)

      expect(user.banned_from_inviting?).to eq(true)
    end
  end

  describe '#enable_invite_by_user!' do
    it 're-enables invites and logs moderation' do
      mod = create(:user)
      user = create(:user)
      user.disable_invite_by_user_for_reason!(mod, 'temp')
      user.reload

      expect(user.enable_invite_by_user!(mod)).to eq(true)
      user.reload

      expect(user.disabled_invite_at).to be_nil
      expect(user.disabled_invite_by_user_id).to be_nil
      expect(user.disabled_invite_reason).to be_nil

      modlog = Moderation.where(user_id: user.id, action: 'Enabled invitations').order(:id).last
      expect(modlog).to be_present
      expect(modlog.moderator_user_id).to eq(mod.id)
    end
  end

  describe '#ban_by_user_for_reason!' do
    it 'bans, notifies, deletes the user, and logs moderation' do
      banner = create(:user)
      user = create(:user, karma: 10, email: 'foo@example.com') # ensure good_riddance? will not change email
      mailer_double = double(deliver_now: true)
      expect(BanNotificationMailer).to receive(:notify).with(user, banner, 'spammer').and_return(mailer_double)

      expect(user.ban_by_user_for_reason!(banner, 'spammer')).to eq(true)
      user.reload

      expect(user.is_banned?).to eq(true)
      expect(user.deleted_at).to be_present
      expect(user.banned_by_user_id).to eq(banner.id)
      expect(user.banned_reason).to eq('spammer')

      modlog = Moderation.where(user_id: user.id, action: 'Banned').order(:id).last
      expect(modlog).to be_present
      expect(modlog.moderator_user_id).to eq(banner.id)
      expect(modlog.reason).to eq('spammer')
    end
  end

  describe '#banned_from_inviting?' do
    it 'reflects disabled_invite_at presence' do
      user = create(:user)
      expect(user.banned_from_inviting?).to eq(false)
      mod = create(:user)
      user.disable_invite_by_user_for_reason!(mod, 'x')
      user.reload
      expect(user.banned_from_inviting?).to eq(true)
    end
  end

  describe 'invitation permission helpers' do
    it '#can_invite? depends on invite ban and story submission karma' do
      user = create(:user, karma: User::MIN_KARMA_TO_SUBMIT_STORIES)
      expect(user.can_invite?).to eq(true)
      user.update!(karma: User::MIN_KARMA_TO_SUBMIT_STORIES - 1)
      expect(user.can_invite?).to eq(false)

      mod = create(:user)
      user.update!(karma: 0)
      user.disable_invite_by_user_for_reason!(mod, 'nope')
      user.reload
      expect(user.can_invite?).to eq(false)
    end

    it '#can_offer_suggestions? requires not new and sufficient karma' do
      old_enough = create(:user, created_at: (User::NEW_USER_DAYS + 1).days.ago, karma: User::MIN_KARMA_TO_SUGGEST)
      expect(old_enough.can_offer_suggestions?).to eq(true)

      low_karma = create(:user, created_at: (User::NEW_USER_DAYS + 1).days.ago, karma: User::MIN_KARMA_TO_SUGGEST - 1)
      expect(low_karma.can_offer_suggestions?).to eq(false)

      new_user = create(:user, created_at: Time.current, karma: 100)
      expect(new_user.can_offer_suggestions?).to eq(false)
    end

    it '#can_see_invitation_requests? requires can_invite? and moderator or high karma' do
      moderator = create(:user, is_moderator: true, karma: 0)
      expect(moderator.can_invite?).to eq(true)
      expect(moderator.can_see_invitation_requests?).to eq(true)

      high_karma = create(:user, karma: User::MIN_KARMA_FOR_INVITATION_REQUESTS)
      expect(high_karma.can_invite?).to eq(true)
      expect(high_karma.can_see_invitation_requests?).to eq(true)

      low_karma = create(:user, karma: User::MIN_KARMA_FOR_INVITATION_REQUESTS - 1)
      expect(low_karma.can_see_invitation_requests?).to eq(false)

      cannot_invite = create(:user, karma: User::MIN_KARMA_TO_SUBMIT_STORIES - 1)
      expect(cannot_invite.can_invite?).to eq(false)
      expect(cannot_invite.can_see_invitation_requests?).to eq(false)
    end

    it '#can_submit_stories? respects minimum karma threshold' do
      u = create(:user, karma: User::MIN_KARMA_TO_SUBMIT_STORIES)
      expect(u.can_submit_stories?).to eq(true)
      u.update!(karma: User::MIN_KARMA_TO_SUBMIT_STORIES - 1)
      expect(u.can_submit_stories?).to eq(false)
    end

    it '#high_karma? reflects the threshold' do
      u = create(:user, karma: User::HIGH_KARMA_THRESHOLD)
      expect(u.high_karma?).to eq(true)
      u.update!(karma: User::HIGH_KARMA_THRESHOLD - 1)
      expect(u.high_karma?).to eq(false)
    end
  end

  describe 'token generation callbacks' do
    it 'rolls session token if blank on save' do
      u = build(:user, session_token: nil)
      u.save!
      expect(u.session_token).to be_present
      expect(u.session_token.length).to be >= 20
    end

    it 'creates rss and mailing list tokens on create' do
      u = create(:user)
      expect(u.rss_token).to be_present
      expect(u.rss_token.length).to be >= 20
      expect(u.mailing_list_token).to be_present
      expect(u.mailing_list_token.length).to be >= 5
    end
  end

  describe 'comment count helpers and refresh_counts!' do
    it 'refreshes and reads posted and deleted comment counts via Keystore' do
      u = create(:user)
      s = create(:story, user: u)
      create(:comment, user: u, story: s, is_deleted: false)
      create(:comment, user: u, story: s, is_deleted: false)
      create(:comment, user: u, story: s, is_deleted: true)

      u.refresh_counts!
      expect(u.comments_posted_count).to eq(2)
      expect(u.comments_deleted_count).to eq(1)
    end
  end

  describe '#delete! and #undelete!' do
    it 'marks user deleted, rolls session token, and updates messages and invitations' do
      u = create(:user)
      old_token = u.session_token.dup
      other = create(:user)
      sent = create(:message, author: u, recipient: other, deleted_by_author: false)
      received = create(:message, author: other, recipient: u, deleted_by_recipient: false)
      inv = create(:invitation, user: u, used_at: nil)

      u.delete!
      u.reload
      sent.reload
      received.reload
      inv.reload

      expect(u.deleted_at).to be_present
      expect(u.session_token).to be_present
      expect(u.session_token).not_to eq(old_token)
      expect(sent.deleted_by_author).to eq(true)
      expect(received.deleted_by_recipient).to eq(true)
      expect(inv.used_at).to be_present

      u.undelete!
      u.reload
      expect(u.deleted_at).to be_nil
    end
  end

  describe '2FA helpers' do
    it '#has_2fa? and #disable_2fa!' do
      u = create(:user, totp_secret: 'SECRET')
      expect(u.has_2fa?).to eq(true)
      u.disable_2fa!
      u.reload
      expect(u.has_2fa?).to eq(false)
      expect(u.totp_secret).to be_nil
    end
  end

  describe '#grant_moderatorship_by_user!' do
    it 'grants moderator, creates modlog and Sysop hat' do
      admin = create(:user)
      u = create(:user)
      expect(u.is_moderator).to eq(false)
      expect(u.grant_moderatorship_by_user!(admin)).to eq(true)
      u.reload
      expect(u.is_moderator).to eq(true)
      modlog = Moderation.where(user_id: u.id, action: 'Granted moderator status').last
      expect(modlog).to be_present
      expect(modlog.moderator_user_id).to eq(admin.id)
      hat = Hat.where(user_id: u.id, hat: 'Sysop').last
      expect(hat).to be_present
      expect(hat.granted_by_user_id).to eq(admin.id)
    end
  end

  describe '#initiate_password_reset_for_ip' do
    it 'sets a token and sends password reset email' do
      u = create(:user)
      mailer_double = double(deliver_now: true)
      expect(PasswordResetMailer).to receive(:password_reset_link).with(u, '127.0.0.1').and_return(mailer_double)
      u.initiate_password_reset_for_ip('127.0.0.1')
      u.reload
      expect(u.password_reset_token).to be_present
      expect(u.password_reset_token).to match(/^\d+-/)
    end
  end

  describe '#mastodon_acct' do
    it 'returns fully qualified account when both parts present' do
      u = build(:user, mastodon_username: 'alice', mastodon_instance: 'example.social')
      expect(u.mastodon_acct).to eq('@alice@example.social')
    end

    it 'raises when parts are missing' do
      u = build(:user, mastodon_username: 'alice', mastodon_instance: nil)
      expect { u.mastodon_acct }.to raise_error(RuntimeError)
    end
  end

  describe '#most_common_story_tag' do
    it 'returns the most frequently used tag for user stories' do
      u = create(:user)
      tag1 = create(:tag)
      tag2 = create(:tag)
      create(:story, user: u, tags: [tag1])
      create(:story, user: u, tags: [tag1])
      create(:story, user: u, tags: [tag2])
      expect(u.most_common_story_tag).to eq(tag1)
    end
  end

  describe '#pushover!' do
    it 'sends a notification when user_key is present' do
      u = create(:user, pushover_user_key: 'key123')
      expect(Pushover).to receive(:push).with('key123', hash_including(message: 'hi'))
      u.pushover!(message: 'hi')
    end

    it 'does nothing when user_key is missing' do
      u = create(:user, pushover_user_key: nil)
      expect(Pushover).not_to receive(:push)
      u.pushover!(message: 'hi')
    end
  end

  describe '#recent_threads' do
    it 'returns most recent thread_ids for user comments' do
      u = create(:user)
      viewer = create(:user)
      s = create(:story)
      c_old = create(:comment, user: u, story: s, created_at: 2.days.ago)
      c_new = create(:comment, user: u, story: s, created_at: 1.day.ago)
      result = u.recent_threads(2, include_submitted_stories: false, for_user: viewer)
      expect(result).to eq([c_new.thread_id, c_old.thread_id])
    end

    it 'includes submitted story threads when enabled' do
      u = create(:user, show_submitted_story_threads: true)
      viewer = create(:user)
      s1 = create(:story, user: u)
      s2 = create(:story, user: u)
      # Comments in those threads by others to create threads
      c1 = create(:comment, user: viewer, story: s1, created_at: 3.days.ago)
      c2 = create(:comment, user: viewer, story: s2, created_at: 1.day.ago)

      result = u.recent_threads(2, include_submitted_stories: true, for_user: viewer)
      expect(result).to include(c2.thread_id).and include(c1.thread_id)
    end
  end

  describe 'story and notification counters' do
    it '#stories_submitted_count reads from Keystore and #refresh_counts! writes it' do
      u = create(:user)
      create(:story, user: u)
      create(:story, user: u)
      u.refresh_counts!
      expect(u.stories_submitted_count).to eq(2)
    end

    it '#stories_deleted_count reads from Keystore' do
      u = create(:user)
      Keystore.put("user:#{u.id}:stories_deleted", 3)
      expect(u.stories_deleted_count).to eq(3)
    end

    it '#inbox_count counts unread notifications' do
      u = create(:user)
      create(:notification, user: u, notifiable: create(:comment), read_at: nil)
      create(:notification, user: u, notifiable: create(:comment), read_at: Time.current)
      expect(u.inbox_count).to eq(1)
    end
  end

  describe '#to_param' do
    it 'returns username' do
      u = create(:user, username: 'paramuser')
      expect(u.to_param).to eq('paramuser')
    end
  end

  describe '#votes_for_others' do
    it 'returns only votes on content not owned by the voting user, newest first' do
      u = create(:user)
      other = create(:user)
      story_by_other = create(:story, user: other)
      story_by_self = create(:story, user: u)
      comment_by_other = create(:comment, user: other, story: story_by_other)
      comment_by_self = create(:comment, user: u, story: story_by_self)

      v1 = create(:vote, user: u, story: story_by_other) # included
      v2 = create(:vote, user: u, story: story_by_self)  # excluded
      v3 = create(:vote, user: u, comment: comment_by_other, story: story_by_other) # included
      v4 = create(:vote, user: u, comment: comment_by_self, story: story_by_self) # excluded

      result = u.votes_for_others.to_a
      expect(result).to eq([v3, v1]) # newest first
      expect(result).not_to include(v2)
      expect(result).not_to include(v4)
    end
  end

  describe '#can_flag?' do
    it 'allows flagging a flaggable story and unflagging a currently flagged story' do
      u = create(:user, created_at: (User::NEW_USER_DAYS + 1).days.ago)
      story = build(:story)
      allow(story).to receive(:is_flaggable?).and_return(true)
      allow(story).to receive(:current_flagged?).and_return(false)
      expect(u.can_flag?(story)).to eq(true)

      allow(story).to receive(:is_flaggable?).and_return(false)
      allow(story).to receive(:current_flagged?).and_return(true)
      expect(u.can_flag?(story)).to eq(true)
    end

    it 'requires sufficient karma to flag a comment' do
      comment = build(:comment)
      allow(comment).to receive(:is_flaggable?).and_return(true)

      low = create(:user, created_at: (User::NEW_USER_DAYS + 1).days.ago, karma: User::MIN_KARMA_TO_FLAG - 1)
      high = create(:user, created_at: (User::NEW_USER_DAYS + 1).days.ago, karma: User::MIN_KARMA_TO_FLAG)

      expect(low.can_flag?(comment)).to eq(false)
      expect(high.can_flag?(comment)).to eq(true)
    end

    it 'disallows new users from flagging' do
      new_user = create(:user, created_at: Time.current, karma: 100)
      story = build(:story)
      allow(story).to receive(:is_flaggable?).and_return(true)
      expect(new_user.can_flag?(story)).to eq(false)
    end
  end
end
