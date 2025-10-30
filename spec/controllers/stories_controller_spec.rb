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
    context 'when story is valid and not already posted' do
      before do
        allow_any_instance_of(Story).to receive(:valid?).and_return(true)
        allow_any_instance_of(Story).to receive(:already_posted_recently?).and_return(false)
        allow_any_instance_of(Story).to receive(:is_resubmit?).and_return(false)
      end

      it 'saves the story and redirects to the story path' do
        post :create, params: { story: { title: 'New Story', url: 'http://example.com' } }
        expect(response).to redirect_to(Routes.title_path(assigns(:story)))
      end
    end

    context 'when story is invalid' do
      before do
        allow_any_instance_of(Story).to receive(:valid?).and_return(false)
      end

      it 'renders the new action' do
        post :create, params: { story: { title: '', url: '' } }
        expect(response).to render_template(:new)
      end
    end
  end

  describe '#destroy' do
    context 'when user is authorized to delete the story' do
      before do
        allow(story).to receive(:is_editable_by_user?).and_return(true)
      end

      it 'deletes the story and redirects to the story path' do
        delete :destroy, params: { id: story.short_id }
        expect(response).to redirect_to(Routes.title_path(story))
      end
    end

    context 'when user is not authorized to delete the story' do
      before do
        allow(story).to receive(:is_editable_by_user?).and_return(false)
      end

      it 'redirects to the root path with an error message' do
        delete :destroy, params: { id: story.short_id }
        expect(response).to redirect_to('/')
        expect(flash[:error]).to eq('You cannot edit that story.')
      end
    end
  end

  describe '#edit' do
    context 'when user is authorized to edit the story' do
      before do
        allow(story).to receive(:is_editable_by_user?).and_return(true)
      end

      it 'renders the edit template' do
        get :edit, params: { id: story.short_id }
        expect(response).to render_template(:edit)
      end
    end

    context 'when user is not authorized to edit the story' do
      before do
        allow(story).to receive(:is_editable_by_user?).and_return(false)
      end

      it 'redirects to the root path with an error message' do
        get :edit, params: { id: story.short_id }
        expect(response).to redirect_to('/')
        expect(flash[:error]).to eq('You cannot edit that story.')
      end
    end
  end

  describe '#upvote' do
    context 'when story is found and not gone' do
      it 'votes on the story and returns ok' do
        post :upvote, params: { id: story.short_id }
        expect(response.body).to eq('ok')
      end
    end

    context 'when story is not found' do
      before do
        allow(controller).to receive(:find_story).and_return(nil)
      end

      it 'returns an error message' do
        post :upvote, params: { id: 'nonexistent' }
        expect(response.body).to eq("can't find story")
        expect(response.status).to eq(400)
      end
    end
  end

  describe '#flag' do
    context 'when user can flag the story' do
      before do
        allow(user).to receive(:can_flag?).and_return(true)
      end

      it 'flags the story and returns ok' do
        post :flag, params: { id: story.short_id, reason: 'spam' }
        expect(response.body).to eq('ok')
      end
    end

    context 'when user cannot flag the story' do
      before do
        allow(user).to receive(:can_flag?).and_return(false)
      end

      it 'returns an error message' do
        post :flag, params: { id: story.short_id, reason: 'spam' }
        expect(response.body).to eq('not permitted to flag')
        expect(response.status).to eq(400)
      end
    end
  end
end