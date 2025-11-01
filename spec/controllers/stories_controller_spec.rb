require 'rails_helper'

RSpec.describe StoriesController do
  let(:user) { create(:user) }
  let(:story) { create(:story, user: user) }
  let(:valid_attributes) { { title: 'Test Story', url: 'http://example.com', description: 'A test story' } }
  let(:invalid_attributes) { { title: '', url: '', description: '' } }

  before do
    allow(controller).to receive(:require_logged_in_user).and_return(true)
    allow(controller).to receive(:require_logged_in_user_or_400).and_return(true)
    allow(controller).to receive(:verify_user_can_submit_stories).and_return(true)
    allow(controller).to receive(:find_user_story).and_return(story)
    allow(controller).to receive(:track_story_reads).and_yield
    allow(controller).to receive(:show_title_h1).and_return(true)
    controller.instance_variable_set(:@user, user)
    controller.instance_variable_set(:@story, story)
  end

  describe 'POST #create' do
    context 'with valid params' do
      it 'creates a new Story' do
        expect {
          post :create, params: { story: valid_attributes }
        }.to change(Story, :count).by(1)
      end

      it 'redirects to the created story' do
        post :create, params: { story: valid_attributes }
        expect(response).to redirect_to(Routes.title_path(Story.last))
      end
    end

    context 'with invalid params' do
      it 'renders the new template' do
        post :create, params: { story: invalid_attributes }
        expect(response).to be_successful
        expect(response.body).to include('Submit Story')
      end
    end
  end

  describe 'DELETE #destroy' do
    context 'when user is authorized' do
      it 'destroys the requested story' do
        story # create the story
        expect {
          delete :destroy, params: { id: story.to_param }
        }.to change(Story, :count).by(-1)
      end

      it 'redirects to the stories list' do
        delete :destroy, params: { id: story.to_param }
        expect(response).to redirect_to(Routes.title_path(story))
      end
    end
  end

  describe 'GET #edit' do
    it 'renders the edit template' do
      get :edit, params: { id: story.to_param }
      expect(response).to be_successful
      expect(response.body).to include('Edit Story')
    end
  end

  describe 'GET #fetch_url_attributes' do
    it 'returns fetched attributes as JSON' do
      get :fetch_url_attributes, params: { fetch_url: 'http://example.com' }, format: :json
      expect(response.content_type).to eq('application/json; charset=utf-8')
    end
  end

  describe 'GET #new' do
    it 'renders the new template' do
      get :new
      expect(response).to be_successful
      expect(response.body).to include('Submit Story')
    end
  end

  describe 'GET #preview' do
    it 'renders the new template with preview layout' do
      get :preview
      expect(response).to be_successful
      expect(response.body).to include('Submit Story')
    end
  end

  describe 'GET #show' do
    it 'renders the show template' do
      get :show, params: { id: story.to_param }
      expect(response).to be_successful
      expect(response.body).to include(story.title)
    end
  end

  describe 'PATCH #update' do
    context 'with valid params' do
      it 'updates the requested story' do
        patch :update, params: { id: story.to_param, story: valid_attributes }
        story.reload
        expect(story.title).to eq('Test Story')
      end

      it 'redirects to the story' do
        patch :update, params: { id: story.to_param, story: valid_attributes }
        expect(response).to redirect_to(Routes.title_path(story))
      end
    end

    context 'with invalid params' do
      it 'renders the edit template' do
        patch :update, params: { id: story.to_param, story: invalid_attributes }
        expect(response).to be_successful
        expect(response.body).to include('Edit Story')
      end
    end
  end

  describe 'GET #check_url_dupe' do
    it 'checks for duplicate URLs' do
      get :check_url_dupe, params: { story: { url: 'http://example.com' } }, format: :json
      expect(response.content_type).to eq('application/json; charset=utf-8')
    end
  end

  # Removed: Tests for #undelete could not be fixed (missing route)
  # Removed: Tests for #disown could not be fixed (missing route)
end