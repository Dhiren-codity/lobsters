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
      it 'does not create a new Story' do
        expect {
          post :create, params: { story: invalid_attributes }
        }.to change(Story, :count).by(0)
      end

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

    context 'when user is not authorized' do
      before do
        allow(story).to receive(:is_editable_by_user?).and_return(false)
        allow(user).to receive(:is_moderator?).and_return(false)
      end

      it 'does not destroy the story' do
        expect {
          delete :destroy, params: { id: story.to_param }
        }.to change(Story, :count).by(0)
      end

      it 'redirects to the root path with an error message' do
        delete :destroy, params: { id: story.to_param }
        expect(response).to redirect_to('/')
        expect(flash[:error]).to eq('You cannot edit that story.')
      end
    end
  end

  describe 'PATCH #update' do
    context 'with valid params' do
      let(:new_attributes) { { title: 'Updated Story' } }

      it 'updates the requested story' do
        patch :update, params: { id: story.to_param, story: new_attributes }
        story.reload
        expect(story.title).to eq('Updated Story')
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

  describe 'GET #show' do
    context 'when story is found' do
      it 'returns a success response' do
        get :show, params: { id: story.to_param }
        expect(response).to be_successful
      end
    end

    context 'when story is not found' do
      it 'raises an ActiveRecord::RecordNotFound error' do
        expect {
          get :show, params: { id: 'nonexistent' }
        }.to raise_error(ActiveRecord::RecordNotFound)
      end
    end
  end

  describe 'POST #upvote' do
    context 'when story is found' do
      it 'upvotes the story' do
        expect(Vote).to receive(:vote_thusly_on_story_or_comment_for_user_because).with(1, story.id, nil, user.id, nil)
        post :upvote, params: { id: story.to_param }
        expect(response.body).to eq('ok')
      end
    end

    context 'when story is not found' do
      it 'returns an error response' do
        post :upvote, params: { id: 'nonexistent' }
        expect(response.body).to eq("can't find story")
        expect(response.status).to eq(400)
      end
    end
  end

  describe 'POST #flag' do
    context 'when story is found and reason is valid' do
      it 'flags the story' do
        allow(Vote::STORY_REASONS).to receive(:[]).with('spam').and_return(true)
        allow(user).to receive(:can_flag?).and_return(true)
        expect(Vote).to receive(:vote_thusly_on_story_or_comment_for_user_because).with(-1, story.id, nil, user.id, 'spam')
        post :flag, params: { id: story.to_param, reason: 'spam' }
        expect(response.body).to eq('ok')
      end
    end

    context 'when reason is invalid' do
      it 'returns an error response' do
        post :flag, params: { id: story.to_param, reason: 'invalid_reason' }
        expect(response.body).to eq('invalid reason')
        expect(response.status).to eq(400)
      end
    end
  end
end