require 'rails_helper'

RSpec.describe LoginController, type: :controller do
  let(:user) { create(:user) }
  let(:banned_user) { create(:user, :banned) }
  let(:wiped_user) { create(:user, :wiped) }
  let(:deleted_user) { create(:user, :deleted) }

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
        expect(flash.now[:error]).to eq('Your account was banned or deleted before the site changed admins. Your email and password hash were wiped for privacy.')
        expect(response).to render_template('index')
      end
    end

    context 'when password is too long' do
      it 'renders the index with an error' do
        post :login, params: { email: user.email, password: 'a' * 73 }
        expect(flash.now[:error]).to eq("BCrypt passwords need to be less than 72 bytes, you'll have to reset to set a shorter one, sorry for the hassle.")
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
        expect(flash.now[:error]).to eq("Your account has been banned. Log: #{banned_user.banned_reason}")
        expect(response).to render_template('index')
      end
    end

    context 'when user is deleted' do
      it 'renders the index with an error' do
        post :login, params: { email: deleted_user.email, password: 'password' }
        expect(flash.now[:error]).to eq('You deleted your account.')
        expect(response).to render_template('index')
      end
    end

    context 'when login is successful' do
      it 'redirects to the root path' do
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
        expect(flash.now[:error]).to eq("It's not possible to reset your password because your account was deleted before the site changed admins and your email address was wiped for privacy.")
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
    let(:reset_user) { create(:user, password_reset_token: "#{Time.current.to_i}-token") }

    context 'when token is invalid' do
      it 'redirects to forgot_password with an error' do
        post :set_new_password, params: { password_reset_token: 'invalid-token' }
        expect(flash[:error]).to eq('Invalid reset token.  It may have already been used or you may have copied it incorrectly.')
        expect(response).to redirect_to(forgot_password_path)
      end
    end

    context 'when token is valid' do
      it 'resets the password and redirects to root' do
        post :set_new_password, params: { password_reset_token: reset_user.password_reset_token, password: 'newpassword', password_confirmation: 'newpassword' }
        expect(session[:u]).to eq(reset_user.reload.session_token)
        expect(response).to redirect_to('/')
      end
    end
  end

  describe 'POST #twofa_verify' do
    let(:twofa_user) { create(:user, :with_2fa) }

    before do
      session[:twofa_u] = twofa_user.session_token
    end

    context 'when TOTP code is invalid' do
      it 'redirects to /login/2fa with an error' do
        post :twofa_verify, params: { totp_code: 'invalid' }
        expect(flash[:error]).to eq('Your TOTP code did not match.  Please try again.')
        expect(response).to redirect_to('/login/2fa')
      end
    end

    context 'when TOTP code is valid' do
      it 'redirects to root' do
        allow(twofa_user).to receive(:authenticate_totp).and_return(true)
        post :twofa_verify, params: { totp_code: 'valid' }
        expect(session[:u]).to eq(twofa_user.session_token)
        expect(response).to redirect_to('/')
      end
    end
  end
end