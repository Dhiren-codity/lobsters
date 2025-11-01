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
      it 'renders the new template' do
        post :create, params: { story: invalid_attributes }
        expect(response).to render_template('new')
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

      it 'redirects to the root path with an error' do
        delete :destroy, params: { id: story.to_param }
        expect(response).to redirect_to('/')
        expect(flash[:error]).to eq('You cannot edit that story.')
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

      it 'redirects to the root path with an error' do
        get :edit, params: { id: story.to_param }
        expect(response).to redirect_to('/')
        expect(flash[:error]).to eq('You cannot edit that story.')
      end
    end
  end

  describe 'GET #fetch_url_attributes' do
    it 'returns fetched attributes as JSON' do
      get :fetch_url_attributes, params: { fetch_url: 'http://example.com' }
      expect(response.content_type).to eq('application/json')
    end
  end

  describe 'GET #new' do
    it 'renders the new template' do
      get :new
      expect(response).to render_template('new')
    end
  end

  describe 'POST #preview' do
    it 'renders the new template with preview layout' do
      post :preview, params: { story: valid_attributes }
      expect(response).to render_template('new')
    end
  end

  describe 'GET #show' do
    context 'when story is visible' do
      it 'renders the show template' do
        get :show, params: { id: story.to_param }
        expect(response).to render_template('show')
      end
    end

    context 'when story is not visible' do
      before do
        allow(story).to receive(:can_be_seen_by_user?).and_return(false)
      end

      it 'renders the missing template with 404 status' do
        get :show, params: { id: story.to_param }
        expect(response).to render_template('_missing')
        expect(response.status).to eq(404)
      end
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
    context 'with valid reason' do
      before do
        allow(Vote::STORY_REASONS).to receive(:[]).with('spam').and_return(true)
        allow(user).to receive(:can_flag?).and_return(true)
      end

      it 'flags the story' do
        expect(Vote).to receive(:vote_thusly_on_story_or_comment_for_user_because).with(-1, story.id, nil, user.id, 'spam')
        post :flag, params: { id: story.to_param, reason: 'spam' }
        expect(response.body).to eq('ok')
      end
    end

    context 'with invalid reason' do
      it 'returns an error' do
        post :flag, params: { id: story.to_param, reason: 'invalid' }
        expect(response.body).to eq('invalid reason')
      end
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

  describe 'GET #check_url_dupe' do
    it 'checks for duplicate URLs' do
      expect_any_instance_of(Story).to receive(:check_already_posted_recently?)
      get :check_url_dupe, params: { story: { url: 'http://example.com' } }
      expect(response.content_type).to eq('text/html')
    end
  end

  describe 'POST #disown' do
    it 'disowns the story' do
      expect(InactiveUser).to receive(:disown!).with(story)
      post :disown, params: { id: story.to_param }
      expect(response).to redirect_to(Routes.title_path(story))
    end
  end
end