require 'rails_helper'

RSpec.describe StoriesController, type: :controller do
  let(:user) do
    instance_double(
      User,
      id: 1,
      is_moderator?: false,
      can_submit_stories?: true
    )
  end

  let(:moderator) do
    instance_double(
      User,
      id: 2,
      is_moderator?: true,
      can_submit_stories?: true
    )
  end

  let(:story) do
    instance_double(
      Story,
      id: 11,
      short_id: 's-11',
      title: 'Title',
      title_as_slug: 'title',
      url: 'http://example.com',
      most_recent_similar: nil,
      merged_into_story: nil,
      is_gone?: false,
      can_be_seen_by_user?: true,
      header_anchor: 'comment-1',
      merged_stories: double(not_deleted: double(mod_single_preload?: double(for_presentation: double(includes: [])))),
      user: instance_double(User, mastodon_username: nil, mastodon_acct: nil, id: 1),
      comments_count: 0
    )
  end

  before do
    allow(Routes).to receive(:title_path).and_return('/stories/s-11-title')
  end

  describe 'GET #show' do
    before do
      allow(Comment).to receive(:story_threads).and_return(
        double(for_presentation: double(includes: double(map: [], to_a: [])))
      )
    end

    context 'html success' do
      before do
        allow(Story).to receive(:where).with(short_id: 's-11').and_return(double(first!: story))
        allow(story).to receive(:can_be_seen_by_user?).with(nil).and_return(true)
      end

      it 'renders successfully' do
        get :show, params: { id: 's-11' }
        expect(response).to be_successful
      end
    end

    context 'json success' do
      let(:comments_relation) do
        double(for_presentation: double(includes: double(map: [], to_a: [])))
      end

      before do
        allow(Story).to receive(:where).with(short_id: 's-11').and_return(double(first!: story))
        allow(story).to receive(:can_be_seen_by_user?).with(nil).and_return(true)
        relation = double(for_presentation: comments_relation)
        allow(Comment).to receive(:story_threads).and_return(relation)
        allow(comments_relation).to receive(:includes).with(:parent_comment).and_return(comments_relation)
        allow(story).to receive(:as_json).with(with_comments: comments_relation).and_return({ 'id' => 's-11' })
      end

      it 'renders json' do
        get :show, params: { id: 's-11' }, format: :json
        expect(response).to be_successful
        json = JSON.parse(response.body)
        expect(json['id']).to eq('s-11')
      end
    end

    context 'redirects to canonical title if mismatched' do
      before do
        allow(Story).to receive(:where).with(short_id: 's-11').and_return(double(first!: story))
        allow(story).to receive(:title_as_slug).and_return('right-title')
        allow(story).to receive(:can_be_seen_by_user?).with(nil).and_return(true)
      end

      it 'redirects' do
        get :show, params: { id: 's-11', title: 'wrong-title' }
        expect(response).to redirect_to('/stories/s-11-title')
      end
    end

    context 'merged into another story (html)' do
      let(:merged_story) { instance_double(Story, short_id: 's-99') }

      before do
        allow(Story).to receive(:where).with(short_id: 's-11').and_return(double(first!: story))
        allow(story).to receive(:merged_into_story).and_return(merged_story)
        allow(story).to receive(:header_anchor).and_return('c123')
        allow(merged_story).to receive(:id).and_return(99)
        allow(Routes).to receive(:title_path).with(merged_story).and_return('/stories/s-99-merged')
      end

      it 'redirects with flash' do
        get :show, params: { id: 's-11' }
        expect(response).to redirect_to('/stories/s-99-merged#c123')
        expect(flash[:success]).to be_present
      end
    end

    context 'merged into another story (json)' do
      let(:merged_story) { instance_double(Story, short_id: 's-99') }

      before do
        allow(Story).to receive(:where).with(short_id: 's-11').and_return(double(first!: story))
        allow(story).to receive(:merged_into_story).and_return(merged_story)
        allow(controller).to receive(:story_path).with(merged_story, format: :json).and_return('/stories/s-99.json')
      end

      it 'redirects to merged story json' do
        get :show, params: { id: 's-11' }, format: :json
        expect(response).to redirect_to('/stories/s-99.json')
      end
    end

    context 'story is gone and not visible to user (html)' do
      before do
        allow(Story).to receive(:where).with(short_id: 's-11').and_return(double(first!: story))
        allow(story).to receive(:is_gone?).and_return(true)
        allow(story).to receive(:can_be_seen_by_user?).with(nil).and_return(false)
        mod_scope1 = double(where: double(where: double(order: double(first: nil))))
        allow(Moderation).to receive(:where).with(story: story, comment: nil).and_return(mod_scope1)
      end

      it 'renders missing with 404' do
        get :show, params: { id: 's-11' }
        expect(response.status).to eq(404)
      end
    end

    context 'story not visible to user (json)' do
      before do
        allow(Story).to receive(:where).with(short_id: 's-11').and_return(double(first!: story))
        allow(story).to receive(:is_gone?).and_return(false)
        allow(story).to receive(:can_be_seen_by_user?).with(nil).and_return(false)
      end

      it 'raises RecordNotFound' do
        expect do
          get :show, params: { id: 's-11' }, format: :json
        end.to raise_error(ActiveRecord::RecordNotFound)
      end
    end
  end

  describe 'GET #new' do
    before do
      allow(controller).to receive(:require_logged_in_user) do
        controller.instance_variable_set(:@user, user)
        true
      end
      allow(controller).to receive(:verify_user_can_submit_stories).and_return(true)
    end

    context 'simple new' do
      before do
        allow(Story).to receive(:new).with(user_id: user.id).and_return(story)
        allow(story).to receive(:fetching_ip=).with(anything)
        allow(story).to receive(:is_resubmit?).and_return(false)
      end

      it 'renders successfully' do
        get :new
        expect(response).to be_successful
      end
    end

    context 'with URL canonicalization and not recently posted' do
      let(:attrs) { { url: 'http://canonical.example', title: 'Fetched' } }

      before do
        allow(Story).to receive(:new).with(user_id: user.id).and_return(story)
        allow(story).to receive(:fetching_ip=).with(anything)
        allow(story).to receive(:url=).with('http://original.example')
        allow(story).to receive(:fetched_attributes).and_return(attrs)
        allow(story).to receive(:already_posted_recently?).and_return(false)
        allow(story).to receive(:is_resubmit?).and_return(false)
        allow(story).to receive(:title=).with('Fetched')
        allow(story).to receive(:title).and_return('Fetched')
      end

      it 'shows notice about canonical URL and stays on page' do
        get :new, params: { url: 'http://original.example' }
        expect(flash.now[:notice]).to be_present
        expect(response).to be_successful
      end
    end

    context 'already posted recently' do
      let(:prev_story) { instance_double(Story) }

      before do
        allow(Story).to receive(:new).with(user_id: user.id).and_return(story)
        allow(story).to receive(:fetching_ip=).with(anything)
        allow(story).to receive(:url=).with('http://original.example')
        allow(story).to receive(:fetched_attributes).and_return({ url: 'http://original.example', title: 't' })
        allow(story).to receive(:already_posted_recently?).and_return(true)
        allow(story).to receive(:most_recent_similar).and_return(prev_story)
        allow(Routes).to receive(:title_path).with(prev_story).and_return('/stories/prev')
      end

      it 'redirects to previous story' do
        get :new, params: { url: 'http://original.example' }
        expect(response).to redirect_to('/stories/prev')
        expect(flash[:success]).to be_present
      end
    end
  end

  describe 'POST #create' do
    let(:job_set) { instance_double(ActiveJob::ConfiguredJob, perform_later: true) }

    before do
      allow(controller).to receive(:require_logged_in_user) do
        controller.instance_variable_set(:@user, user)
        true
      end
      allow(controller).to receive(:verify_user_can_submit_stories).and_return(true)
      allow(SendWebmentionJob).to receive(:set).with(any_args).and_return(job_set)
    end

    context 'preview path' do
      before do
        allow(Story).to receive(:new).and_return(story)
        allow(controller).to receive(:update_story_attributes).and_return(true)
        allow(controller).to receive(:update_resubmit_comment_attributes).and_return(true)
        allow(story).to receive(:user_id=).with(user.id)
        allow(story).to receive(:previewing=).with(true)
        allow(story).to receive(:current_vote=)
        allow(story).to receive(:score=).with(1)
        allow(story).to receive(:valid?).and_return(true)
      end

      it 'renders new via preview' do
        post :create, params: { preview: '1', story: { title: 'x', url: 'y' } }
        expect(response).to be_successful
      end
    end

    context 'successful create' do
      before do
        allow(Story).to receive(:new).with(user: user).and_return(story)
        allow(controller).to receive(:update_story_attributes).and_return(true)
        allow(controller).to receive(:update_resubmit_comment_attributes).and_return(true)
        allow(story).to receive(:valid?).and_return(true)
        allow(story).to receive(:already_posted_recently?).and_return(false)
        allow(story).to receive(:is_resubmit?).and_return(false)
        allow(Story).to receive(:transaction).and_yield
        allow(story).to receive(:save).and_return(true)
        allow(ReadRibbon).to receive(:where).with(user: user, story: story).and_return(double(first_or_create!: true))
        allow(story).to receive(:persisted?).and_return(true)
      end

      it 'redirects to story and enqueues job' do
        expect(SendWebmentionJob).to receive(:set).with(wait: 5.minutes).and_return(job_set)
        post :create, params: { story: { title: 't', url: 'http://x' } }
        expect(response).to redirect_to('/stories/s-11-title')
      end
    end

    context 'failed create renders new' do
      before do
        allow(Story).to receive(:new).with(user: user).and_return(story)
        allow(controller).to receive(:update_story_attributes).and_return(true)
        allow(controller).to receive(:update_resubmit_comment_attributes).and_return(true)
        allow(story).to receive(:valid?).and_return(true)
        allow(story).to receive(:already_posted_recently?).and_return(false)
        allow(story).to receive(:is_resubmit?).and_return(false)
        allow(Story).to receive(:transaction).and_yield
        allow(story).to receive(:save).and_return(false)
        allow(story).to receive(:persisted?).and_return(false)
      end

      it 'renders new' do
        post :create, params: { story: { title: 't', url: 'http://x' } }
        expect(response).to be_successful
      end
    end
  end

  describe 'GET #edit' do
    before do
      allow(controller).to receive(:require_logged_in_user) do
        controller.instance_variable_set(:@user, user)
        true
      end
      allow(controller).to receive(:find_user_story) do
        controller.instance_variable_set(:@story, story)
        true
      end
    end

    it 'redirects when not editable' do
      allow(story).to receive(:is_editable_by_user?).with(user).and_return(false)
      get :edit, params: { id: story.short_id }
      expect(response).to redirect_to('/')
      expect(flash[:error]).to be_present
    end

    it 'renders when editable' do
      allow(story).to receive(:is_editable_by_user?).with(user).and_return(true)
      get :edit, params: { id: story.short_id }
      expect(response).to be_successful
    end
  end

  describe 'PATCH #update' do
    before do
      allow(controller).to receive(:require_logged_in_user) do
        controller.instance_variable_set(:@user, user)
        true
      end
      allow(controller).to receive(:find_user_story) do
        controller.instance_variable_set(:@story, story)
        true
      end
      allow(controller).to receive(:update_story_attributes).and_return(true)
      allow(story).to receive(:is_deleted=).with(false)
      allow(story).to receive(:editor=).with(user)
      allow(story).to receive(:last_edited_at=).with(instance_of(ActiveSupport::TimeWithZone).or(Time))
    end

    it 'redirects on success' do
      allow(story).to receive(:is_editable_by_user?).with(user).and_return(true)
      allow(story).to receive(:save).and_return(true)
      patch :update, params: { id: story.short_id, story: { title: 'new' } }
      expect(response).to redirect_to('/stories/s-11-title')
    end

    it 'renders edit on failure' do
      allow(story).to receive(:is_editable_by_user?).with(user).and_return(true)
      allow(story).to receive(:save).and_return(false)
      patch :update, params: { id: story.short_id, story: { title: 'bad' } }
      expect(response).to be_successful
    end

    it 'forbidden when not editable' do
      allow(story).to receive(:is_editable_by_user?).with(user).and_return(false)
      patch :update, params: { id: story.short_id, story: { title: 'x' } }
      expect(response).to redirect_to('/')
      expect(flash[:error]).to be_present
    end
  end

  describe 'DELETE #destroy' do
    before do
      allow(controller).to receive(:require_logged_in_user) do
        controller.instance_variable_set(:@user, user)
        true
      end
      allow(controller).to receive(:find_user_story) do
        controller.instance_variable_set(:@story, story)
        true
      end
      allow(controller).to receive(:update_story_attributes).and_return(true)
      allow(story).to receive(:is_deleted=).with(true)
      allow(story).to receive(:editor=).with(user)
    end

    it 'redirects when not permitted' do
      allow(user).to receive(:is_moderator?).and_return(false)
      allow(story).to receive(:is_editable_by_user?).with(user).and_return(false)
      delete :destroy, params: { id: story.short_id }
      expect(response).to redirect_to('/')
      expect(flash[:error]).to be_present
    end

    it 'destroys and redirects when permitted' do
      allow(story).to receive(:is_editable_by_user?).with(user).and_return(true)
      allow(story).to receive(:save).and_return(true)
      allow(Keystore).to receive(:increment_value_for).with("user:#{story.user.id}:stories_deleted")
      allow(Mastodon).to receive(:delete_post).with(story)
      delete :destroy, params: { id: story.short_id }
      expect(response).to redirect_to('/stories/s-11-title')
    end
  end

  describe 'POST #undelete' do
    before do
      allow(controller).to receive(:require_logged_in_user) do
        controller.instance_variable_set(:@user, user)
        true
      end
      allow(controller).to receive(:find_user_story) do
        controller.instance_variable_set(:@story, story)
        true
      end
      allow(controller).to receive(:update_story_attributes).and_return(true)
      allow(story).to receive(:is_deleted=).with(false)
      allow(story).to receive(:editor=).with(user)
    end

    it 'forbidden when not undeletable' do
      allow(story).to receive(:is_editable_by_user?).with(user).and_return(false)
      allow(story).to receive(:is_undeletable_by_user?).with(user).and_return(false)
      post :undelete, params: { id: story.short_id }
      expect(response).to redirect_to('/')
      expect(flash[:error]).to be_present
    end

    it 'undeletes and redirects when permitted' do
      allow(story).to receive(:is_editable_by_user?).with(user).and_return(true)
      allow(story).to receive(:is_undeletable_by_user?).with(user).and_return(true)
      allow(story).to receive(:save).and_return(true)
      allow(Keystore).to receive(:increment_value_for).with("user:#{story.user.id}:stories_deleted", -1)
      post :undelete, params: { id: story.short_id }
      expect(response).to redirect_to('/stories/s-11-title')
    end
  end

  describe 'POST #unvote' do
    before do
      allow(controller).to receive(:require_logged_in_user_or_400) do
        controller.instance_variable_set(:@user, user)
        true
      end
    end

    it 'returns 400 when not found' do
      allow(controller).to receive(:find_story).and_return(nil)
      post :unvote, params: { id: 's-11' }
      expect(response.status).to eq(400)
      expect(response.body).to include("can't find story")
    end

    it 'ok when found' do
      allow(controller).to receive(:find_story).and_return(story)
      allow(story).to receive(:is_gone?).and_return(false)
      allow(Vote).to receive(:vote_thusly_on_story_or_comment_for_user_because).with(0, story.id, nil, user.id, nil)
      post :unvote, params: { id: 's-11' }
      expect(response).to be_successful
      expect(response.body).to eq('ok')
    end
  end

  describe 'POST #upvote' do
    before do
      allow(controller).to receive(:require_logged_in_user_or_400) do
        controller.instance_variable_set(:@user, user)
        true
      end
    end

    it 'returns 400 when merged' do
      allow(controller).to receive(:find_story).and_return(story)
      allow(story).to receive(:is_gone?).and_return(false)
      allow(story).to receive(:merged_into_story).and_return(instance_double(Story))
      post :upvote, params: { id: 's-11' }
      expect(response.status).to eq(400)
      expect(response.body).to include('story has been merged')
    end

    it 'votes when ok' do
      allow(controller).to receive(:find_story).and_return(story)
      allow(story).to receive(:is_gone?).and_return(false)
      allow(story).to receive(:merged_into_story).and_return(nil)
      allow(Vote).to receive(:vote_thusly_on_story_or_comment_for_user_because).with(1, story.id, nil, user.id, nil)
      post :upvote, params: { id: 's-11' }
      expect(response).to be_successful
      expect(response.body).to eq('ok')
    end
  end

  describe 'POST #flag' do
    before do
      allow(controller).to receive(:require_logged_in_user_or_400) do
        controller.instance_variable_set(:@user, user)
        true
      end
      stub_const('Vote::STORY_REASONS', { 'spam' => 'Spam' })
    end

    it 'invalid reason' do
      allow(controller).to receive(:find_story).and_return(story)
      allow(story).to receive(:is_gone?).and_return(false)
      post :flag, params: { id: 's-11', reason: 'bad' }
      expect(response.status).to eq(400)
      expect(response.body).to include('invalid reason')
    end

    it 'not permitted' do
      allow(controller).to receive(:find_story).and_return(story)
      allow(story).to receive(:is_gone?).and_return(false)
      allow(user).to receive(:can_flag?).with(story).and_return(false)
      post :flag, params: { id: 's-11', reason: 'spam' }
      expect(response.status).to eq(400)
      expect(response.body).to include('not permitted to flag')
    end

    it 'flags successfully' do
      allow(controller).to receive(:find_story).and_return(story)
      allow(story).to receive(:is_gone?).and_return(false)
      allow(user).to receive(:can_flag?).with(story).and_return(true)
      expect(Vote).to receive(:vote_thusly_on_story_or_comment_for_user_because).with(-1, story.id, nil, user.id,
                                                                                      'spam')
      post :flag, params: { id: 's-11', reason: 'spam' }
      expect(response).to be_successful
      expect(response.body).to eq('ok')
    end
  end

  describe 'POST #hide' do
    before do
      allow(controller).to receive(:require_logged_in_user_or_400) do
        controller.instance_variable_set(:@user, user)
        true
      end
    end

    it 'returns 400 when missing' do
      allow(controller).to receive(:find_story).and_return(nil)
      post :hide, params: { id: 's-11' }
      expect(response.status).to eq(400)
    end

    it 'returns 400 when merged' do
      allow(controller).to receive(:find_story).and_return(story)
      allow(story).to receive(:merged_into_story).and_return(instance_double(Story))
      post :hide, params: { id: 's-11' }
      expect(response.status).to eq(400)
      expect(response.body).to include('story has been merged')
    end

    it 'ok on xhr' do
      allow(controller).to receive(:find_story).and_return(story)
      allow(story).to receive(:merged_into_story).and_return(nil)
      allow(HiddenStory).to receive(:hide_story_for_user).with(story, user)
      allow(request).to receive(:xhr?).and_return(true)
      post :hide, params: { id: 's-11' }
      expect(response).to be_successful
      expect(response.body).to eq('ok')
    end

    it 'redirects on html' do
      allow(controller).to receive(:find_story).and_return(story)
      allow(story).to receive(:merged_into_story).and_return(nil)
      allow(HiddenStory).to receive(:hide_story_for_user).with(story, user)
      allow(request).to receive(:xhr?).and_return(false)
      allow(controller).to receive(:story_path).with(story).and_return('/stories/s-11')
      post :hide, params: { id: 's-11' }
      expect(response).to redirect_to('/stories/s-11')
    end
  end

  describe 'DELETE #unhide' do
    before do
      allow(controller).to receive(:require_logged_in_user_or_400) do
        controller.instance_variable_set(:@user, user)
        true
      end
    end

    it 'returns 400 when missing' do
      allow(controller).to receive(:find_story).and_return(nil)
      delete :unhide, params: { id: 's-11' }
      expect(response.status).to eq(400)
    end

    it 'ok on xhr' do
      allow(controller).to receive(:find_story).and_return(story)
      allow(HiddenStory).to receive(:unhide_story_for_user).with(story, user)
      allow(request).to receive(:xhr?).and_return(true)
      delete :unhide, params: { id: 's-11' }
      expect(response).to be_successful
      expect(response.body).to eq('ok')
    end

    it 'redirects on html' do
      allow(controller).to receive(:find_story).and_return(story)
      allow(HiddenStory).to receive(:unhide_story_for_user).with(story, user)
      allow(request).to receive(:xhr?).and_return(false)
      allow(controller).to receive(:story_path).with(story).and_return('/stories/s-11')
      delete :unhide, params: { id: 's-11' }
      expect(response).to redirect_to('/stories/s-11')
    end
  end

  describe 'POST #save' do
    before do
      allow(controller).to receive(:require_logged_in_user_or_400) do
        controller.instance_variable_set(:@user, user)
        true
      end
    end

    it 'returns 400 when missing' do
      allow(controller).to receive(:find_story).and_return(nil)
      post :save, params: { id: 's-11' }
      expect(response.status).to eq(400)
    end

    it 'returns 400 when merged' do
      allow(controller).to receive(:find_story).and_return(story)
      allow(story).to receive(:merged_into_story).and_return(instance_double(Story))
      post :save, params: { id: 's-11' }
      expect(response.status).to eq(400)
      expect(response.body).to include('story has been merged')
    end

    it 'saves' do
      allow(controller).to receive(:find_story).and_return(story)
      allow(story).to receive(:merged_into_story).and_return(nil)
      allow(SavedStory).to receive(:save_story_for_user).with(story.id, user.id)
      post :save, params: { id: 's-11' }
      expect(response).to be_successful
      expect(response.body).to eq('ok')
    end
  end

  describe 'DELETE #unsave' do
    before do
      allow(controller).to receive(:require_logged_in_user_or_400) do
        controller.instance_variable_set(:@user, user)
        true
      end
    end

    it 'returns 400 when missing' do
      allow(controller).to receive(:find_story).and_return(nil)
      delete :unsave, params: { id: 's-11' }
      expect(response.status).to eq(400)
    end

    it 'unsaves' do
      allow(controller).to receive(:find_story).and_return(story)
      rel = double(delete_all: 1)
      allow(SavedStory).to receive(:where).with(user_id: user.id, story_id: story.id).and_return(rel)
      delete :unsave, params: { id: 's-11' }
      expect(response).to be_successful
      expect(response.body).to eq('ok')
    end
  end

  describe 'GET #fetch_url_attributes' do
    let(:s) do
      instance_double(
        Story,
        fetched_attributes: { 'title' => 'Fetched Title', 'url' => 'http://example.com' }
      )
    end

    before do
      allow(controller).to receive(:require_logged_in_user) do
        controller.instance_variable_set(:@user, user)
        true
      end
      allow(Story).to receive(:new).and_return(s)
      allow(s).to receive(:fetching_ip=).with(anything)
      allow(s).to receive(:url=).with('http://example.com')
    end

    it 'returns fetched attributes json' do
      get :fetch_url_attributes, params: { fetch_url: 'http://example.com' }
      expect(response).to be_successful
      json = JSON.parse(response.body)
      expect(json['title']).to eq('Fetched Title')
    end
  end

  describe 'POST #preview' do
    before do
      allow(controller).to receive(:require_logged_in_user_or_400) do
        controller.instance_variable_set(:@user, user)
        true
      end
      allow(Story).to receive(:new).and_return(story)
      allow(controller).to receive(:update_story_attributes).and_return(true)
      allow(controller).to receive(:update_resubmit_comment_attributes).and_return(true)
      allow(story).to receive(:user_id=).with(user.id)
      allow(story).to receive(:previewing=).with(true)
      allow(story).to receive(:current_vote=)
      allow(story).to receive(:score=).with(1)
      allow(story).to receive(:valid?).and_return(true)
    end

    it 'renders new for preview' do
      post :preview, params: { story: { title: 'x', url: 'y' } }
      expect(response).to be_successful
    end
  end

  describe 'GET #check_url_dupe' do
    before do
      allow(controller).to receive(:require_logged_in_user) do
        controller.instance_variable_set(:@user, user)
        true
      end
    end

    it 'raises without url param' do
      expect do
        get :check_url_dupe, params: { story: { url: '' } }
      end.to raise_error(ActionController::ParameterMissing)
    end

    context 'html format' do
      before do
        allow(Story).to receive(:new).with(user: user).and_return(story)
        allow(controller).to receive(:update_story_attributes) do
          allow(story).to receive(:url).and_return('http://example.com')
        end
        allow(controller).to receive(:update_resubmit_comment_attributes).and_return(true)
        allow(story).to receive(:check_already_posted_recently?).and_return(true)
        allow(Link).to receive(:recently_linked_from_comments).with('http://example.com').and_return([])
      end

      it 'renders partial html' do
        get :check_url_dupe, params: { story: { url: 'http://example.com' } }
        expect(response).to be_successful
        expect(response.content_type).to include('text/html')
      end
    end

    context 'json format' do
      before do
        allow(Story).to receive(:new).with(user: user).and_return(story)
        allow(controller).to receive(:update_story_attributes) do
          allow(story).to receive(:url).and_return('http://example.com')
        end
        allow(controller).to receive(:update_resubmit_comment_attributes).and_return(true)
        allow(story).to receive(:check_already_posted_recently?).and_return(false)
        similar = [instance_double(Story, as_json: { id: 2 })]
        allow(story).to receive(:public_similar_stories).with(user).and_return(similar)
        allow(story).to receive(:as_json).and_return({ id: 1 })
      end

      it 'returns json with similar stories' do
        get :check_url_dupe, params: { story: { url: 'http://example.com' } }, format: :json
        expect(response).to be_successful
        json = JSON.parse(response.body)
        expect(json['id']).to eq(1)
        expect(json['similar_stories']).to be_an(Array)
      end
    end
  end

  describe 'POST #disown' do
    before do
      controller.instance_variable_set(:@user, user)
    end

    it 'returns 400 when not found or not disownable' do
      allow(controller).to receive(:find_story).and_return(nil)
      post :disown, params: { id: 's-11' }
      expect(response.status).to eq(400)
      expect(response.body).to include("can't find story")
    end

    it 'disowns and redirects' do
      allow(controller).to receive(:find_story).and_return(story)
      allow(story).to receive(:disownable_by_user?).with(user).and_return(true)
      allow(InactiveUser).to receive(:disown!).with(story)
      post :disown, params: { id: 's-11' }
      expect(response).to redirect_to('/stories/s-11-title')
    end
  end
end
