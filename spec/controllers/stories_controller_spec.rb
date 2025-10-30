require 'rails_helper'

RSpec.describe StoriesController do
  let(:user) { create(:user) }
  let(:story) { create(:story, user: user) }
  let(:moderator) { create(:user, :moderator) }

  before do
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
        expect(controller).to receive(:preview)
        post :create, params: { preview: true }
      end
    end

    context 'when story is valid and not already posted recently' do
      before do
        allow_any_instance_of(Story).to receive(:valid?).and_return(true)
        allow_any_instance_of(Story).to receive(:already_posted_recently?).and_return(false)
        allow_any_instance_of(Story).to receive(:is_resubmit?).and_return(false)
      end

      it 'saves the story and redirects to the story path' do
        post :create
        expect(response).to redirect_to(Routes.title_path(assigns(:story)))
      end
    end

    context 'when story is invalid' do
      before do
        allow_any_instance_of(Story).to receive(:valid?).and_return(false)
      end

      it 'renders the new action' do
        post :create
        expect(response).to render_template(:new)
      end
    end
  end

  describe '#destroy' do
    context 'when user is not authorized to edit the story' do
      it 'redirects to root with an error message' do
        allow(story).to receive(:is_editable_by_user?).and_return(false)
        allow(user).to receive(:is_moderator?).and_return(false)
        delete :destroy, params: { id: story.id }
        expect(response).to redirect_to('/')
        expect(flash[:error]).to eq('You cannot edit that story.')
      end
    end

    context 'when user is authorized to edit the story' do
      it 'marks the story as deleted and redirects to the story path' do
        allow(story).to receive(:is_editable_by_user?).and_return(true)
        delete :destroy, params: { id: story.id }
        expect(story.reload.is_deleted).to be_truthy
        expect(response).to redirect_to(Routes.title_path(story))
      end
    end
  end

  describe '#edit' do
    context 'when user is not authorized to edit the story' do
      it 'redirects to root with an error message' do
        allow(story).to receive(:is_editable_by_user?).and_return(false)
        get :edit, params: { id: story.id }
        expect(response).to redirect_to('/')
        expect(flash[:error]).to eq('You cannot edit that story.')
      end
    end

    context 'when user is authorized to edit the story' do
      it 'renders the edit template' do
        allow(story).to receive(:is_editable_by_user?).and_return(true)
        get :edit, params: { id: story.id }
        expect(response).to render_template(:edit)
      end
    end
  end

  describe '#fetch_url_attributes' do
    it 'returns fetched attributes as JSON' do
      get :fetch_url_attributes, params: { fetch_url: 'http://example.com' }
      expect(response.content_type).to eq('application/json')
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
      post :preview
      expect(assigns(:story).previewing).to be_truthy
      expect(response).to render_template(:new)
    end
  end

  describe '#show' do
    context 'when story is merged into another story' do
      let(:merged_story) { create(:story) }

      before do
        allow(story).to receive(:merged_into_story).and_return(merged_story)
      end

      it 'redirects to the merged story path' do
        get :show, params: { id: story.short_id }
        expect(response).to redirect_to(Routes.title_path(merged_story, anchor: story.header_anchor))
      end
    end

    context 'when story is not visible to the user' do
      before do
        allow(story).to receive(:can_be_seen_by_user?).and_return(false)
      end

      it 'renders the missing template with 404 status' do
        get :show, params: { id: story.short_id }
        expect(response).to render_template(:_missing)
        expect(response.status).to eq(404)
      end
    end
  end

  describe '#undelete' do
    context 'when user is not authorized to undelete the story' do
      it 'redirects to root with an error message' do
        allow(story).to receive(:is_editable_by_user?).and_return(false)
        allow(story).to receive(:is_undeletable_by_user?).and_return(false)
        post :undelete, params: { id: story.id }
        expect(response).to redirect_to('/')
        expect(flash[:error]).to eq('You cannot edit that story.')
      end
    end

    context 'when user is authorized to undelete the story' do
      it 'marks the story as not deleted and redirects to the story path' do
        allow(story).to receive(:is_editable_by_user?).and_return(true)
        allow(story).to receive(:is_undeletable_by_user?).and_return(true)
        post :undelete, params: { id: story.id }
        expect(story.reload.is_deleted).to be_falsey
        expect(response).to redirect_to(Routes.title_path(story))
      end
    end
  end

  describe '#update' do
    context 'when user is not authorized to update the story' do
      it 'redirects to root with an error message' do
        allow(story).to receive(:is_editable_by_user?).and_return(false)
        patch :update, params: { id: story.id }
        expect(response).to redirect_to('/')
        expect(flash[:error]).to eq('You cannot edit that story.')
      end
    end

    context 'when user is authorized to update the story' do
      it 'updates the story and redirects to the story path' do
        allow(story).to receive(:is_editable_by_user?).and_return(true)
        patch :update, params: { id: story.id, story: { title: 'Updated Title' } }
        expect(story.reload.title).to eq('Updated Title')
        expect(response).to redirect_to(Routes.title_path(story))
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
    context 'when story is merged into another story' do
      let(:merged_story) { create(:story) }

      before do
        allow(story).to receive(:merged_into_story).and_return(merged_story)
      end

      it 'returns an error message' do
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
        post :flag, params: { id: story.id, reason: 'invalid' }
        expect(response.body).to eq('invalid reason')
      end
    end

    context 'when user is not permitted to flag' do
      before do
        allow(user).to receive(:can_flag?).and_return(false)
      end

      it 'returns an error message' do
        post :flag, params: { id: story.id, reason: 'spam' }
        expect(response.body).to eq('not permitted to flag')
      end
    end

    context 'when user is permitted to flag' do
      before do
        allow(user).to receive(:can_flag?).and_return(true)
      end

      it 'flags the story and returns ok' do
        post :flag, params: { id: story.id, reason: 'spam' }
        expect(response.body).to eq('ok')
      end
    end
  end

  describe '#hide' do
    context 'when story is merged into another story' do
      let(:merged_story) { create(:story) }

      before do
        allow(story).to receive(:merged_into_story).and_return(merged_story)
      end

      it 'returns an error message' do
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
    context 'when story is merged into another story' do
      let(:merged_story) { create(:story) }

      before do
        allow(story).to receive(:merged_into_story).and_return(merged_story)
      end

      it 'returns an error message' do
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
      it 'renders the form errors partial' do
        post :check_url_dupe, params: { story: { url: 'http://example.com' } }
        expect(response).to render_template(partial: 'stories/form_errors')
      end
    end
  end

  describe '#disown' do
    context 'when user is not authorized to disown the story' do
      it 'returns an error message' do
        allow(story).to receive(:disownable_by_user?).and_return(false)
        post :disown, params: { id: story.id }
        expect(response.body).to eq("can't find story")
      end
    end

    context 'when user is authorized to disown the story' do
      it 'disowns the story and redirects to the story path' do
        allow(story).to receive(:disownable_by_user?).and_return(true)
        post :disown, params: { id: story.id }
        expect(response).to redirect_to(Routes.title_path(story))
      end
    end
  end
end