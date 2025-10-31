require 'rails_helper'

RSpec.describe LoginController do
  let(:user) { instance_double(User) }
  let(:params) { { email: 'test@example.com', password: 'password' } }
  let(:request) { instance_double(ActionDispatch::Request, referer: 'http://example.com') }
  let(:session) { {} }

  before do
    allow(controller).to receive(:request).and_return(request)
    allow(controller).to receive(:session).and_return(session)
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
        params[:password] = 'a' * 73
      end

      it 'raises LoginPasswordTooLong' do
        expect { controller.login }.to raise_error(LoginPasswordTooLong)
      end
    end

    context 'when authentication fails' do
      before do
        allow(User).to receive(:where).and_return([user])
        allow(user).to receive(:is_wiped?).and_return(false)
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
        controller.login
        expect(session[:u]).to eq('session_token')
        expect(response).to redirect_to('/')
      end
    end
  end
end