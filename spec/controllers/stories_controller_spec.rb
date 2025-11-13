# frozen_string_literal: true

require 'rails_helper'

RSpec.describe StoriesController, type: :controller do
  let(:user) { FactoryBot.create(:user) }
  let!(:story) { FactoryBot.create(:story, user: user) }

  describe 'GET #show' do
    it 'returns http success for HTML' do
      get :show, params: { id: story.to_param }
      expect(response).to have_http_status(:ok)
    end

    it 'returns JSON with story data' do
      get :show, params: { id: story.to_param }, format: :json
      expect(response).to have_http_status(:ok)
      expect(response.content_type).to include('application/json')
      expect(response.body).to include(story.title)
    end
  end

  describe 'GET #new' do
    before do
      allow(controller).to receive(:require_logged_in_user).and_return(true)
      allow(controller).to receive(:verify_user_can_submit_stories).and_return(true)
      controller.instance_variable_set(:@user, user)
    end

    it 'loads the new story form' do
      get :new
      expect(response).to have_http_status(:ok)
    end
  end

  describe 'GET #edit' do
    before do
      allow(controller).to receive(:require_logged_in_user).and_return(true)
      allow(controller).to receive(:find_user_story).and_return(true)
      controller.instance_variable_set(:@user, user)
      controller.instance_variable_set(:@story, story)
    end

    it 'returns http success' do
      get :edit, params: { id: story.to_param }
      expect(response).to have_http_status(:ok)
    end
  end

  describe 'PATCH/PUT #update' do
    before do
      allow(controller).to receive(:require_logged_in_user).and_return(true)
      allow(controller).to receive(:find_user_story).and_return(true)
      controller.instance_variable_set(:@user, user)
      controller.instance_variable_set(:@story, story)
    end

    it 'updates the story and redirects' do
      patch :update, params: { id: story.to_param, story: { title: "#{story.title} updated" } }
      expect(response).to have_http_status(:redirect)
    end
  end

  describe 'GET #preview' do
    before do
      allow(controller).to receive(:require_logged_in_user_or_400).and_return(true)
      controller.instance_variable_set(:@user, user)
    end

    it 'renders the preview via new template' do
      get :preview, params: { id: story.to_param, story: { title: 'Preview Title', url: 'http://example.com', description: '', tags: [] } }
      expect(response).to have_http_status(:ok)
    end
  end

  describe 'POST #upvote' do
    before do
      allow(controller).to receive(:require_logged_in_user_or_400).and_return(true)
      controller.instance_variable_set(:@user, user)
    end

    it 'returns ok' do
      post :upvote, params: { id: story.to_param }
      expect(response).to have_http_status(:ok)
      expect(response.body).to eq('ok')
    end
  end

  describe 'POST #unvote' do
    before do
      allow(controller).to receive(:require_logged_in_user_or_400).and_return(true)
      controller.instance_variable_set(:@user, user)
    end

    it 'returns ok' do
      post :unvote, params: { id: story.to_param }
      expect(response).to have_http_status(:ok)
      expect(response.body).to eq('ok')
    end
  end

  describe 'POST #hide' do
    before do
      allow(controller).to receive(:require_logged_in_user_or_400).and_return(true)
      controller.instance_variable_set(:@user, user)
    end

    it 'hides the story and redirects' do
      post :hide, params: { id: story.to_param }
      expect(response).to have_http_status(:redirect)
    end
  end

  describe 'POST #unhide' do
    before do
      allow(controller).to receive(:require_logged_in_user_or_400).and_return(true)
      controller.instance_variable_set(:@user, user)
    end

    it 'unhides the story and redirects' do
      post :unhide, params: { id: story.to_param }
      expect(response).to have_http_status(:redirect)
    end
  end

  describe 'POST #save' do
    before do
      allow(controller).to receive(:require_logged_in_user_or_400).and_return(true)
      controller.instance_variable_set(:@user, user)
    end

    it 'saves the story for user' do
      post :save, params: { id: story.to_param }
      expect(response).to have_http_status(:ok)
      expect(response.body).to eq('ok')
    end
  end

  describe 'POST #unsave' do
    before do
      allow(controller).to receive(:require_logged_in_user_or_400).and_return(true)
      controller.instance_variable_set(:@user, user)
    end

    it 'unsaves the story for user' do
      post :unsave, params: { id: story.to_param }
      expect(response).to have_http_status(:ok)
      expect(response.body).to eq('ok')
    end
  end

  describe 'GET #check_url_dupe' do
    it 'returns JSON with similar_stories key' do
      controller.instance_variable_set(:@user, user)
      get :check_url_dupe,
          params: { story: { url: 'http://example.com/test', title: 'Test', description: 'Desc', tags: [] } }, format: :json
      expect(response).to have_http_status(:ok)
      expect(response.content_type).to include('application/json')
      expect(response.body).to include('similar_stories')
    end
  end
end
