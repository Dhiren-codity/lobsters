require 'rails_helper'
require 'spec_helper'

RSpec.describe StoriesController, type: :controller do
  let(:user) { create(:user) }
  let(:story) { create(:story, user: user) }
  let(:moderator) { create(:user, :moderator) }

  before do
    sign_in user
    allow(controller).to receive(:require_logged_in_user_or_400).and_return(true)
    allow(controller).to receive(:require_logged_in_user).and_return(true)
    allow(controller).to receive(:verify_user_can_submit_stories).and_return(true)
    allow(controller).to receive(:find_user_story).and_return(true)
    allow(controller).to receive(:track_story_reads).and_yield
    allow(controller).to receive(:show_title_h1).and_return(true)
    allow(controller).to receive(:find_story).and_return(story)
  end

  describe '#create' do
    context 'when preview is true' do
      it 'calls the preview method' do
        post :create, params: { preview: true }
        expect(response).to render_template(:new)
      end
    end

    context 'when story is valid and not already posted' do
      it 'saves the story and redirects' do
        allow_any_instance_of(Story).to receive(:valid?).and_return(true)
        allow_any_instance_of(Story).to receive(:already_posted_recently?).and_return(false)
        allow_any_instance_of(Story).to receive(:is_resubmit?).and_return(false)

        post :create, params: { story: { title: 'Test Story', url: 'http://example.com' } }
        expect(response).to redirect_to(story_path(assigns(:story)))
      end
    end

    context 'when story is invalid' do
      it 'renders the new template' do
        allow_any_instance_of(Story).to receive(:valid?).and_return(false)

        post :create, params: { story: { title: '', url: '' } }
        expect(response).to render_template(:new)
      end
    end
  end

  describe '#destroy' do
    context 'when user is not authorized' do
      it 'redirects with an error message' do
        allow(story).to receive(:is_editable_by_user?).and_return(false)
        allow(user).to receive(:is_moderator?).and_return(false)

        delete :destroy, params: { id: story.id }
        expect(response).to redirect_to('/')
        expect(flash[:error]).to eq('You cannot edit that story.')
      end
    end

    context 'when user is authorized' do
      it 'deletes the story and redirects' do
        allow(story).to receive(:is_editable_by_user?).and_return(true)

        delete :destroy, params: { id: story.id }
        expect(response).to redirect_to(story_path(story))
      end
    end
  end

  describe '#edit' do
    context 'when user is not authorized' do
      it 'redirects with an error message' do
        allow(story).to receive(:is_editable_by_user?).and_return(false)

        get :edit, params: { id: story.id }
        expect(response).to redirect_to('/')
        expect(flash[:error]).to eq('You cannot edit that story.')
      end
    end

    context 'when user is authorized' do
      it 'renders the edit template' do
        allow(story).to receive(:is_editable_by_user?).and_return(true)

        get :edit, params: { id: story.id }
        expect(response).to render_template(:edit)
      end
    end
  end

  describe '#fetch_url_attributes' do
    it 'returns fetched attributes as JSON' do
      allow_any_instance_of(Story).to receive(:fetched_attributes).and_return({ title: 'Fetched Title' })

      get :fetch_url_attributes, params: { fetch_url: 'http://example.com' }
      expect(response.content_type).to eq('application/json; charset=utf-8')
      expect(response.body).to include('Fetched Title')
    end
  end

  describe '#new' do
    it 'initializes a new story and renders the new template' do
      get :new
      expect(assigns(:story)).to be_a_new(Story)
      expect(response).to render_template(:new)
    end
  end

  describe '#preview' do
    it 'renders the new template with previewing set to true' do
      post :preview, params: { story: { title: 'Preview Story', url: 'http://example.com' } }
      expect(assigns(:story).previewing).to be true
      expect(response).to render_template(:new)
    end
  end

  describe '#show' do
    context 'when story is merged' do
      it 'redirects to the merged story' do
        allow(story).to receive(:merged_into_story).and_return(create(:story))

        get :show, params: { id: story.short_id }
        expect(response).to redirect_to(story_path(story.merged_into_story))
      end
    end

    context 'when story is not visible' do
      it 'renders the missing template' do
        allow(story).to receive(:can_be_seen_by_user?).and_return(false)

        get :show, params: { id: story.short_id }
        expect(response).to render_template('_missing')
      end
    end

    context 'when story is visible' do
      it 'renders the show template' do
        allow(story).to receive(:can_be_seen_by_user?).and_return(true)

        get :show, params: { id: story.short_id }
        expect(response).to render_template(:show)
      end
    end
  end

  # Removed undelete action tests as the route/action does not exist

  describe '#update' do
    context 'when user is not authorized' do
      it 'redirects with an error message' do
        allow(story).to receive(:is_editable_by_user?).and_return(false)

        patch :update, params: { id: story.id, story: { title: 'Updated Title' } }
        expect(response).to redirect_to('/')
        expect(flash[:error]).to eq('You cannot edit that story.')
      end
    end

    context 'when user is authorized' do
      it 'updates the story and redirects' do
        allow(story).to receive(:is_editable_by_user?).and_return(true)

        patch :update, params: { id: story.id, story: { title: 'Updated Title' } }
        expect(response).to redirect_to(story_path(story))
      end
    end
  end

  describe '#unvote' do
    it 'removes the vote and returns ok' do
      post :unvote, params: { id: story.id }
      expect(response.body).to eq('ok')
    end
  end

  describe '#upvote' do
    context 'when story is merged' do
      it 'returns an error message' do
        allow(story).to receive(:merged_into_story).and_return(create(:story))

        post :upvote, params: { id: story.id }
        expect(response.body).to eq('story has been merged')
      end
    end

    context 'when story is not merged' do
      it 'adds an upvote and returns ok' do
        post :upvote, params: { id: story.id }
        expect(response.body).to eq('ok')
      end
    end
  end

  describe '#flag' do
    context 'when reason is invalid' do
      it 'returns an error message' do
        post :flag, params: { id: story.id, reason: 'invalid_reason' }
        expect(response.body).to eq('invalid reason')
      end
    end

    context 'when user is not permitted to flag' do
      it 'returns an error message' do
        allow(user).to receive(:can_flag?).and_return(false)

        post :flag, params: { id: story.id, reason: 'spam' }
        expect(response.body).to eq('not permitted to flag')
      end
    end

    context 'when user is permitted to flag' do
      it 'flags the story and returns ok' do
        allow(user).to receive(:can_flag?).and_return(true)

        post :flag, params: { id: story.id, reason: 'spam' }
        expect(response.body).to eq('ok')
      end
    end
  end

  describe '#hide' do
    context 'when story is merged' do
      it 'returns an error message' do
        allow(story).to receive(:merged_into_story).and_return(create(:story))

        post :hide, params: { id: story.id }
        expect(response.body).to eq('story has been merged')
      end
    end

    context 'when story is not merged' do
      it 'hides the story and returns ok' do
        post :hide, params: { id: story.id }
        expect(response.body).to eq('ok')
      end
    end
  end

  describe '#unhide' do
    it 'unhides the story and returns ok' do
      post :unhide, params: { id: story.id }
      expect(response.body).to eq('ok')
    end
  end

  describe '#save' do
    context 'when story is merged' do
      it 'returns an error message' do
        allow(story).to receive(:merged_into_story).and_return(create(:story))

        post :save, params: { id: story.id }
        expect(response.body).to eq('story has been merged')
      end
    end

    context 'when story is not merged' do
      it 'saves the story and returns ok' do
        post :save, params: { id: story.id }
        expect(response.body).to eq('ok')
      end
    end
  end

  describe '#unsave' do
    it 'unsaves the story and returns ok' do
      post :unsave, params: { id: story.id }
      expect(response.body).to eq('ok')
    end
  end

  describe '#check_url_dupe' do
    context 'when URL is missing' do
      it 'raises an error' do
        expect {
          post :check_url_dupe, params: { story: { url: '' } }
        }.to raise_error(ActionController::ParameterMissing)
      end
    end

    context 'when URL is present' do
      it 'returns similar stories as JSON' do
        allow_any_instance_of(Story).to receive(:public_similar_stories).and_return([story])

        post :check_url_dupe, params: { story: { url: 'http://example.com' } }, format: :json
        expect(response.content_type).to eq('application/json; charset=utf-8')
        expect(response.body).to include(story.title)
      end
    end
  end

  describe '#disown' do
    context 'when user is not authorized' do
      it 'returns an error message' do
        allow(story).to receive(:disownable_by_user?).and_return(false)

        post :disown, params: { id: story.id }
        expect(response.body).to eq("can't find story")
      end
    end

    context 'when user is authorized' do
      it 'disowns the story and redirects' do
        allow(story).to receive(:disownable_by_user?).and_return(true)

        post :disown, params: { id: story.id }
        expect(response).to redirect_to(story_path(story))
      end
    end
  end
end