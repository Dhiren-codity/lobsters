require 'rails_helper'

RSpec.describe LoginController, type: :controller do
  let(:user) { create(:user) }
  let(:banned_user) { create(:user, :banned) }
  let(:wiped_user) { create(:user, :wiped) }
  let(:inactive_user) { create(:user, :inactive) }
  let(:user_with_2fa) { create(:user, :with_2fa) }

  describe 'POST #login' do
    context 'when user is not found' do
      it 'renders the index with an error' do
        post :login, params: { email: 'nonexistent@example.com', password: 'password' }
        expect(flash.now[:error]).to eq('Invalid e-mail address and/or password.')
        expect(response).to render_template('index')
      end
    end

    context 'when user is wiped' do
      it 'renders the index with an error' do
        post :login, params: { email: wiped_user.email, password: 'password' }
        expect(flash.now[:error]).to include('Your account was banned or deleted')
        expect(response).to render_template('index')
      end
    end

    context 'when password is too long' do
      it 'renders the index with an error' do
        long_password = 'a' * 73
        post :login, params: { email: user.email, password: long_password }
        expect(flash.now[:error]).to include('BCrypt passwords need to be less than 72 bytes')
        expect(response).to render_template('index')
      end
    end

    context 'when password is incorrect' do
      it 'renders the index with an error' do
        post :login, params: { email: user.email, password: 'wrongpassword' }
        expect(flash.now[:error]).to eq('Invalid e-mail address and/or password.')
        expect(response).to render_template('index')
      end
    end

    context 'when user is banned' do
      it 'renders the index with an error' do
        post :login, params: { email: banned_user.email, password: 'password' }
        expect(flash.now[:error]).to include('Your account has been banned.')
        expect(response).to render_template('index')
      end
    end

    context 'when user is inactive' do
      it 'renders the index with an error' do
        post :login, params: { email: inactive_user.email, password: 'password' }
        expect(flash.now[:error]).to eq('You deleted your account.')
        expect(response).to render_template('index')
      end
    end

    context 'when user has 2FA enabled' do
      it 'redirects to 2FA page' do
        post :login, params: { email: user_with_2fa.email, password: 'password' }
        expect(response).to redirect_to('/login/2fa')
      end
    end

    context 'when login is successful' do
      it 'redirects to root path' do
        post :login, params: { email: user.email, password: 'password' }
        expect(session[:u]).to eq(user.session_token)
        expect(response).to redirect_to('/')
      end
    end
  end

  describe 'POST #reset_password' do
    context 'when user is not found' do
      it 'renders forgot_password with an error' do
        post :reset_password, params: { email: 'nonexistent@example.com' }
        expect(flash.now[:error]).to eq('Unknown e-mail address or username.')
        expect(response).to render_template(:forgot_password)
      end
    end

    context 'when user is banned' do
      it 'renders forgot_password with an error' do
        post :reset_password, params: { email: banned_user.email }
        expect(flash.now[:error]).to eq('Your account has been banned.')
        expect(response).to render_template(:forgot_password)
      end
    end

    context 'when user is wiped' do
      it 'renders forgot_password with an error' do
        post :reset_password, params: { email: wiped_user.email }
        expect(flash.now[:error]).to include("It's not possible to reset your password")
        expect(response).to render_template(:forgot_password)
      end
    end

    context 'when reset is successful' do
      it 'renders index with a success message' do
        post :reset_password, params: { email: user.email }
        expect(flash.now[:success]).to eq('Password reset instructions have been e-mailed to you.')
        expect(response).to render_template('index')
      end
    end
  end

  describe 'POST #set_new_password' do
    let(:reset_user) { create(:user, password_reset_token: '12345-67890') }

    context 'when token is invalid' do
      it 'redirects to forgot_password' do
        post :set_new_password, params: { password_reset_token: 'invalid-token' }
        expect(flash[:error]).to include('Invalid reset token')
        expect(response).to redirect_to(forgot_password_path)
      end
    end

    context 'when token is valid' do
      it 'resets the password and redirects to root' do
        post :set_new_password, params: { password_reset_token: reset_user.password_reset_token, password: 'newpassword', password_confirmation: 'newpassword' }
        expect(response).to redirect_to('/')
      end
    end
  end

  describe 'POST #twofa_verify' do
    context 'when TOTP code is invalid' do
      it 'redirects to 2FA page with an error' do
        session[:twofa_u] = user_with_2fa.session_token
        post :twofa_verify, params: { totp_code: 'invalid' }
        expect(flash[:error]).to include('Your TOTP code did not match')
        expect(response).to redirect_to('/login/2fa')
      end
    end

    context 'when TOTP code is valid' do
      it 'redirects to root path' do
        allow_any_instance_of(User).to receive(:authenticate_totp).and_return(true)
        session[:twofa_u] = user_with_2fa.session_token
        post :twofa_verify, params: { totp_code: 'valid' }
        expect(response).to redirect_to('/')
      end
    end
  end
end