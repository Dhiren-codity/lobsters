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

  describe 'PATCH #update' do
    context 'with valid params' do
      let(:new_attributes) { { title: 'Updated Title' } }

      it 'updates the requested story' do
        patch :update, params: { id: story.to_param, story: new_attributes }
        story.reload
        expect(story.title).to eq('Updated Title')
      end

      it 'redirects to the story' do
        patch :update, params: { id: story.to_param, story: new_attributes }
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

  describe 'POST #upvote' do
    it 'upvotes the story' do
      expect(Vote).to receive(:vote_thusly_on_story_or_comment_for_user_because).with(1, story.id, nil, user.id, nil)
      post :upvote, params: { id: story.to_param }
      expect(response.body).to eq('ok')
    end
  end

  describe 'POST #unvote' do
    it 'removes the vote from the story' do
      expect(Vote).to receive(:vote_thusly_on_story_or_comment_for_user_because).with(0, story.id, nil, user.id, nil)
      post :unvote, params: { id: story.to_param }
      expect(response.body).to eq('ok')
    end
  end

  describe 'POST #flag' do
    it 'flags the story with a valid reason' do
      allow(Vote::STORY_REASONS).to receive(:[]).with('spam').and_return(true)
      expect(Vote).to receive(:vote_thusly_on_story_or_comment_for_user_because).with(-1, story.id, nil, user.id, 'spam')
      post :flag, params: { id: story.to_param, reason: 'spam' }
      expect(response.body).to eq('ok')
    end

    it 'returns error for invalid reason' do
      post :flag, params: { id: story.to_param, reason: 'invalid' }
      expect(response.body).to eq('invalid reason')
    end
  end

  describe 'POST #hide' do
    it 'hides the story for the user' do
      expect(HiddenStory).to receive(:hide_story_for_user).with(story, user)
      post :hide, params: { id: story.to_param }
      expect(response.body).to eq('ok')
    end
  end

  describe 'POST #unhide' do
    it 'unhides the story for the user' do
      expect(HiddenStory).to receive(:unhide_story_for_user).with(story, user)
      post :unhide, params: { id: story.to_param }
      expect(response.body).to eq('ok')
    end
  end

  describe 'POST #save' do
    it 'saves the story for the user' do
      expect(SavedStory).to receive(:save_story_for_user).with(story.id, user.id)
      post :save, params: { id: story.to_param }
      expect(response.body).to eq('ok')
    end
  end

  describe 'POST #unsave' do
    it 'unsaves the story for the user' do
      expect(SavedStory).to receive(:where).with(user_id: user.id, story_id: story.id).and_return(double(delete_all: true))
      post :unsave, params: { id: story.to_param }
      expect(response.body).to eq('ok')
    end
  end
end