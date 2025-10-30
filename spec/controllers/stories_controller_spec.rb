require 'rails_helper'

RSpec.describe StoriesController do
  let(:user) { create(:user) }
  let(:story) { create(:story, user: user) }
  let(:valid_attributes) { { title: 'Test Story', url: 'http://example.com', description: 'A test story' } }
  let(:invalid_attributes) { { title: '', url: '', description: '' } }

  before do
    allow(controller).to receive(:require_logged_in_user_or_400).and_return(true)
    allow(controller).to receive(:require_logged_in_user).and_return(true)
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

  describe 'GET #edit' do
    context 'when user is authorized' do
      it 'renders the edit template' do
        get :edit, params: { id: story.to_param }
        expect(response).to render_template('edit')
      end
    end

    context 'when user is not authorized' do
      before do
        allow(story).to receive(:is_editable_by_user?).and_return(false)
      end

      it 'redirects to the root path' do
        get :edit, params: { id: story.to_param }
        expect(response).to redirect_to('/')
      end
    end
  end

  describe 'GET #show' do
    context 'when story is found' do
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

  describe 'POST #upvote' do
    context 'when story is found' do
      it 'returns ok' do
        post :upvote, params: { id: story.to_param }
        expect(response.body).to eq('ok')
      end
    end

    context 'when story is not found' do
      it 'returns error message' do
        post :upvote, params: { id: 'nonexistent' }
        expect(response.body).to eq("can't find story")
      end
    end
  end

  describe 'POST #flag' do
    context 'when story is found and reason is valid' do
      before do
        allow(Vote::STORY_REASONS).to receive(:[]).and_return(true)
        allow(user).to receive(:can_flag?).and_return(true)
      end

      it 'returns ok' do
        post :flag, params: { id: story.to_param, reason: 'spam' }
        expect(response.body).to eq('ok')
      end
    end

    context 'when reason is invalid' do
      it 'returns invalid reason message' do
        post :flag, params: { id: story.to_param, reason: 'invalid' }
        expect(response.body).to eq('invalid reason')
      end
    end

    context 'when user is not permitted to flag' do
      before do
        allow(user).to receive(:can_flag?).and_return(false)
      end

      it 'returns not permitted message' do
        post :flag, params: { id: story.to_param, reason: 'spam' }
        expect(response.body).to eq('not permitted to flag')
      end
    end
  end
end