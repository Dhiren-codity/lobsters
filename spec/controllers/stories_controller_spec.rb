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
    controller.instance_variable_set(:@user, user)
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
        expect(response).to render_template('new')
      end
    end
  end

  describe 'DELETE #destroy' do
    context 'when user is authorized' do
      it 'destroys the requested story' do
        story_to_destroy = create(:story, user: user)
        expect {
          delete :destroy, params: { id: story_to_destroy.to_param }
        }.to change(Story, :count).by(-1)
      end

      it 'redirects to the stories list' do
        delete :destroy, params: { id: story.to_param }
        expect(response).to redirect_to(Routes.title_path(story))
      end
    end
  end

  describe 'PUT #update' do
    context 'with valid params' do
      let(:new_attributes) { { title: 'Updated Story' } }

      it 'updates the requested story' do
        put :update, params: { id: story.to_param, story: new_attributes }
        story.reload
        expect(story.title).to eq('Updated Story')
      end

      it 'redirects to the story' do
        put :update, params: { id: story.to_param, story: new_attributes }
        expect(response).to redirect_to(Routes.title_path(story))
      end
    end

    context 'with invalid params' do
      it 'renders the edit template' do
        put :update, params: { id: story.to_param, story: invalid_attributes }
        expect(response).to render_template('edit')
      end
    end
  end

  describe 'GET #show' do
    it 'returns a success response' do
      get :show, params: { id: story.to_param }
      expect(response).to be_successful
    end
  end

  # Removed: Route 'upvote' does not exist
  # Removed: Route 'unvote' does not exist
  # Removed: Route 'hide' does not exist
  # Removed: Route 'unhide' does not exist
  # Removed: Route 'save' does not exist
  # Removed: Route 'unsave' does not exist

  describe 'POST #flag' do
    it 'flags the story with a valid reason' do
      reason = Vote::STORY_REASONS.keys.first
      allow(user).to receive(:can_flag?).with(story).and_return(true)
      expect(Vote).to receive(:vote_thusly_on_story_or_comment_for_user_because).with(-1, story.id, nil, user.id, reason)
      post :flag, params: { id: story.to_param, reason: reason }
      expect(response.body).to eq('ok')
    end
  end
end