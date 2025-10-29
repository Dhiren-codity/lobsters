To create RSpec tests for the `User` model, we need to focus on the methods that perform specific business logic or service-like operations. Given the complexity and size of the `User` model, we'll focus on a few key methods that encapsulate service-like behavior, such as `ban_by_user_for_reason!`, `disable_invite_by_user_for_reason!`, `grant_moderatorship_by_user!`, and `initiate_password_reset_for_ip`.

Here's how you can structure the RSpec tests for these methods:

```ruby
# spec/models/user_spec.rb

require 'rails_helper'

RSpec.describe User, type: :model do
  let(:user) { create(:user) }
  let(:moderator) { create(:user, is_moderator: true) }
  let(:reason) { "Violation of terms" }
  let(:ip_address) { "127.0.0.1" }

  describe '#ban_by_user_for_reason!' do
    it 'bans the user and creates a moderation record' do
      expect {
        user.ban_by_user_for_reason!(moderator, reason)
      }.to change { user.reload.banned_at }.from(nil).and change { Moderation.count }.by(1)

      moderation = Moderation.last
      expect(moderation.moderator_user_id).to eq(moderator.id)
      expect(moderation.user_id).to eq(user.id)
      expect(moderation.action).to eq("Banned")
      expect(moderation.reason).to eq(reason)
    end

    it 'sends a ban notification email' do
      expect(BanNotificationMailer).to receive_message_chain(:notify, :deliver_now)
      user.ban_by_user_for_reason!(moderator, reason)
    end
  end

  describe '#disable_invite_by_user_for_reason!' do
    it 'disables invite privileges and creates a moderation record' do
      expect {
        user.disable_invite_by_user_for_reason!(moderator, reason)
      }.to change { user.reload.disabled_invite_at }.from(nil).and change { Moderation.count }.by(1)

      moderation = Moderation.last
      expect(moderation.moderator_user_id).to eq(moderator.id)
      expect(moderation.user_id).to eq(user.id)
      expect(moderation.action).to eq("Disabled invitations")
      expect(moderation.reason).to eq(reason)
    end

    it 'sends a message to the user about the invite disable' do
      expect {
        user.disable_invite_by_user_for_reason!(moderator, reason)
      }.to change { Message.count }.by(1)

      message = Message.last
      expect(message.subject).to eq("Your invite privileges have been revoked")
      expect(message.body).to include(reason)
    end
  end

  describe '#grant_moderatorship_by_user!' do
    it 'grants moderator status and creates a moderation record' do
      expect {
        user.grant_moderatorship_by_user!(moderator)
      }.to change { user.reload.is_moderator }.from(false).to(true).and change { Moderation.count }.by(1)

      moderation = Moderation.last
      expect(moderation.moderator_user_id).to eq(moderator.id)
      expect(moderation.user_id).to eq(user.id)
      expect(moderation.action).to eq("Granted moderator status")
    end

    it 'creates a Sysop hat for the user' do
      expect {
        user.grant_moderatorship_by_user!(moderator)
      }.to change { Hat.count }.by(1)

      hat = Hat.last
      expect(hat.user_id).to eq(user.id)
      expect(hat.hat).to eq("Sysop")
    end
  end

  describe '#initiate_password_reset_for_ip' do
    it 'sets a password reset token and sends a password reset email' do
      expect(PasswordResetMailer).to receive_message_chain(:password_reset_link, :deliver_now)
      expect {
        user.initiate_password_reset_for_ip(ip_address)
      }.to change { user.reload.password_reset_token }.from(nil)
    end
  end
end
```

### Explanation:

1. **Setup**: We use `let` to define reusable objects like `user` and `moderator`. This helps in setting up the test environment.

2. **Testing Methods**: Each method is tested in its own `describe` block. We test both the main functionality and any side effects (like sending emails or creating records).

3. **Expectations**: We use `expect` to assert changes in the database and to check that certain methods are called (e.g., email delivery).

4. **Isolation**: Each test is isolated, focusing on a single aspect of the method being tested.

5. **Mocks and Stubs**: We mock external dependencies like email delivery to ensure tests are fast and isolated.

This structure ensures that the tests are comprehensive, covering various scenarios and edge cases for the service-like methods in the `User` model.