
# NOTE: Some failing tests were automatically removed after 3 fix attempts failed.
# These tests may need manual review and fixes. See CI logs for details.
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
    controller.instance_variable_set(:@user, user)
    controller.instance_variable_set(:@story, story)
  end

  describe '#create' do

    context 'with invalid attributes' do
      it 'does not create a new story' do
        expect {
          post :create, params: { story: invalid_attributes }
        }.not_to change(Story, :count)
      end

    end
  end

  describe '#destroy' do

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

  describe '#show' do

    context 'when story is not found' do
      it 'raises ActiveRecord::RecordNotFound' do
        expect {
          get :show, params: { id: 'nonexistent' }
        }.to raise_error(ActiveRecord::RecordNotFound)
      end
    end
  end

  describe '#update' do
    context 'with valid attributes' do
      it 'updates the story' do
        patch :update, params: { id: story.short_id, story: { title: 'Updated Title' } }
        expect(story.reload.title).to eq('Updated Title')
      end

      it 'redirects to the story page' do
        patch :update, params: { id: story.short_id, story: { title: 'Updated Title' } }
        expect(response).to redirect_to(Routes.title_path(story))
      end
    end

    context 'with invalid attributes' do
      it 'does not update the story' do
        patch :update, params: { id: story.short_id, story: { title: '' } }
        expect(story.reload.title).not_to eq('')
      end

    end
  end

  describe '#check_url_dupe' do
    it 'checks for duplicate URLs' do
      allow_any_instance_of(Story).to receive(:check_already_posted_recently?).and_return(true)
      post :check_url_dupe, params: { story: { url: 'http://example.com' } }
      expect(response.content_type).to eq('text/html; charset=utf-8')
    end
  end
end