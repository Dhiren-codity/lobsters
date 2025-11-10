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

    it 'renders successfully' do
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

    it 'renders successfully' do
      get :edit, params: { id: story.short_id }
      expect(response).to have_http_status(:ok)
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

    it 'marks the story as deleted and redirects' do
      delete :destroy, params: {
        id: story.short_id,
        story: {
          title: story.title,
          url: story.url || "https://example.com/#{SecureRandom.hex(6)}",
          description: story.description || 'desc',
          user_is_author: false,
          user_is_following: false,
          tags: [tag.tag]
        }
      }
      expect(response).to have_http_status(:redirect)
      expect(story.reload.is_deleted).to be true
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

  # Removed: Routes for unvote, upvote, flag, hide, unhide, save, and unsave do not exist in this app

  describe 'GET #check_url_dupe' do
    before do
      controller.instance_variable_set(:@user, user)
    end

    it 'returns JSON with dupe check info' do
      get :check_url_dupe, params: { story: valid_story_params }, format: :json
      expect(response).to have_http_status(:ok)
      expect(response.content_type).to include('application/json')
    end
  end

  # Removed: Route for POST #disown does not exist in this app
end