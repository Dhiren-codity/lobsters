# frozen_string_literal: true

require 'rails_helper'

RSpec.describe StoriesController, type: :controller do
  let(:user) { FactoryBot.create(:user) }
  let(:tag)  { FactoryBot.create(:tag) }
  let(:valid_story_params) do
    {
      title: 'A Title',
      url: "https://example.com/#{SecureRandom.hex(6)}",
      description: 'A test description',
      user_is_author: false,
      user_is_following: false,
      tags: [tag.tag]
    }
  end

  describe 'GET #show' do
    let!(:story) { FactoryBot.create(:story, user: user, tags: [tag]) }

    it 'returns http success (HTML)' do
      get :show, params: { id: story.short_id }
      expect(response).to have_http_status(:ok)
    end

    it 'returns http success (JSON)' do
      get :show, params: { id: story.short_id }, format: :json
      expect(response).to have_http_status(:ok)
      expect(response.content_type).to include('application/json')
    end
  end

  describe 'GET #new' do
    before do
      allow(controller).to receive(:require_logged_in_user).and_return(true)
      allow(controller).to receive(:verify_user_can_submit_stories).and_return(true)
      controller.instance_variable_set(:@user, user)
    end

    it 'returns http success' do
      get :new
      expect(response).to have_http_status(:ok)
    end
  end

  describe 'POST #create' do
    before do
      allow(controller).to receive(:require_logged_in_user).and_return(true)
      allow(controller).to receive(:verify_user_can_submit_stories).and_return(true)
      controller.instance_variable_set(:@user, user)
    end

    it 'creates a story and redirects' do
      expect do
        post :create, params: { story: valid_story_params }
      end.to change(Story, :count).by(1)
      expect(response).to have_http_status(:redirect)
    end

    it 'renders preview when preview is set' do
      post :create, params: { story: valid_story_params, preview: '1' }
      expect(response).to have_http_status(:ok)
    end
  end

  describe 'GET #edit' do
    let!(:story) { FactoryBot.create(:story, user: user, tags: [tag]) }

    before do
      allow(controller).to receive(:require_logged_in_user).and_return(true)
      allow(controller).to receive(:find_user_story).and_return(true)
      controller.instance_variable_set(:@user, user)
      controller.instance_variable_set(:@story, story)
      allow(story).to receive(:is_editable_by_user?).with(user).and_return(true)
    end

    it 'returns http success' do
      get :edit, params: { id: story.short_id }
      expect(response).to have_http_status(:ok)
    end
  end

  describe 'PATCH #update' do
    let!(:story) { FactoryBot.create(:story, user: user, tags: [tag]) }

    before do
      allow(controller).to receive(:require_logged_in_user).and_return(true)
      allow(controller).to receive(:find_user_story).and_return(true)
      controller.instance_variable_set(:@user, user)
      controller.instance_variable_set(:@story, story)
      allow(story).to receive(:is_editable_by_user?).with(user).and_return(true)
    end

    it 'updates the story and redirects' do
      patch :update, params: { id: story.short_id, story: valid_story_params.merge(title: 'Updated Title') }
      expect(response).to have_http_status(:redirect)
      expect(story.reload.title).to eq('Updated Title')
    end
  end

  describe 'DELETE #destroy' do
    let!(:story) { FactoryBot.create(:story, user: user, tags: [tag]) }

    before do
      user.update!(is_moderator: true)
      allow(Mastodon).to receive(:delete_post).and_return(true)
      allow(controller).to receive(:require_logged_in_user).and_return(true)
      allow(controller).to receive(:find_user_story).and_return(true)
      controller.instance_variable_set(:@user, user)
      controller.instance_variable_set(:@story, story)
    end

    it 'soft deletes and redirects' do
      delete :destroy, params: { id: story.short_id, story: valid_story_params }
      expect(response).to have_http_status(:redirect)
      expect(story.reload.is_deleted).to eq(true)
    end
  end

  describe 'POST #undelete' do
    let!(:story) { FactoryBot.create(:story, user: user, tags: [tag], is_deleted: true) }

    before do
      allow(controller).to receive(:find_user_story).and_return(true)
      allow(controller).to receive(:require_logged_in_user).and_return(true)
      controller.instance_variable_set(:@user, user)
      controller.instance_variable_set(:@story, story)
    end

    it 'redirects with error when not permitted' do
      post :undelete, params: { id: story.short_id, story: valid_story_params }
      expect(response).to have_http_status(:redirect)
      expect(flash[:error]).to be_present
    end
  end

  describe 'GET #fetch_url_attributes' do
    before do
      allow(controller).to receive(:require_logged_in_user).and_return(true)
      controller.instance_variable_set(:@user, user)
      allow_any_instance_of(Story).to receive(:fetched_attributes).and_return({ url: 'https://example.com',
                                                                                title: 'Example', description: 'Desc' })
    end

    it 'returns JSON with fetched attributes' do
      get :fetch_url_attributes, params: { fetch_url: 'https://example.com' }
      expect(response).to have_http_status(:ok)
      expect(response.content_type).to include('application/json')
    end
  end

  describe 'POST #preview' do
    before do
      allow(controller).to receive(:require_logged_in_user_or_400).and_return(true)
      controller.instance_variable_set(:@user, user)
    end

    it 'renders successfully' do
      post :preview, params: { story: valid_story_params }
      expect(response).to have_http_status(:ok)
    end
  end

  describe 'POST #unvote' do
    let!(:story) { FactoryBot.create(:story, user: user, tags: [tag]) }

    before do
      allow(controller).to receive(:require_logged_in_user_or_400).and_return(true)
      controller.instance_variable_set(:@user, user)
    end

    it 'returns ok' do
      post :unvote, params: { id: story.short_id }
      expect(response).to have_http_status(:ok)
      expect(response.body).to eq('ok')
    end
  end

  describe 'POST #upvote' do
    let!(:story) { FactoryBot.create(:story, user: user, tags: [tag]) }

    before do
      allow(controller).to receive(:require_logged_in_user_or_400).and_return(true)
      controller.instance_variable_set(:@user, user)
    end

    it 'returns ok' do
      post :upvote, params: { id: story.short_id }
      expect(response).to have_http_status(:ok)
      expect(response.body).to eq('ok')
    end
  end

  describe 'POST #flag' do
    let!(:story) { FactoryBot.create(:story, user: user, tags: [tag]) }

    before do
      allow(controller).to receive(:require_logged_in_user_or_400).and_return(true)
      controller.instance_variable_set(:@user, user)
      allow(user).to receive(:can_flag?).and_return(true)
    end

    it 'flags a story with a valid reason' do
      reason = Vote::STORY_REASONS.keys.first
      post :flag, params: { id: story.short_id, reason: reason }
      expect(response).to have_http_status(:ok)
      expect(response.body).to eq('ok')
    end
  end

  describe 'POST #hide' do
    let!(:story) { FactoryBot.create(:story, user: user, tags: [tag]) }

    before do
      allow(controller).to receive(:require_logged_in_user_or_400).and_return(true)
      controller.instance_variable_set(:@user, user)
    end

    it 'hides the story for xhr requests' do
      post :hide, params: { id: story.short_id }, xhr: true
      expect(response).to have_http_status(:ok)
      expect(response.body).to eq('ok')
    end
  end

  describe 'POST #unhide' do
    let!(:story) { FactoryBot.create(:story, user: user, tags: [tag]) }

    before do
      allow(controller).to receive(:require_logged_in_user_or_400).and_return(true)
      controller.instance_variable_set(:@user, user)
    end

    it 'unhides the story for xhr requests' do
      post :unhide, params: { id: story.short_id }, xhr: true
      expect(response).to have_http_status(:ok)
      expect(response.body).to eq('ok')
    end
  end

  describe 'POST #save' do
    let!(:story) { FactoryBot.create(:story, user: user, tags: [tag]) }

    before do
      allow(controller).to receive(:require_logged_in_user_or_400).and_return(true)
      controller.instance_variable_set(:@user, user)
    end

    it 'saves the story' do
      post :save, params: { id: story.short_id }
      expect(response).to have_http_status(:ok)
      expect(response.body).to eq('ok')
    end
  end

  describe 'POST #unsave' do
    let!(:story) { FactoryBot.create(:story, user: user, tags: [tag]) }

    before do
      allow(controller).to receive(:require_logged_in_user_or_400).and_return(true)
      controller.instance_variable_set(:@user, user)
    end

    it 'unsaves the story' do
      post :unsave, params: { id: story.short_id }
      expect(response).to have_http_status(:ok)
      expect(response.body).to eq('ok')
    end
  end

  describe 'GET #check_url_dupe' do
    it 'returns JSON data' do
      get :check_url_dupe, params: { story: { url: "https://example.com/#{SecureRandom.hex(4)}" } }, format: :json
      expect(response).to have_http_status(:ok)
      expect(response.content_type).to include('application/json')
    end
  end

  describe 'POST #disown' do
    let!(:story) { FactoryBot.create(:story, user: user, tags: [tag]) }

    before do
      allow(controller).to receive(:require_logged_in_user_or_400).and_return(true)
      controller.instance_variable_set(:@user, user)
      allow_any_instance_of(Story).to receive(:disownable_by_user?).and_return(true)
      allow(InactiveUser).to receive(:disown!).and_return(true)
    end

    it 'disowns the story and redirects' do
      post :disown, params: { id: story.short_id }
      expect(response).to have_http_status(:redirect)
    end
  end
end
