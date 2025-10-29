require 'rails_helper'

RSpec.describe SettingsController do
  let(:user) { create(:user) }
  let(:session) { {} }

  before do
    allow(controller).to receive(:require_logged_in_user).and_return(true)
    allow(controller).to receive(:show_title_h1).and_return(true)
    allow(controller).to receive(:session).and_return(session)
    allow(controller).to receive(:current_user).and_return(user)
  end

  describe '#deactivate' do
    context 'when "I am sure" checkbox is not checked' do
      it 'redirects to settings path with an error message' do
        post :deactivate, params: { user: { i_am_sure: "0", password: "password" } }
        expect(flash[:error]).to eq('You did not check the "I am sure" checkbox.')
        expect(response).to redirect_to(settings_path)
      end
    end

    context 'when password is incorrect' do
      it 'redirects to settings path with an error message' do
        allow(user).to receive(:authenticate).and_return(false)
        post :deactivate, params: { user: { i_am_sure: "1", password: "wrong_password" } }
        expect(flash[:error]).to eq("Given password doesn't match account.")
        expect(response).to redirect_to(settings_path)
      end
    end

    context 'when "I am sure" checkbox is checked and password is correct' do
      it 'deletes the user and redirects to root path with a success message' do
        allow(user).to receive(:authenticate).and_return(true)
        expect(user).to receive(:delete!)
        post :deactivate, params: { user: { i_am_sure: "1", password: "password" } }
        expect(flash[:success]).to include("You have deleted your account")
        expect(response).to redirect_to("/")
      end
    end
  end

  describe '#update' do
    context 'when current password is incorrect' do
      it 'renders index with an error message' do
        allow(user).to receive(:authenticate).and_return(false)
        patch :update, params: { user: { password: "new_password" }, current_password: "wrong_password" }
        expect(flash[:error]).to eq("Your current password was not entered correctly.")
        expect(response).to render_template(:index)
      end
    end

    context 'when current password is correct' do
      it 'updates the user and renders index with a success message' do
        allow(user).to receive(:authenticate).and_return(true)
        allow(user).to receive(:update).and_return(true)
        patch :update, params: { user: { password: "new_password" }, current_password: "password" }
        expect(flash.now[:success]).to eq("Successfully updated settings.")
        expect(response).to render_template(:index)
      end
    end
  end

  describe '#twofa_auth' do
    context 'when password is correct' do
      it 'disables 2FA and redirects to settings with a success message' do
        allow(user).to receive(:authenticate).and_return(true)
        allow(user).to receive(:has_2fa?).and_return(true)
        expect(user).to receive(:disable_2fa!)
        post :twofa_auth, params: { user: { password: "password" } }
        expect(flash[:success]).to eq("Two-Factor Authentication has been disabled.")
        expect(response).to redirect_to("/settings")
      end
    end

    context 'when password is incorrect' do
      it 'redirects to twofa_url with an error message' do
        allow(user).to receive(:authenticate).and_return(false)
        post :twofa_auth, params: { user: { password: "wrong_password" } }
        expect(flash[:error]).to eq("Your password was not correct.")
        expect(response).to redirect_to(twofa_url)
      end
    end
  end

  describe '#pushover_auth' do
    context 'when Pushover is not enabled' do
      it 'redirects to settings with an error message' do
        allow(Pushover).to receive(:enabled?).and_return(false)
        get :pushover_auth
        expect(flash[:error]).to eq("This site is not configured for Pushover")
        expect(response).to redirect_to("/settings")
      end
    end

    context 'when Pushover is enabled' do
      it 'redirects to Pushover subscription URL' do
        allow(Pushover).to receive(:enabled?).and_return(true)
        allow(SecureRandom).to receive(:hex).and_return("random_token")
        expect(Pushover).to receive(:subscription_url).and_return("http://pushover.com")
        get :pushover_auth
        expect(response).to redirect_to("http://pushover.com")
      end
    end
  end

  describe '#mastodon_auth' do
    context 'when Mastodon app is persisted' do
      it 'redirects to Mastodon OAuth URL' do
        app = double("MastodonApp", persisted?: true, oauth_auth_url: "http://mastodon.com")
        allow(MastodonApp).to receive(:find_or_register).and_return(app)
        get :mastodon_auth, params: { mastodon_instance_name: "instance" }
        expect(response).to redirect_to("http://mastodon.com")
      end
    end

    context 'when Mastodon app is not persisted' do
      it 'redirects to settings with an error message' do
        app = double("MastodonApp", persisted?: false, errors: double(full_messages: ["Error"]))
        allow(MastodonApp).to receive(:find_or_register).and_return(app)
        get :mastodon_auth, params: { mastodon_instance_name: "instance" }
        expect(flash[:error]).to eq("Error")
        expect(response).to redirect_to(settings_path)
      end
    end
  end

  describe '#github_auth' do
    it 'redirects to GitHub OAuth URL' do
      allow(SecureRandom).to receive(:hex).and_return("random_token")
      expect(Github).to receive(:oauth_auth_url).with("random_token").and_return("http://github.com")
      get :github_auth
      expect(response).to redirect_to("http://github.com")
    end
  end
end