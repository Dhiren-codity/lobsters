To create RSpec tests for the `LoginController` service methods, we need to focus on the main actions that involve significant logic, such as `login`, `reset_password`, and `set_new_password`. We'll mock external dependencies like database calls and ensure that we cover various scenarios, including success, failure, and edge cases.

Here's a sample RSpec test suite for the `LoginController`:

```ruby
# spec/controllers/login_controller_spec.rb

require 'rails_helper'

RSpec.describe LoginController, type: :controller do
  let(:user) { instance_double(User) }
  let(:banned_user) { instance_double(User, is_banned?: true, banned_reason: "Violation of terms") }
  let(:wiped_user) { instance_double(User, is_wiped?: true) }
  let(:inactive_user) { instance_double(User, is_active?: false) }
  let(:valid_password) { 'valid_password' }
  let(:long_password) { 'a' * 73 }
  let(:valid_email) { 'user@example.com' }
  let(:valid_username) { 'username' }

  before do
    allow(User).to receive(:where).and_return([user])
    allow(user).to receive(:is_wiped?).and_return(false)
    allow(user).to receive(:is_banned?).and_return(false)
    allow(user).to receive(:is_active?).and_return(true)
    allow(user).to receive(:authenticate).and_return(true)
    allow(user).to receive(:session_token).and_return('session_token')
    allow(user).to receive(:has_2fa?).and_return(false)
    allow(user).to receive(:password_digest).and_return('$2a$12$example')
  end

  describe 'POST #login' do
    context 'with valid credentials' do
      it 'logs in the user and redirects to root' do
        post :login, params: { email: valid_email, password: valid_password }
        expect(session[:u]).to eq('session_token')
        expect(response).to redirect_to('/')
      end
    end

    context 'with invalid email' do
      before { allow(User).to receive(:where).and_return([]) }

      it 'renders the index with an error message' do
        post :login, params: { email: 'invalid@example.com', password: valid_password }
        expect(flash.now[:error]).to eq('Invalid e-mail address and/or password.')
        expect(response).to render_template('index')
      end
    end

    context 'with wiped user' do
      before { allow(user).to receive(:is_wiped?).and_return(true) }

      it 'renders the index with an error message' do
        post :login, params: { email: valid_email, password: valid_password }
        expect(flash.now[:error]).to include('Your account was banned or deleted')
        expect(response).to render_template('index')
      end
    end

    context 'with password too long' do
      it 'renders the index with an error message' do
        post :login, params: { email: valid_email, password: long_password }
        expect(flash.now[:error]).to include('BCrypt passwords need to be less than 72 bytes')
        expect(response).to render_template('index')
      end
    end

    context 'with banned user' do
      before { allow(User).to receive(:where).and_return([banned_user]) }

      it 'renders the index with an error message' do
        post :login, params: { email: valid_email, password: valid_password }
        expect(flash.now[:error]).to include('Your account has been banned')
        expect(response).to render_template('index')
      end
    end

    context 'with inactive user' do
      before { allow(User).to receive(:where).and_return([inactive_user]) }

      it 'renders the index with an error message' do
        post :login, params: { email: valid_email, password: valid_password }
        expect(flash.now[:error]).to include('You deleted your account.')
        expect(response).to render_template('index')
      end
    end
  end

  describe 'POST #reset_password' do
    let(:found_user) { instance_double(User) }

    before do
      allow(User).to receive(:where).and_return([found_user])
      allow(found_user).to receive(:is_banned?).and_return(false)
      allow(found_user).to receive(:is_wiped?).and_return(false)
      allow(found_user).to receive(:initiate_password_reset_for_ip)
    end

    context 'with valid email' do
      it 'initiates password reset and renders index with success message' do
        post :reset_password, params: { email: valid_email }
        expect(flash.now[:success]).to include('Password reset instructions have been e-mailed to you.')
        expect(response).to render_template('index')
      end
    end

    context 'with unknown email' do
      before { allow(User).to receive(:where).and_return([]) }

      it 'renders forgot_password with an error message' do
        post :reset_password, params: { email: 'unknown@example.com' }
        expect(flash.now[:error]).to include('Unknown e-mail address or username.')
        expect(response).to render_template(:forgot_password)
      end
    end

    context 'with banned user' do
      before { allow(found_user).to receive(:is_banned?).and_return(true) }

      it 'renders forgot_password with an error message' do
        post :reset_password, params: { email: valid_email }
        expect(flash.now[:error]).to include('Your account has been banned.')
        expect(response).to render_template(:forgot_password)
      end
    end

    context 'with wiped user' do
      before { allow(found_user).to receive(:is_wiped?).and_return(true) }

      it 'renders forgot_password with an error message' do
        post :reset_password, params: { email: valid_email }
        expect(flash.now[:error]).to include('your account was deleted before the site changed admins')
        expect(response).to render_template(:forgot_password)
      end
    end
  end

  describe 'POST #set_new_password' do
    let(:reset_user) { instance_double(User, is_banned?: false, is_active?: true, has_2fa?: false) }

    before do
      allow(User).to receive(:where).and_return([reset_user])
      allow(reset_user).to receive(:save).and_return(true)
      allow(reset_user).to receive(:roll_session_token)
    end

    context 'with valid reset token and password' do
      it 'resets the password and redirects to root' do
        post :set_new_password, params: { password_reset_token: "#{Time.current.to_i}-token", password: valid_password, password_confirmation: valid_password }
        expect(session[:u]).to eq(reset_user.session_token)
        expect(response).to redirect_to('/')
      end
    end

    context 'with invalid reset token' do
      it 'redirects to forgot_password with an error message' do
        post :set_new_password, params: { password_reset_token: 'invalid-token', password: valid_password, password_confirmation: valid_password }
        expect(flash[:error]).to include('Invalid reset token')
        expect(response).to redirect_to(forgot_password_path)
      end
    end

    context 'with banned user' do
      before { allow(reset_user).to receive(:is_banned?).and_return(true) }

      it 'redirects to forgot_password with an error message' do
        post :set_new_password, params: { password_reset_token: "#{Time.current.to_i}-token", password: valid_password, password_confirmation: valid_password }
        expect(flash[:error]).to include('Invalid reset token')
        expect(response).to redirect_to(forgot_password_path)
      end
    end
  end
end
```

### Key Points:
- **Mocks and Stubs**: We use `instance_double` to create mock objects for `User` and stub methods to simulate different scenarios.
- **Error Handling**: We test various error conditions, such as invalid credentials, banned users, and wiped accounts.
- **Edge Cases**: We handle edge cases like long passwords and invalid reset tokens.
- **Isolation**: Each test is isolated, focusing on a specific scenario without side effects on others.
- **Fast Execution**: By mocking database calls and other dependencies, tests run quickly without hitting the actual database.