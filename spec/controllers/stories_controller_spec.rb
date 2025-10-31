require 'rails_helper'

RSpec.describe StoriesController do
  let(:user) { create(:user) }
  let(:story) { create(:story, user: user) }
  let(:valid_attributes) { { title: 'New Story', url: 'http://example.com', description: 'A new story' } }
  let(:invalid_attributes) { { title: '', url: '', description: '' } }

  before do
    controller.instance_variable_set(:@user, user)
    controller.instance_variable_set(:@story, story)
    allow(controller).to receive(:require_logged_in_user).and_return(true)
    allow(controller).to receive(:require_logged_in_user_or_400).and_return(true)
    allow(controller).to receive(:verify_user_can_submit_stories).and_return(true)
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
        expect(response).to be_successful
        expect(response.body).to include("Submit Story")
      end
    end
  end

  describe 'DELETE #destroy' do
    context 'when user can edit the story' do
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

    context 'when user cannot edit the story' do
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
    context 'when user can edit the story' do
      it 'renders the edit template' do
        get :edit, params: { id: story.to_param }
        expect(response).to be_successful
        expect(response.body).to include("Edit Story")
      end
    end

    context 'when user cannot edit the story' do
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
      get :fetch_url_attributes, params: { fetch_url: 'http://example.com' }, format: :json
      expect(response.content_type).to eq('application/json')
    end
  end

  describe 'GET #new' do
    it 'renders the new template' do
      get :new
      expect(response).to be_successful
      expect(response.body).to include("Submit Story")
    end
  end

  describe 'POST #preview' do
    it 'renders the new template with preview layout' do
      post :preview, params: { story: valid_attributes }
      expect(response).to be_successful
      expect(response.body).to include("Submit Story")
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

      it 'renders the missing template with 404 status' do
        get :show, params: { id: story.to_param }
        expect(response.status).to eq(404)
        expect(response.body).to include("missing")
      end
    end
  end

  describe 'PATCH #update' do
    context 'with valid params' do
      it 'updates the requested story' do
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
        expect(response).to be_successful
        expect(response.body).to include("Edit Story")
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
      it 'returns error' do
        post :upvote, params: { id: 'invalid' }
        expect(response.body).to eq("can't find story")
      end
    end
  end

  describe 'POST #flag' do
    context 'when reason is valid' do
      it 'returns ok' do
        allow(Vote::STORY_REASONS).to receive(:[]).and_return(true)
        post :flag, params: { id: story.to_param, reason: 'spam' }
        expect(response.body).to eq('ok')
      end
    end

    context 'when reason is invalid' do
      it 'returns error' do
        post :flag, params: { id: story.to_param, reason: 'invalid' }
        expect(response.body).to eq('invalid reason')
      end
    end
  end

  describe 'POST #hide' do
    context 'when story is found' do
      it 'returns ok' do
        post :hide, params: { id: story.to_param }
        expect(response.body).to eq('ok')
      end
    end

    context 'when story is not found' do
      it 'returns error' do
        post :hide, params: { id: 'invalid' }
        expect(response.body).to eq("can't find story")
      end
    end
  end

  # Removed: Route 'unhide' does not exist
  # describe 'POST #unhide' do
  #   context 'when story is found' do
  #     it 'returns ok' do
  #       post :unhide, params: { id: story.to_param }
  #       expect(response.body).to eq('ok')
  #     end
  #   end

  #   context 'when story is not found' do
  #     it 'returns error' do
  #       post :unhide, params: { id: 'invalid' }
  #       expect(response.body).to eq("can't find story")
  #     end
  #   end
  # end

  describe 'POST #save' do
    context 'when story is found' do
      it 'returns ok' do
        post :save, params: { id: story.to_param }
        expect(response.body).to eq('ok')
      end
    end

    context 'when story is not found' do
      it 'returns error' do
        post :save, params: { id: 'invalid' }
        expect(response.body).to eq("can't find story")
      end
    end
  end

  describe 'POST #unsave' do
    context 'when story is found' do
      it 'returns ok' do
        post :unsave, params: { id: story.to_param }
        expect(response.body).to eq('ok')
      end
    end

    context 'when story is not found' do
      it 'returns error' do
        post :unsave, params: { id: 'invalid' }
        expect(response.body).to eq("can't find story")
      end
    end
  end

  describe 'POST #check_url_dupe' do
    context 'when URL is provided' do
      it 'returns similar stories as JSON' do
        post :check_url_dupe, params: { story: { url: 'http://example.com' } }, format: :json
        expect(response.content_type).to eq('application/json')
      end
    end

    context 'when URL is not provided' do
      it 'raises an error' do
        expect {
          post :check_url_dupe, params: { story: { url: '' } }
        }.to raise_error(ActionController::ParameterMissing)
      end
    end
  end

  describe 'POST #disown' do
    context 'when story is disownable' do
      before do
        allow(story).to receive(:disownable_by_user?).and_return(true)
      end

      it 'disowns the story and redirects' do
        post :disown, params: { id: story.to_param }
        expect(response).to redirect_to(Routes.title_path(story))
      end
    end

    context 'when story is not disownable' do
      it 'returns error' do
        post :disown, params: { id: 'invalid' }
        expect(response.body).to eq("can't find story")
      end
    end
  end
end