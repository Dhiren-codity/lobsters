To create RSpec tests for the `User` model, we need to focus on the methods that perform significant logic or interact with external systems. Given the complexity and size of the `User` model, I'll provide a sample RSpec test suite that covers some of the key methods. This will include testing validations, scopes, and some of the more complex methods like `ban_by_user_for_reason!`, `disable_invite_by_user_for_reason!`, and `authenticate_totp`.

Here's a sample RSpec test suite for the `User` model:

```ruby
# spec/models/user_spec.rb

require 'rails_helper'

RSpec.describe User, type: :model do
  let(:user) { create(:user) }
  let(:moderator) { create(:user, is_moderator: true) }
  let(:disabler) { create(:user) }
  let(:banner) { create(:user) }

  describe 'validations' do
    it { should validate_presence_of(:username) }
    it { should validate_uniqueness_of(:username).case_insensitive }
    it { should validate_presence_of(:email) }
    it { should validate_uniqueness_of(:email).case_insensitive }
    it { should validate_length_of(:email).is_at_most(100) }
    it { should allow_value('user@example.com').for(:email) }
    it { should_not allow_value('userexample.com').for(:email) }
    it { should validate_presence_of(:password).on(:create) }
  end

  describe 'scopes' do
    describe '.active' do
      it 'returns only active users' do
        active_user = create(:user, banned_at: nil, deleted_at: nil)
        banned_user = create(:user, banned_at: Time.current)
        deleted_user = create(:user, deleted_at: Time.current)

        expect(User.active).to include(active_user)
        expect(User.active).not_to include(banned_user)
        expect(User.active).not_to include(deleted_user)
      end
    end

    describe '.moderators' do
      it 'returns only moderators' do
        moderator_user = create(:user, is_moderator: true)
        non_moderator_user = create(:user, is_moderator: false)

        expect(User.moderators).to include(moderator_user)
        expect(User.moderators).not_to include(non_moderator_user)
      end
    end
  end

  describe '#ban_by_user_for_reason!' do
    it 'bans the user and creates a moderation record' do
      reason = 'Violation of terms'
      expect {
        user.ban_by_user_for_reason!(banner, reason)
      }.to change { user.reload.banned_at }.from(nil).to(be_within(1.second).of(Time.current))

      moderation = Moderation.last
      expect(moderation.moderator_user_id).to eq(banner.id)
      expect(moderation.user_id).to eq(user.id)
      expect(moderation.action).to eq('Banned')
      expect(moderation.reason).to eq(reason)
    end
  end

  describe '#disable_invite_by_user_for_reason!' do
    it 'disables invite privileges and creates a moderation record' do
      reason = 'Spamming invites'
      expect {
        user.disable_invite_by_user_for_reason!(disabler, reason)
      }.to change { user.reload.disabled_invite_at }.from(nil).to(be_within(1.second).of(Time.current))

      moderation = Moderation.last
      expect(moderation.moderator_user_id).to eq(disabler.id)
      expect(moderation.user_id).to eq(user.id)
      expect(moderation.action).to eq('Disabled invitations')
      expect(moderation.reason).to eq(reason)
    end
  end

  describe '#authenticate_totp' do
    let(:totp_secret) { 'base32secret3232' }
    let(:user) { create(:user, totp_secret: totp_secret) }

    it 'authenticates with a valid TOTP code' do
      totp = ROTP::TOTP.new(totp_secret)
      code = totp.now
      expect(user.authenticate_totp(code)).to be_truthy
    end

    it 'fails to authenticate with an invalid TOTP code' do
      expect(user.authenticate_totp('123456')).to be_falsey
    end
  end

  describe '#is_new?' do
    it 'returns true for a new user' do
      new_user = create(:user, created_at: 10.days.ago)
      expect(new_user.is_new?).to be_truthy
    end

    it 'returns false for an old user' do
      old_user = create(:user, created_at: 100.days.ago)
      expect(old_user.is_new?).to be_falsey
    end
  end

  # Add more tests for other methods as needed
end
```

### Explanation:

1. **Validations**: We test the presence, uniqueness, and format of attributes like `username` and `email`.

2. **Scopes**: We test the `active` and `moderators` scopes to ensure they return the correct users.

3. **Methods**:
   - `ban_by_user_for_reason!`: We test that the user is banned and a moderation record is created.
   - `disable_invite_by_user_for_reason!`: We test that invite privileges are disabled and a moderation record is created.
   - `authenticate_totp`: We test TOTP authentication with valid and invalid codes.
   - `is_new?`: We test the logic for determining if a user is considered new.

4. **Setup**: We use `let` to define reusable objects like `user`, `moderator`, `disabler`, and `banner`.

5. **RSpec Matchers**: We use matchers like `be_within` to handle time-based assertions and `change` to test state changes.

This is a starting point, and you can expand the test suite to cover more methods and edge cases as needed.