require 'rails_helper'

RSpec.describe LoginController do
  let(:user) { instance_double(User) }
  let(:params) { { email: 'test@example.com', password: 'password' } }
  let(:session) { {} }
  let(:request) { instance_double(ActionDispatch::Request, referer: 'http://example.com', remote_ip: '127.0.0.1') }

  before do
    allow(controller).to receive(:params).and_return(params)
    allow(controller).to receive(:session).and_return(session)
    allow(controller).to receive(:request).and_return(request)
  end

  describe '#login' do
    context 'when user is not found' do
      before do
        allow(User).to receive(:where).and_return([])
      end

      it 'raises LoginFailedError' do
        expect { controller.login }.to raise_error(LoginFailedError)
      end
    end

    context 'when user is wiped' do
      before do
        allow(User).to receive(:where).and_return([user])
        allow(user).to receive(:is_wiped?).and_return(true)
      end

      it 'raises LoginWipedError' do
        expect { controller.login }.to raise_error(LoginWipedError)
      end
    end

    context 'when password is too long' do
      before do
        allow(User).to receive(:where).and_return([user])
        allow(user).to receive(:is_wiped?).and_return(false)
        allow(params[:password]).to receive(:to_s).and_return('a' * 73)
      end

      it 'raises LoginPasswordTooLong' do
        expect { controller.login }.to raise_error(LoginPasswordTooLong)
      end
    end

    context 'when authentication fails' do
      before do
        allow(User).to receive(:where).and_return([user])
        allow(user).to receive(:is_wiped?).and_return(false)
        allow(params[:password]).to receive(:to_s).and_return('password')
        allow(user).to receive(:authenticate).and_return(false)
      end

      it 'raises LoginFailedError' do
        expect { controller.login }.to raise_error(LoginFailedError)
      end
    end

    context 'when user is banned' do
      before do
        allow(User).to receive(:where).and_return([user])
        allow(user).to receive(:is_wiped?).and_return(false)
        allow(user).to receive(:authenticate).and_return(true)
        allow(user).to receive(:is_banned?).and_return(true)
      end

      it 'raises LoginBannedError' do
        expect { controller.login }.to raise_error(LoginBannedError)
      end
    end

    context 'when user is deleted' do
      before do
        allow(User).to receive(:where).and_return([user])
        allow(user).to receive(:is_wiped?).and_return(false)
        allow(user).to receive(:authenticate).and_return(true)
        allow(user).to receive(:is_banned?).and_return(false)
        allow(user).to receive(:is_active?).and_return(false)
      end

      it 'raises LoginDeletedError' do
        expect { controller.login }.to raise_error(LoginDeletedError)
      end
    end

    context 'when login is successful' do
      before do
        allow(User).to receive(:where).and_return([user])
        allow(user).to receive(:is_wiped?).and_return(false)
        allow(user).to receive(:authenticate).and_return(true)
        allow(user).to receive(:is_banned?).and_return(false)
        allow(user).to receive(:is_active?).and_return(true)
        allow(user).to receive(:password_digest).and_return('$2a$12$example')
        allow(user).to receive(:has_2fa?).and_return(false)
        allow(user).to receive(:session_token).and_return('session_token')
      end

      it 'sets session token and redirects to root' do
        expect(controller).to receive(:redirect_to).with('/')
        controller.login
        expect(session[:u]).to eq('session_token')
      end
    end
  end

  describe '#logout' do
    context 'when user is logged in' do
      before do
        allow(controller).to receive(:reset_session)
        allow(controller).to receive(:@user).and_return(user)
      end

      it 'resets session and redirects to root' do
        expect(controller).to receive(:reset_session)
        expect(controller).to receive(:redirect_to).with('/')
        controller.logout
      end
    end
  end

  describe '#forgot_password' do
    it 'renders forgot_password template' do
      expect(controller).to receive(:render).with(:forgot_password)
      controller.forgot_password
    end
  end

  describe '#reset_password' do
    context 'when user is not found' do
      before do
        allow(User).to receive(:where).and_return([])
      end

      it 'renders forgot_password with error' do
        expect(controller).to receive(:render).with(:forgot_password)
        controller.reset_password
        expect(flash.now[:error]).to eq('Unknown e-mail address or username.')
      end
    end

    context 'when user is banned' do
      before do
        allow(User).to receive(:where).and_return([user])
        allow(user).to receive(:is_banned?).and_return(true)
      end

      it 'renders forgot_password with error' do
        expect(controller).to receive(:render).with(:forgot_password)
        controller.reset_password
        expect(flash.now[:error]).to eq('Your account has been banned.')
      end
    end

    context 'when user is wiped' do
      before do
        allow(User).to receive(:where).and_return([user])
        allow(user).to receive(:is_banned?).and_return(false)
        allow(user).to receive(:is_wiped?).and_return(true)
      end

      it 'renders forgot_password with error' do
        expect(controller).to receive(:render).with(:forgot_password)
        controller.reset_password
        expect(flash.now[:error]).to eq("It's not possible to reset your password because your account was deleted before the site changed admins and your email address was wiped for privacy.")
      end
    end

    context 'when password reset is initiated' do
      before do
        allow(User).to receive(:where).and_return([user])
        allow(user).to receive(:is_banned?).and_return(false)
        allow(user).to receive(:is_wiped?).and_return(false)
        allow(user).to receive(:initiate_password_reset_for_ip)
      end

      it 'renders index with success message' do
        expect(controller).to receive(:render).with('index')
        controller.reset_password
        expect(flash.now[:success]).to eq('Password reset instructions have been e-mailed to you.')
      end
    end
  end
end