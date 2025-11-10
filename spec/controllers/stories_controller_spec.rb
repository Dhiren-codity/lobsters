# frozen_string_literal: true

require 'rails_helper'

RSpec.describe StoriesController, type: :controller do
  let!(:tag) { FactoryBot.create(:tag, active: true) }
  let(:user) { FactoryBot.create(:user) }
  let(:other_user) { FactoryBot.create(:user) }
  let(:story) { FactoryBot.create(:story, user: other_user, tags: [tag]) }

  describe 'GET #show' do
    it 'returns http success for an existing story' do
      get :show, params: { id: story.short_id }
      expect(response).to have_http_status(:ok)
      expect(response.body).to include(story.title)
    end

    it 'returns json for an existing story' do
      get :show, params: { id: story.short_id, format: :json }
      expect(response).to have_http_status(:ok)
      expect(response.media_type).to include('application/json')
      json = JSON.parse(response.body)
      expect(json).to be_a(Hash)
      expect(json['short_id']).to eq(story.short_id)
    end
  end

  describe 'POST #create' do
    let(:valid_params) do
      {
        story: {
          title: 'A test story title',
          url: 'https://example.com/article',
          description: 'A description',
          user_is_author: '0',
          user_is_following: '0',
          tags: [tag.tag]
        }
      }
    end

    before do
      allow(controller).to receive(:require_logged_in_user).and_return(true)
      allow(controller).to receive(:verify_user_can_submit_stories).and_return(true)
      controller.instance_variable_set(:@user, user)
    end

    it 'creates a new story and redirects' do
      expect do
        post :create, params: valid_params
      end.to change(Story, :count).by(1)
      expect(response).to have_http_status(:redirect)
    end
  end

  describe 'POST #upvote' do
    before do
      allow(controller).to receive(:require_logged_in_user_or_400).and_return(true)
      controller.instance_variable_set(:@user, user)
    end

    it 'upvotes the story and returns ok' do
      post :upvote, params: { id: story.short_id }
      expect(response).to have_http_status(:ok)
      expect(response.body).to eq('ok')
    end
  end

  describe 'POST #unvote' do
    before do
      allow(controller).to receive(:require_logged_in_user_or_400).and_return(true)
      controller.instance_variable_set(:@user, user)
    end

    it 'removes vote from the story and returns ok' do
      post :unvote, params: { id: story.short_id }
      expect(response).to have_http_status(:ok)
      expect(response.body).to eq('ok')
    end
  end

  describe 'POST #flag' do
    before do
      allow(controller).to receive(:require_logged_in_user_or_400).and_return(true)
      controller.instance_variable_set(:@user, user)
    end

    it 'returns 400 for invalid reason' do
      post :flag, params: { id: story.short_id, reason: 'invalid_reason' }
      expect(response).to have_http_status(400)
      expect(response.body).to eq('invalid reason')
    end

    it 'flags with a valid reason and returns ok' do
      valid_reason = Vote::STORY_REASONS.keys.first
      post :flag, params: { id: story.short_id, reason: valid_reason }
      expect(response).to have_http_status(:ok)
      expect(response.body).to eq('ok')
    end
  end

  describe 'POST #hide' do
    before do
      allow(controller).to receive(:require_logged_in_user_or_400).and_return(true)
      controller.instance_variable_set(:@user, user)
    end

    it 'hides the story for the user and redirects for non-XHR requests' do
      post :hide, params: { id: story.short_id }
      expect(response).to have_http_status(:redirect)
    end
  end

  describe 'POST #unhide' do
    before do
      allow(controller).to receive(:require_logged_in_user_or_400).and_return(true)
      controller.instance_variable_set(:@user, user)
    end

    it 'unhides the story for the user and redirects for non-XHR requests' do
      # First hide it
      post :hide, params: { id: story.short_id }
      # Then unhide
      post :unhide, params: { id: story.short_id }
      expect(response).to have_http_status(:redirect)
    end
  end

  describe 'POST #save and #unsave' do
    before do
      allow(controller).to receive(:require_logged_in_user_or_400).and_return(true)
      controller.instance_variable_set(:@user, user)
    end

    it 'saves a story for the user' do
      post :save, params: { id: story.short_id }
      expect(response).to have_http_status(:ok)
      expect(response.body).to eq('ok')
      expect(SavedStory.where(user_id: user.id, story_id: story.id)).to exist
    end

    it 'unsaves a story for the user' do
      post :save, params: { id: story.short_id }
      post :unsave, params: { id: story.short_id }
      expect(response).to have_http_status(:ok)
      expect(response.body).to eq('ok')
      expect(SavedStory.where(user_id: user.id, story_id: story.id)).not_to exist
    end
  end

  describe 'GET #new' do
    before do
      allow(controller).to receive(:require_logged_in_user).and_return(true)
      allow(controller).to receive(:verify_user_can_submit_stories).and_return(true)
      controller.instance_variable_set(:@user, user)
    end

    it 'renders successfully' do
      get :new
      expect(response).to have_http_status(:ok)
    end
  end

  describe 'GET #preview' do
    before do
      allow(controller).to receive(:require_logged_in_user_or_400).and_return(true)
      controller.instance_variable_set(:@user, user)
    end

    let(:preview_params) do
      {
        story: {
          title: 'Preview Story',
          url: 'https://example.com/preview',
          description: 'Preview description',
          user_is_author: '0',
          user_is_following: '0',
          tags: [tag.tag]
        }
      }
    end

    it 'renders the preview successfully' do
      get :preview, params: preview_params
      expect(response).to have_http_status(:ok)
      expect(assigns(:story)).to be_present
      expect(assigns(:story).previewing).to be true
    end
  end

  describe 'DELETE #destroy' do
    let!(:owned_story) { FactoryBot.create(:story, user: other_user, tags: [tag]) }

    before do
      allow(controller).to receive(:require_logged_in_user).and_return(true)
      user.update!(is_moderator: true)
      controller.instance_variable_set(:@user, user)
      allow(Mastodon).to receive(:delete_post).and_return(true)
      # Let the real before_action run to find story by id/short_id for moderator
    end

    it 'marks the story as deleted and redirects' do
      delete :destroy, params: { id: owned_story.short_id }
      expect(response).to have_http_status(:redirect)
      expect(owned_story.reload.is_deleted).to be true
    end
  end

  describe 'GET #check_url_dupe (json)' do
    it 'returns JSON response including similar_stories key' do
      get :check_url_dupe, params: { story: { url: 'https://example.com/something' } }, format: :json
      expect(response).to have_http_status(:ok)
      expect(response.media_type).to include('application/json')
      json = JSON.parse(response.body)
      expect(json).to be_a(Hash)
      expect(json).to have_key('similar_stories')
    end
  end
end
