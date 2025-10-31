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

  describe '#create' do
    context 'with valid attributes' do
      it 'creates a new story' do
        expect {
          post :create, params: { story: valid_attributes }
        }.to change(Story, :count).by(1)
      end

      it 'redirects to the story page' do
        post :create, params: { story: valid_attributes }
        expect(response).to redirect_to(Routes.title_path(Story.last))
      end
    end

    context 'with invalid attributes' do
      it 'does not create a new story' do
        expect {
          post :create, params: { story: invalid_attributes }
        }.not_to change(Story, :count)
      end

      it 'renders the new template' do
        post :create, params: { story: invalid_attributes }
        expect(response).to render_template('new')
      end
    end
  end

  describe '#destroy' do
    context 'when user is authorized' do
      it 'deletes the story' do
        story
        expect {
          delete :destroy, params: { id: story.short_id }
        }.to change(Story, :count).by(-1)
      end

      it 'redirects to the root path' do
        delete :destroy, params: { id: story.short_id }
        expect(response).to redirect_to(Routes.title_path(story))
      end
    end

    context 'when user is not authorized' do
      before do
        allow(story).to receive(:is_editable_by_user?).and_return(false)
        allow(user).to receive(:is_moderator?).and_return(false)
      end

      it 'does not delete the story' do
        story
        expect {
          delete :destroy, params: { id: story.short_id }
        }.not_to change(Story, :count)
      end

      it 'redirects to the root path with an error' do
        delete :destroy, params: { id: story.short_id }
        expect(response).to redirect_to('/')
        expect(flash[:error]).to eq('You cannot edit that story.')
      end
    end
  end

  describe '#edit' do
    context 'when user is authorized' do
      it 'renders the edit template' do
        get :edit, params: { id: story.short_id }
        expect(response).to render_template('edit')
      end
    end

    context 'when user is not authorized' do
      before do
        allow(story).to receive(:is_editable_by_user?).and_return(false)
      end

      it 'redirects to the root path with an error' do
        get :edit, params: { id: story.short_id }
        expect(response).to redirect_to('/')
        expect(flash[:error]).to eq('You cannot edit that story.')
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
    it 'renders the new template' do
      get :new
      expect(response).to render_template('new')
    end
  end

  describe '#preview' do
    it 'renders the new template with preview layout' do
      post :preview, params: { story: valid_attributes }
      expect(response).to render_template('new')
    end
  end

  describe '#show' do
    context 'when story is found' do
      it 'renders the show template' do
        get :show, params: { id: story.short_id }
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

  describe '#undelete' do
    context 'when user is authorized' do
      it 'undeletes the story' do
        story.update(is_deleted: true)
        post :undelete, params: { id: story.short_id }
        expect(story.reload.is_deleted).to be_falsey
      end

      it 'redirects to the story page' do
        post :undelete, params: { id: story.short_id }
        expect(response).to redirect_to(Routes.title_path(story))
      end
    end

    context 'when user is not authorized' do
      before do
        allow(story).to receive(:is_editable_by_user?).and_return(false)
        allow(story).to receive(:is_undeletable_by_user?).and_return(false)
      end

      it 'does not undelete the story' do
        story.update(is_deleted: true)
        post :undelete, params: { id: story.short_id }
        expect(story.reload.is_deleted).to be_truthy
      end

      it 'redirects to the root path with an error' do
        post :undelete, params: { id: story.short_id }
        expect(response).to redirect_to('/')
        expect(flash[:error]).to eq('You cannot edit that story.')
      end
    end
  end

  describe '#update' do
    context 'with valid attributes' do
      it 'updates the story' do
        patch :update, params: { id: story.short_id, story: valid_attributes }
        story.reload
        expect(story.title).to eq('Test Story')
      end

      it 'redirects to the story page' do
        patch :update, params: { id: story.short_id, story: valid_attributes }
        expect(response).to redirect_to(Routes.title_path(story))
      end
    end

    context 'with invalid attributes' do
      it 'does not update the story' do
        patch :update, params: { id: story.short_id, story: invalid_attributes }
        story.reload
        expect(story.title).not_to eq('')
      end

      it 'renders the edit template' do
        patch :update, params: { id: story.short_id, story: invalid_attributes }
        expect(response).to render_template('edit')
      end
    end
  end

  describe '#unvote' do
    it 'removes the user vote from the story' do
      allow(controller).to receive(:find_story).and_return(story)
      expect(Vote).to receive(:vote_thusly_on_story_or_comment_for_user_because).with(0, story.id, nil, user.id, nil)
      post :unvote, params: { id: story.short_id }
      expect(response.body).to eq('ok')
    end
  end

  describe '#upvote' do
    it 'adds a user vote to the story' do
      allow(controller).to receive(:find_story).and_return(story)
      expect(Vote).to receive(:vote_thusly_on_story_or_comment_for_user_because).with(1, story.id, nil, user.id, nil)
      post :upvote, params: { id: story.short_id }
      expect(response.body).to eq('ok')
    end
  end

  describe '#flag' do
    it 'flags the story with a valid reason' do
      allow(controller).to receive(:find_story).and_return(story)
      allow(user).to receive(:can_flag?).and_return(true)
      expect(Vote).to receive(:vote_thusly_on_story_or_comment_for_user_because).with(-1, story.id, nil, user.id, 'spam')
      post :flag, params: { id: story.short_id, reason: 'spam' }
      expect(response.body).to eq('ok')
    end

    it 'returns an error for an invalid reason' do
      allow(controller).to receive(:find_story).and_return(story)
      post :flag, params: { id: story.short_id, reason: 'invalid' }
      expect(response.body).to eq('invalid reason')
    end
  end

  describe '#hide' do
    it 'hides the story for the user' do
      allow(controller).to receive(:find_story).and_return(story)
      expect(HiddenStory).to receive(:hide_story_for_user).with(story, user)
      post :hide, params: { id: story.short_id }
      expect(response.body).to eq('ok')
    end
  end

  describe '#unhide' do
    it 'unhides the story for the user' do
      allow(controller).to receive(:find_story).and_return(story)
      expect(HiddenStory).to receive(:unhide_story_for_user).with(story, user)
      post :unhide, params: { id: story.short_id }
      expect(response.body).to eq('ok')
    end
  end

  describe '#save' do
    it 'saves the story for the user' do
      allow(controller).to receive(:find_story).and_return(story)
      expect(SavedStory).to receive(:save_story_for_user).with(story.id, user.id)
      post :save, params: { id: story.short_id }
      expect(response.body).to eq('ok')
    end
  end

  describe '#unsave' do
    it 'unsaves the story for the user' do
      allow(controller).to receive(:find_story).and_return(story)
      expect(SavedStory).to receive(:where).with(user_id: user.id, story_id: story.id).and_return(double(delete_all: true))
      post :unsave, params: { id: story.short_id }
      expect(response.body).to eq('ok')
    end
  end

  describe '#check_url_dupe' do
    it 'checks for duplicate URLs' do
      allow_any_instance_of(Story).to receive(:check_already_posted_recently?).and_return(true)
      post :check_url_dupe, params: { story: { url: 'http://example.com' } }
      expect(response).to be_successful
    end
  end

  describe '#disown' do
    it 'disowns the story' do
      allow(controller).to receive(:find_story).and_return(story)
      allow(story).to receive(:disownable_by_user?).and_return(true)
      expect(InactiveUser).to receive(:disown!).with(story)
      post :disown, params: { id: story.short_id }
      expect(response).to redirect_to(Routes.title_path(story))
    end
  end
end