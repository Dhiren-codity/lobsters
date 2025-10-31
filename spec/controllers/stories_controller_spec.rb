require 'rails_helper'

RSpec.describe StoriesController do
  let(:user) { create(:user) }
  let(:story) { create(:story, user: user) }
  let(:valid_attributes) { { title: 'New Story', url: 'http://example.com', description: 'Story description' } }
  let(:invalid_attributes) { { title: '', url: '', description: '' } }

  before do
    allow(controller).to receive(:require_logged_in_user).and_return(true)
    allow(controller).to receive(:require_logged_in_user_or_400).and_return(true)
    allow(controller).to receive(:verify_user_can_submit_stories).and_return(true)
    allow(controller).to receive(:find_user_story).and_return(story)
  end

  describe '#create' do
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
        expect(response).to render_template('new')
      end
    end
  end

  describe '#destroy' do
    context 'when user is authorized' do
      it 'deletes the story' do
        story
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

  describe '#edit' do
    it 'renders the edit template' do
      get :edit, params: { id: story.to_param }
      expect(response).to render_template('edit')
    end
  end

  describe '#fetch_url_attributes' do
    it 'returns fetched attributes as JSON' do
      get :fetch_url_attributes, params: { fetch_url: 'http://example.com' }
      expect(response.content_type).to eq('application/json')
    end
  end

  describe '#new' do
    it 'renders the new template' do
      get :new
      expect(response).to render_template('new')
    end
  end

  describe '#preview' do
    it 'renders the new template with preview layout' do
      post :preview, params: { story: valid_attributes }
      expect(response).to render_template('new')
    end
  end

  describe '#show' do
    it 'renders the show template' do
      get :show, params: { id: story.to_param }
      expect(response).to render_template('show')
    end
  end

  describe '#undelete' do
    it 'restores a deleted story' do
      story.update(is_deleted: true)
      post :undelete, params: { id: story.to_param }
      expect(story.reload.is_deleted).to be_falsey
    end
  end

  describe '#update' do
    context 'with valid params' do
      it 'updates the story' do
        patch :update, params: { id: story.to_param, story: valid_attributes }
        story.reload
        expect(story.title).to eq('New Story')
      end

      it 'redirects to the story' do
        patch :update, params: { id: story.to_param, story: valid_attributes }
        expect(response).to redirect_to(Routes.title_path(story))
      end
    end

    context 'with invalid params' do
      it 'renders the edit template' do
        patch :update, params: { id: story.to_param, story: invalid_attributes }
        expect(response).to render_template('edit')
      end
    end
  end

  describe '#unvote' do
    it 'removes the user vote from the story' do
      post :unvote, params: { id: story.to_param }
      expect(response.body).to eq('ok')
    end
  end

  describe '#upvote' do
    it 'adds an upvote to the story' do
      post :upvote, params: { id: story.to_param }
      expect(response.body).to eq('ok')
    end
  end

  describe '#flag' do
    it 'flags the story with a valid reason' do
      post :flag, params: { id: story.to_param, reason: 'spam' }
      expect(response.body).to eq('ok')
    end
  end

  describe '#hide' do
    it 'hides the story for the user' do
      post :hide, params: { id: story.to_param }
      expect(response.body).to eq('ok')
    end
  end

  describe '#unhide' do
    it 'unhides the story for the user' do
      post :unhide, params: { id: story.to_param }
      expect(response.body).to eq('ok')
    end
  end

  describe '#save' do
    it 'saves the story for the user' do
      post :save, params: { id: story.to_param }
      expect(response.body).to eq('ok')
    end
  end

  describe '#unsave' do
    it 'removes the saved story for the user' do
      post :unsave, params: { id: story.to_param }
      expect(response.body).to eq('ok')
    end
  end

  describe '#check_url_dupe' do
    it 'checks for duplicate URLs' do
      post :check_url_dupe, params: { story: { url: 'http://example.com' } }
      expect(response.content_type).to eq('application/json')
    end
  end

  describe '#disown' do
    it 'disowns the story' do
      post :disown, params: { id: story.to_param }
      expect(response).to redirect_to(Routes.title_path(story))
    end
  end
end