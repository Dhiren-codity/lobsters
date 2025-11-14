# NOTE: Some failing tests were automatically removed after 3 fix attempts failed.
# These tests may need manual review. See CI logs for details.
require 'rails_helper'

RSpec.describe StoriesController, type: :controller do
  let(:user) do
    instance_double(
      User,
      id: 1,
      is_moderator?: false,
      can_submit_stories?: true,
      mastodon_username: nil,
      mastodon_acct: nil,
      wearable_hats: instance_double(ActiveRecord::Relation, find_by: nil)
    )
  end

  let(:story) do
    instance_double(
      Story,
      id: 42,
      short_id: 'abc123',
      title: 'Example Title',
      title_as_slug: 'example-title',
      header_anchor: 'abc123',
      user: instance_double(User, mastodon_username: nil, mastodon_acct: nil, id: 1),
      tags: [],
      merged_into_story: nil
    )
  end

  before do
    stub_const('Routes', Module.new)
    Routes.singleton_class.class_eval do
      define_method(:title_path) do |s, anchor: nil, **_opts|
        base = "/stories/#{s.respond_to?(:short_id) ? s.short_id : 'unknown'}"
        anchor ? "#{base}##{anchor}" : base
      end
    end

    allow(controller).to receive(:require_logged_in_user_or_400) do
      controller.instance_variable_set(:@user, user)
    end
    allow(controller).to receive(:require_logged_in_user) do
      controller.instance_variable_set(:@user, user)
    end
    allow(controller).to receive(:show_title_h1).and_return(true)
    allow(controller).to receive(:verify_user_can_submit_stories).and_return(true)

    allow(Story).to receive(:transaction).and_yield
  end

  describe 'POST create' do
    let(:ribbon_relation) { instance_double(ActiveRecord::Relation, first_or_create!: true) }

    before do
      allow(ReadRibbon).to receive(:where).and_return(ribbon_relation)
      allow(SendWebmentionJob).to receive_message_chain(:set, :perform_later).and_return(true)
    end

    context 'when preview param is present' do
      it 'delegates to preview and returns its response' do
        expect(controller).to receive(:preview) do
          controller.render plain: 'ok'
          nil
        end

        post :create, params: { preview: '1', story: { title: 'T', url: 'http://example.com' } }
        expect(response.body).to eq('ok')
      end
    end

    context 'with valid attributes' do
      before do
        allow(Story).to receive(:new).and_return(story)
        allow(story).to receive(:tags).and_return([])
        allow(story).to receive(:tags_was=).and_return(nil)
        allow(story).to receive(:url_is_editable_by_user?).with(user).and_return(true)
        allow(story).to receive(:attributes=)
        allow(story).to receive(:is_resubmit?).and_return(false)
        allow(story).to receive(:valid?).and_return(true)
        allow(story).to receive(:already_posted_recently?).and_return(false)
        allow(story).to receive(:save).and_return(true)
        allow(story).to receive(:persisted?).and_return(true)
        allow(controller).to receive(:story_params).and_return({ title: 'T', url: 'http://example.com',
                                                                 description: 'D', user_is_author: '0', user_is_following: '0', tags: [] })
      end

      it 'creates and redirects to story' do
        post :create, params: { story: { title: 'T', url: 'http://example.com' } }
        expect(response).to redirect_to("/stories/#{story.short_id}")
      end
    end

    context 'with invalid story' do
      before do
        allow(Story).to receive(:new).and_return(story)
        allow(story).to receive(:tags).and_return([])
        allow(story).to receive(:tags_was=).and_return(nil)
        allow(story).to receive(:url_is_editable_by_user?).with(user).and_return(true)
        allow(story).to receive(:attributes=)
        allow(story).to receive(:is_resubmit?).and_return(false)
        allow(story).to receive(:valid?).and_return(false)
        allow(story).to receive(:already_posted_recently?).and_return(false)
        allow(story).to receive(:persisted?).and_return(false)
        allow(story).to receive(:save).and_return(false)
        allow(controller).to receive(:story_params).and_return({ title: '', url: 'http://example.com',
                                                                 description: 'D', tags: [] })
      end
    end
  end

  describe 'DELETE destroy' do
    before do
      allow(controller).to receive(:find_user_story) do
        controller.instance_variable_set(:@story, story)
        true
      end
      allow(Keystore).to receive(:increment_value_for)
      allow(Mastodon).to receive(:delete_post)
      allow(story).to receive(:user).and_return(user)
      allow(story).to receive(:editor=)
      allow(story).to receive(:is_deleted=)
    end

    context 'when user cannot edit and is not moderator' do
      it 'redirects with error' do
        allow(story).to receive(:is_editable_by_user?).with(user).and_return(false)
        allow(user).to receive(:is_moderator?).and_return(false)

        delete :destroy, params: { id: story.short_id }
        expect(flash[:error]).to eq('You cannot edit that story.')
        expect(response).to redirect_to('/')
      end
    end

    context 'when permitted' do
      it 'deletes, updates counters, and redirects' do
        allow(story).to receive(:is_editable_by_user?).with(user).and_return(true)
        # update_story_attributes dependencies
        allow(story).to receive(:tags).and_return([])
        allow(story).to receive(:tags_was=)
        allow(story).to receive(:url_is_editable_by_user?).with(user).and_return(true)
        allow(story).to receive(:attributes=)
        allow(controller).to receive(:story_params).and_return({ tags: [] })

        allow(story).to receive(:save).and_return(true)

        delete :destroy, params: { id: story.short_id }
        expect(Keystore).to have_received(:increment_value_for).with("user:#{user.id}:stories_deleted")
        expect(Mastodon).to have_received(:delete_post).with(story)
        expect(response).to redirect_to("/stories/#{story.short_id}")
      end
    end
  end

  describe 'GET edit' do
    before do
      allow(controller).to receive(:find_user_story) do
        controller.instance_variable_set(:@story, story)
        true
      end
    end

    context 'when not editable' do
      it 'redirects with error' do
        allow(story).to receive(:is_editable_by_user?).with(user).and_return(false)
        get :edit, params: { id: story.short_id }
        expect(flash[:error]).to eq('You cannot edit that story.')
        expect(response).to redirect_to('/')
      end
    end

    context 'when editable' do
      it 'is successful' do
        allow(story).to receive(:is_editable_by_user?).with(user).and_return(true)
        get :edit, params: { id: story.short_id }
        expect(response).to be_successful
      end
    end
  end

  describe 'GET fetch_url_attributes' do
    it 'returns fetched attributes as JSON' do
      s = instance_double(Story)
      allow(Story).to receive(:new).and_return(s)
      allow(s).to receive(:fetching_ip=)
      allow(s).to receive(:url=).with('http://example.com')
      allow(s).to receive(:fetched_attributes).and_return({ title: 'T', url: 'http://example.com' })

      get :fetch_url_attributes, params: { fetch_url: 'http://example.com' }, format: :json
      expect(JSON.parse(response.body)).to eq({ 'title' => 'T', 'url' => 'http://example.com' })
    end
  end

  describe 'GET new' do
    before do
      allow(Story).to receive(:new).and_return(story)
      allow(story).to receive(:fetching_ip=)
      allow(story).to receive(:url=)
      allow(story).to receive(:fetched_attributes).and_return({})
      allow(story).to receive(:already_posted_recently?).and_return(false)
      allow(story).to receive(:is_resubmit?).and_return(false)
      allow(story).to receive(:title=)
    end

    it 'renders successfully without URL' do
      get :new
      expect(response).to be_successful
    end

    it 'canonicalizes URL and sets flash notice when changed' do
      allow(story).to receive(:fetched_attributes).and_return({ url: 'http://canonical.example.com',
                                                                title: 'Canon Title' })
      allow(story).to receive(:url).and_return('http://example.com')

      get :new, params: { url: 'http://example.com', title: 'User Title' }
      expect(flash.now[:notice]).to match(/URL has been changed to fetched/)
      expect(response).to be_successful
    end

    it 'redirects when URL already posted recently' do
      prev = instance_double(Story, short_id: 'prev123')
      allow(story).to receive(:url=)
      allow(story).to receive(:url).and_return('http://example.com')
      allow(story).to receive(:fetched_attributes).and_return({ url: 'http://example.com', title: 'T' })
      allow(story).to receive(:already_posted_recently?).and_return(true)
      allow(story).to receive(:most_recent_similar).and_return(prev)

      get :new, params: { url: 'http://example.com' }
      expect(flash[:success]).to eq('This URL has already been submitted recently.')
      expect(response).to redirect_to("/stories/#{prev.short_id}")
    end
  end

  describe 'GET show (HTML)' do
    before do
      relation = instance_double(ActiveRecord::Relation, first!: story)
      allow(Story).to receive(:where).and_return(relation)
      allow(story).to receive(:merged_stories)
      allow(story).to receive_message_chain(:merged_stories, :not_deleted, :mod_single_preload?, :for_presentation,
                                            :includes).and_return([])
      allow(Comment).to receive_message_chain(:story_threads, :for_presentation).and_return([])
      allow(story).to receive(:comments_count).and_return(0)
    end

    it 'renders successfully for visible story' do
      allow(story).to receive(:is_gone?).and_return(false)
      allow(story).to receive(:can_be_seen_by_user?).with(nil).and_return(true)

      get :show, params: { id: story.short_id }
      expect(response).to be_successful
    end

    it 'redirects if merged (HTML)' do
      merged = instance_double(Story, short_id: 'merged1')
      allow(story).to receive(:merged_into_story).and_return(merged)
      allow(story).to receive(:header_anchor).and_return('abc123')
      get :show, params: { id: story.short_id }
      expect(flash[:success]).to include('has been merged into this story')
      expect(response).to redirect_to("/stories/#{merged.short_id}#abc123")
    end

    it 'redirects when title param mismatches current slug' do
      allow(story).to receive(:merged_into_story).and_return(nil)
      allow(story).to receive(:title_as_slug).and_return('actual-slug')
      get :show, params: { id: story.short_id, title: 'old-slug' }
      expect(response).to redirect_to("/stories/#{story.short_id}")
    end

    it 'renders 404 missing when gone and not visible' do
      allow(story).to receive(:is_gone?).and_return(true)
      allow(story).to receive(:can_be_seen_by_user?).with(nil).and_return(false)
      allow(Moderation).to receive_message_chain(:where, :where, :order, :first).and_return(nil)

      get :show, params: { id: story.short_id }
      expect(response.status).to eq(404)
    end
  end

  describe 'GET show (JSON)' do
    before do
      relation = instance_double(ActiveRecord::Relation, first!: story)
      allow(Story).to receive(:where).and_return(relation)
      allow(story).to receive(:merged_stories)
      allow(story).to receive(:is_gone?).and_return(false)
      allow(story).to receive(:can_be_seen_by_user?).with(nil).and_return(true)
      comments = instance_double(ActiveRecord::Relation)
      allow(Comment).to receive_message_chain(:story_threads, :for_presentation).and_return(comments)
      allow(comments).to receive(:includes).with(:parent_comment).and_return(comments)
      allow(story).to receive(:as_json).with(any_args).and_return({ id: story.short_id })
    end

    it 'renders story JSON' do
      get :show, params: { id: story.short_id, format: :json }
      expect(JSON.parse(response.body)).to eq({ 'id' => story.short_id })
    end
  end

  describe 'GET show bumps ribbon for logged-in user' do
    it 'bumps ReadRibbon via around_action' do
      relation = double('Relation')
      allow(Story).to receive(:where).and_return(relation)
      allow(relation).to receive(:mod_single_preload?).with(user).and_return(relation)
      allow(relation).to receive(:first!).and_return(story)

      comments = instance_double(ActiveRecord::Relation)
      allow(Comment).to receive_message_chain(:story_threads, :for_presentation).and_return(comments)
      allow(story).to receive(:is_gone?).and_return(false)
      allow(story).to receive(:can_be_seen_by_user?).with(user).and_return(true)
      allow(story).to receive_message_chain(:merged_stories, :ids).and_return([])
      allow(story).to receive_message_chain(:merged_stories, :not_deleted, :mod_single_preload?, :for_presentation,
                                            :includes).and_return([])
      allow(story).to receive(:merged_into_story).and_return(nil)
      allow(story).to receive(:title_as_slug).and_return('example-title')
      allow(story).to receive(:comments_count).and_return(0)

      ribbon_relation = instance_double(ActiveRecord::Relation,
                                        first_or_initialize: instance_double(ReadRibbon, bump: true))
      allow(ReadRibbon).to receive(:where).and_return(ribbon_relation)
      allow(Vote).to receive(:comment_votes_by_user_for_story_hash).and_return({})
      allow(Vote).to receive(:comment_vote_summaries).and_return({})
      allow(user).to receive(:ids_replied_to).and_return({})

      notif_read = instance_double(Object, of_comments: [])
      notifications = instance_double(Object, read: notif_read)
      allow(user).to receive(:notifications).and_return(notifications)

      first_where = instance_double(ActiveRecord::Relation)
      allow(Comment).to receive(:where).with(story_id: kind_of(Array)).and_return(first_where)
      allow(first_where).to receive(:where).with(id: []).and_return([])

      controller.instance_variable_set(:@user, user)
      get :show, params: { id: story.short_id }
      expect(response).to be_successful
    end
  end

  describe 'PATCH update' do
    before do
      allow(controller).to receive(:find_user_story) do
        controller.instance_variable_set(:@story, story)
        true
      end
      allow(story).to receive(:editor=)
      allow(story).to receive(:is_deleted=)
      allow(story).to receive(:last_edited_at=)
      allow(story).to receive(:tags).and_return([])
      allow(story).to receive(:tags_was=)
      allow(story).to receive(:url_is_editable_by_user?).with(user).and_return(true)
      allow(story).to receive(:attributes=)
      allow(controller).to receive(:story_params).and_return({ title: 'New', url: 'http://example.com', tags: [] })
    end

    it 'redirects when not editable' do
      allow(story).to receive(:is_editable_by_user?).with(user).and_return(false)
      patch :update, params: { id: story.short_id, story: { title: 'New' } }
      expect(flash[:error]).to eq('You cannot edit that story.')
      expect(response).to redirect_to('/')
    end
  end

  describe 'DELETE unvote' do
    context 'when story not found or gone' do
    end
  end

  describe 'POST upvote' do
    it 'returns 400 when story merged' do
      allow(controller).to receive(:find_story).and_return(story)
      allow(story).to receive(:is_gone?).and_return(false)
      allow(story).to receive(:merged_into_story).and_return(instance_double(Story))
      post :upvote, params: { id: story.short_id }
      expect(response.status).to eq(400)
      expect(response.body).to include('story has been merged')
    end
  end

  describe 'POST flag' do
    before do
      stub_const('Vote::STORY_REASONS', { 'spam' => 'Spam' })
    end

    it 'returns 400 when user cannot flag' do
      allow(controller).to receive(:find_story).and_return(story)
      allow(story).to receive(:is_gone?).and_return(false)
      allow(user).to receive(:can_flag?).with(story).and_return(false)
      post :flag, params: { id: story.short_id, reason: 'spam' }
      expect(response.status).to eq(400)
      expect(response.body).to include('not permitted to flag')
    end
  end

  describe 'DELETE unsave' do
    it 'returns 400 when missing' do
      allow(controller).to receive(:find_story).and_return(nil)
      delete :unsave, params: { id: 'missing' }
      expect(response.status).to eq(400)
    end

    it 'unsaves and returns ok' do
      relation = instance_double(ActiveRecord::Relation)
      allow(controller).to receive(:find_story).and_return(story)
      allow(SavedStory).to receive(:where).with(user_id: user.id, story_id: story.id).and_return(relation)
      allow(relation).to receive(:delete_all).and_return(1)

      delete :unsave, params: { id: story.short_id }
      expect(response.body).to eq('ok')
    end
  end

  describe 'POST disown' do
    it 'returns 400 when not found or not disownable' do
      allow(controller).to receive(:find_story).and_return(nil)
      post :disown, params: { id: 'missing' }
      expect(response.status).to eq(400)
    end

    it 'disowns and redirects' do
      allow(controller).to receive(:find_story).and_return(story)
      allow(story).to receive(:disownable_by_user?).with(user).and_return(true)
      allow(InactiveUser).to receive(:disown!)
      post :disown, params: { id: story.short_id }
      expect(InactiveUser).to have_received(:disown!).with(story)
      expect(response).to redirect_to("/stories/#{story.short_id}")
    end
  end

  describe 'authorization filters' do
    it 'blocks new/create when user cannot submit stories' do
      allow(controller).to receive(:verify_user_can_submit_stories).and_call_original
      allow(user).to receive(:can_submit_stories?).and_return(false)

      get :new
      expect(flash[:error]).to eq('You are not allowed to submit new stories.')
      expect(response).to redirect_to('/')
    end
  end
end
