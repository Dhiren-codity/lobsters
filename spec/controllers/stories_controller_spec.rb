RSpec.describe StoriesController, type: :controller do
  let(:user) { FactoryBot.create(:user) }
  let!(:tag) { FactoryBot.create(:tag, active: true) }
  let(:valid_story_params) do
    {
      title: 'A test story',
      url: 'http://example.com/test',
      description: 'desc',
      user_is_author: '0',
      user_is_following: '0',
      tags: [tag.tag]
    }
  end

  describe 'GET #show' do
    let!(:story) { FactoryBot.create(:story, user: user, tags: [tag]) }

    it 'returns http success' do
      get :show, params: { id: story.short_id }
      expect(response).to have_http_status(:success)
    end
  end

  describe 'GET #new' do
    before do
      allow(controller).to receive(:require_logged_in_user).and_return(true)
      allow(controller).to receive(:verify_user_can_submit_stories).and_return(true)
      controller.instance_variable_set(:@user, user)
    end

    it 'returns http success' do
      get :new
      expect(response).to have_http_status(:success)
    end
  end

  describe 'POST #create' do
    before do
      allow(controller).to receive(:require_logged_in_user).and_return(true)
      allow(controller).to receive(:verify_user_can_submit_stories).and_return(true)
      controller.instance_variable_set(:@user, user)
    end

    it 'creates a new Story and redirects' do
      expect do
        post :create, params: { story: valid_story_params }
      end.to change(Story, :count).by(1)
      expect(response).to have_http_status(:redirect)
    end
  end

  describe 'GET #edit' do
    let!(:story) { FactoryBot.create(:story, user: user, tags: [tag]) }

    before do
      allow(controller).to receive(:require_logged_in_user).and_return(true)
      controller.instance_variable_set(:@user, user)
    end

    it 'returns http success for owner' do
      get :edit, params: { id: story.short_id }
      expect(response).to have_http_status(:success)
    end
  end

  describe 'PATCH #update' do
    let!(:story) { FactoryBot.create(:story, user: user, tags: [tag]) }

    before do
      allow(controller).to receive(:require_logged_in_user).and_return(true)
      controller.instance_variable_set(:@user, user)
    end

    it 'updates the story and redirects' do
      patch :update, params: { id: story.short_id, story: { title: 'Updated', tags: [tag.tag] } }
      expect(response).to have_http_status(:redirect)
      expect(story.reload.title).to eq('Updated')
    end
  end

  describe 'DELETE #destroy' do
    let!(:story) { FactoryBot.create(:story, user: user, tags: [tag]) }

    before do
      allow(controller).to receive(:require_logged_in_user).and_return(true)
      controller.instance_variable_set(:@user, user)
      allow(Mastodon).to receive(:delete_post).and_return(true)
    end

    it 'soft-deletes the story and redirects' do
      delete :destroy, params: { id: story.short_id, story: { title: story.title, tags: [tag.tag] } }
      expect(response).to have_http_status(:redirect)
      expect(story.reload.is_deleted).to be(true)
    end
  end

  describe 'POST #undelete' do
    let!(:story) { FactoryBot.create(:story, user: user, is_deleted: true, tags: [tag]) }

    before do
      allow(controller).to receive(:require_logged_in_user).and_return(true)
      controller.instance_variable_set(:@user, user)
    end

    it 'undeletes the story and redirects' do
      post :undelete, params: { id: story.short_id, story: { title: story.title, tags: [tag.tag] } }
      expect(response).to have_http_status(:redirect)
      expect(story.reload.is_deleted).to be(false)
    end
  end

  describe 'DELETE #unvote' do
    let!(:story) { FactoryBot.create(:story, user: user, tags: [tag]) }

    before do
      allow(controller).to receive(:require_logged_in_user_or_400).and_return(true)
      controller.instance_variable_set(:@user, user)
    end

    it 'returns ok' do
      delete :unvote, params: { id: story.short_id }
      expect(response).to have_http_status(:success)
      expect(response.body).to eq('ok')
    end
  end

  describe 'POST #upvote' do
    let!(:story) { FactoryBot.create(:story, user: user, tags: [tag]) }

    before do
      allow(controller).to receive(:require_logged_in_user_or_400).and_return(true)
      controller.instance_variable_set(:@user, user)
    end

    it 'upvotes and returns ok' do
      post :upvote, params: { id: story.short_id }
      expect(response).to have_http_status(:success)
      expect(response.body).to eq('ok')
    end
  end

  describe 'POST #flag' do
    let!(:story) { FactoryBot.create(:story, user: user, tags: [tag]) }

    before do
      allow(controller).to receive(:require_logged_in_user_or_400).and_return(true)
      controller.instance_variable_set(:@user, user)
    end

    it 'returns 400 for invalid reason' do
      post :flag, params: { id: story.short_id, reason: 'not_a_reason' }
      expect(response).to have_http_status(400)
      expect(response.body).to eq('invalid reason')
    end
  end

  describe 'POST #hide' do
    let!(:story) { FactoryBot.create(:story, user: user, tags: [tag]) }

    before do
      allow(controller).to receive(:require_logged_in_user_or_400).and_return(true)
      controller.instance_variable_set(:@user, user)
    end

    it 'hides the story and redirects' do
      expect do
        post :hide, params: { id: story.short_id }
      end.to change(HiddenStory, :count).by(1)
      expect(response).to have_http_status(:redirect)
    end
  end

  describe 'POST #unhide' do
    let!(:story) { FactoryBot.create(:story, user: user, tags: [tag]) }

    before do
      allow(controller).to receive(:require_logged_in_user_or_400).and_return(true)
      controller.instance_variable_set(:@user, user)
      HiddenStory.hide_story_for_user(story, user)
    end

    it 'unhides the story and redirects' do
      expect do
        post :unhide, params: { id: story.short_id }
      end.to change(HiddenStory, :count).by(-1)
      expect(response).to have_http_status(:redirect)
    end
  end

  describe 'POST #save' do
    let!(:story) { FactoryBot.create(:story, user: user, tags: [tag]) }

    before do
      allow(controller).to receive(:require_logged_in_user_or_400).and_return(true)
      controller.instance_variable_set(:@user, user)
    end

    it 'saves the story for the user and returns ok' do
      expect do
        post :save, params: { id: story.short_id }
      end.to change(SavedStory, :count).by(1)
      expect(response.body).to eq('ok')
    end
  end

  describe 'POST #unsave' do
    let!(:story) { FactoryBot.create(:story, user: user, tags: [tag]) }
    let!(:saved) { SavedStory.save_story_for_user(story.id, user.id) }

    before do
      allow(controller).to receive(:require_logged_in_user_or_400).and_return(true)
      controller.instance_variable_set(:@user, user)
    end

    it 'unsaves the story and returns ok' do
      expect do
        post :unsave, params: { id: story.short_id }
      end.to change(SavedStory, :count).by(-1)
      expect(response.body).to eq('ok')
    end
  end

  describe 'POST #preview' do
    before do
      allow(controller).to receive(:require_logged_in_user_or_400).and_return(true)
      controller.instance_variable_set(:@user, user)
    end

    it 'renders preview successfully' do
      post :preview, params: { story: valid_story_params }
      expect(response).to have_http_status(:success)
    end
  end

  describe 'GET #fetch_url_attributes' do
    before do
      allow(controller).to receive(:require_logged_in_user).and_return(true)
      controller.instance_variable_set(:@user, user)
      allow_any_instance_of(Story).to receive(:fetched_attributes).and_return({ url: 'http://example.com',
                                                                                title: 'Title' })
    end

    it 'returns JSON with fetched attributes' do
      get :fetch_url_attributes, params: { fetch_url: 'http://example.com' }, format: :json
      expect(response).to have_http_status(:success)
      expect(response.media_type).to eq('application/json')
      parsed = JSON.parse(response.body)
      expect(parsed['url']).to eq('http://example.com')
      expect(parsed['title']).to eq('Title')
    end
  end

  describe 'GET/POST #check_url_dupe' do
    before do
      allow(controller).to receive(:require_logged_in_user).and_return(true)
      controller.instance_variable_set(:@user, user)
    end

    it 'raises ParameterMissing when url is absent' do
      expect do
        get :check_url_dupe, params: { story: { title: 't', tags: [tag.tag] } }
      end.to raise_error(ActionController::ParameterMissing)
    end
  end

  describe 'POST #disown' do
    before do
      allow(controller).to receive(:require_logged_in_user_or_400).and_return(true)
      controller.instance_variable_set(:@user, user)
    end

    it "returns 400 when story can't be found" do
      post :disown, params: { id: 'nonexistent' }
      expect(response).to have_http_status(400)
      expect(response.body).to eq("can't find story")
    end
  end
end
