require 'rails_helper'

RSpec.describe StoriesController do
  let(:user) { create(:user) }
  let(:story) { create(:story, user: user) }
  let(:valid_attributes) { { title: 'New Story', url: 'http://example.com', description: 'A new story' } }
  let(:invalid_attributes) { { title: '', url: '', description: '' } }

  before do
    controller.instance_variable_set(:@user, user)
    allow(controller).to receive(:require_logged_in_user).and_return(true)
    allow(controller).to receive(:require_logged_in_user_or_400).and_return(true)
    allow(controller).to receive(:verify_user_can_submit_stories).and_return(true)
    allow(controller).to receive(:find_user_story).and_return(story)
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
        expect(response.body).to include("Submit Story")
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

    context 'when user is not authorized' do
      before do
        allow(story).to receive(:is_editable_by_user?).and_return(false)
        allow(user).to receive(:is_moderator?).and_return(false)
      end

      it 'does not destroy the story' do
        story # create the story
        expect {
          delete :destroy, params: { id: story.to_param }
        }.not_to change(Story, :count)
      end

      it 'redirects to the root path with an error' do
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
        expect(response).to be_successful
        expect(response.body).to include("Edit Story")
      end
    end
  end

  describe 'GET #show' do
    context 'when story is visible' do
      it 'renders the show template' do
        get :show, params: { id: story.to_param }
        expect(response).to be_successful
        expect(response.body).to include(story.title)
      end
    end

    context 'when story is not visible' do
      before do
        allow(story).to receive(:can_be_seen_by_user?).and_return(false)
      end

      it 'renders the missing template' do
        get :show, params: { id: story.to_param }
        expect(response).to have_http_status(404)
        expect(response.body).to include("missing")
      end
    end
  end

  describe 'POST #upvote' do
    context 'when story is found' do
      it 'votes on the story' do
        expect(Vote).to receive(:vote_thusly_on_story_or_comment_for_user_because).with(1, story.id, nil, user.id, nil)
        post :upvote, params: { id: story.to_param }
        expect(response.body).to eq('ok')
      end
    end

    context 'when story is not found' do
      before do
        allow(controller).to receive(:find_story).and_return(nil)
      end

      it 'returns an error' do
        post :upvote, params: { id: 'invalid' }
        expect(response.body).to eq("can't find story")
        expect(response.status).to eq(400)
      end
    end
  end
end