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
      it 'deletes the story' do
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

      it 'does not delete the story' do
        story # create the story
        expect {
          delete :destroy, params: { id: story.to_param }
        }.to change(Story, :count).by(0)
      end

      it 'redirects to the root path' do
        delete :destroy, params: { id: story.to_param }
        expect(response).to redirect_to('/')
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
      it 'does not update the story' do
        patch :update, params: { id: story.to_param, story: invalid_attributes }
        story.reload
        expect(story.title).not_to eq('')
      end

      it 'renders the edit template' do
        patch :update, params: { id: story.to_param, story: invalid_attributes }
        expect(response).to render_template('edit')
      end
    end
  end

  describe 'GET #show' do
    context 'when story is found' do
      it 'assigns the requested story as @story' do
        get :show, params: { id: story.to_param }
        expect(assigns(:story)).to eq(story)
      end

      it 'renders the show template' do
        get :show, params: { id: story.to_param }
        expect(response).to render_template('show')
      end
    end

    context 'when story is not found' do
      it 'raises ActiveRecord::RecordNotFound' do
        expect {
          get :show, params: { id: 'nonexistent' }
        }.to raise_error(ActiveRecord::RecordNotFound)
      end
    end
  end
end