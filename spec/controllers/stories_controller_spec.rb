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
    stub_const('Routes', Class.new)
    allow(Routes).to receive(:title_path) do |s, opts = {}|
      base = "/stories/#{s.respond_to?(:short_id) ? s.short_id : 'unknown'}"
      if opts && opts[:anchor]
        "#{base}##{opts[:anchor]}"
      else
        base
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

      it 'renders new' do
        post :create, params: { story: { title: '', url: 'http://example.com' } }
        expect(response).to render_template('new')
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

      get :new, params: { url: 'http://example.com', title: 'User Title' }
      expect(flash.now[:notice]).to match(/URL has been changed to fetched/)
      expect(response).to be_successful
    end

    it 'redirects when URL already posted recently' do
      prev = instance_double(Story, short_id: 'prev123')
      allow(story).to receive(:url=)
      allow(story).to receive(:fetched_attributes).and_return({ url: 'http://example.com', title: 'T' })
      allow(story).to receive(:already_posted_recently?).and_return(true)
      allow(story).to receive(:most_recent_similar).and_return(prev)

      get :new, params: { url: 'http://example.com' }
      expect(flash[:success]).to eq('This URL has already been submitted recently.')
      expect(response).to redirect_to("/stories/#{prev.short_id}")
    end
  end

  describe 'GET preview' do
    before do
      s = story
      allow(Story).to receive(:new).and_return(s)
      allow(s).to receive(:tags).and_return([])
      allow(s).to receive(:tags_was=)
      allow(s).to receive(:url_is_editable_by_user?).with(user).and_return(true)
      allow(s).to receive(:attributes=)
      allow(s).to receive(:is_resubmit?).and_return(false)
      allow(s).to receive(:user_id=).with(user.id)
      allow(s).to receive(:previewing=).with(true)
      allow(s).to receive(:current_vote=)
      allow(s).to receive(:score=).with(1)
      allow(s).to receive(:valid?).and_return(true)
      allow(Vote).to receive(:new).with(vote: 1).and_return(instance_double(Vote))
    end

    it 'renders new for preview' do
      allow(controller).to receive(:story_params).and_return({ title: 'T', url: 'http://example.com', description: 'D',
                                                               tags: [] })
      get :preview
      expect(response).to render_template('new')
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

    it 'redirects to merged JSON endpoint if merged' do
      merged = instance_double(Story, short_id: 'merged1')
      allow(story).to receive(:merged_into_story).and_return(merged)
      allow(controller).to receive(:story_path) do |st, options = {}|
        suffix = options[:format] == :json ? '.json' : ''
        "/stories/#{st.short_id}#{suffix}"
      end

      get :show, params: { id: story.short_id, format: :json }
      expect(response).to redirect_to("/stories/#{merged.short_id}.json")
    end
  end

  describe 'GET show bumps ribbon for logged-in user' do
    it 'bumps ReadRibbon via around_action' do
      relation = instance_double(ActiveRecord::Relation)
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

      ribbon_relation = instance_double(ActiveRecord::Relation,
                                        first_or_initialize: instance_double(ReadRibbon, bump: true))
      allow(ReadRibbon).to receive(:where).and_return(ribbon_relation)
      allow(Vote).to receive(:comment_votes_by_user_for_story_hash).and_return({})
      allow(Vote).to receive(:comment_vote_summaries).and_return({})
      allow(user).to receive(:ids_replied_to).and_return({})
      allow(Comment).to receive(:where).and_return(Comment)
      allow(Comment).to receive(:where).and_return([])

      controller.instance_variable_set(:@user, user)
      get :show, params: { id: story.short_id }
      expect(response).to be_successful
    end
  end

  describe 'POST undelete' do
    before do
      allow(controller).to receive(:find_user_story) do
        controller.instance_variable_set(:@story, story)
        true
      end
      allow(story).to receive(:editor=)
      allow(story).to receive(:is_deleted=)
      allow(Keystore).to receive(:increment_value_for)
    end

    it 'rejects when not editable or not undeletable' do
      allow(story).to receive(:is_editable_by_user?).with(user).and_return(false)
      allow(story).to receive(:is_undeletable_by_user?).with(user).and_return(false)
      post :undelete, params: { id: story.short_id }
      expect(flash[:error]).to eq('You cannot edit that story.')
      expect(response).to redirect_to('/')
    end

    it 'undeletes and redirects when permitted' do
      allow(story).to receive(:is_editable_by_user?).with(user).and_return(true)
      allow(story).to receive(:is_undeletable_by_user?).with(user).and_return(true)
      allow(story).to receive(:save).and_return(true)

      post :undelete, params: { id: story.short_id }
      expect(Keystore).to have_received(:increment_value_for).with("user:#{story.user.id}:stories_deleted", -1)
      expect(response).to redirect_to("/stories/#{story.short_id}")
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

    it 'updates and redirects on success' do
      allow(story).to receive(:is_editable_by_user?).with(user).and_return(true)
      allow(story).to receive(:save).and_return(true)
      patch :update, params: { id: story.short_id, story: { title: 'New' } }
      expect(response).to redirect_to("/stories/#{story.short_id}")
    end

    it 'renders edit on failure' do
      allow(story).to receive(:is_editable_by_user?).with(user).and_return(true)
      allow(story).to receive(:save).and_return(false)
      patch :update, params: { id: story.short_id, story: { title: 'New' } }
      expect(response).to render_template('edit')
    end
  end

  describe 'DELETE unvote' do
    context 'when story not found or gone' do
      it 'returns 400' do
        allow(controller).to receive(:find_story).and_return(nil)
        delete :unvote, params: { id: 'missing' }
        expect(response.status).to eq(400)
        expect(response.body).to include("can't find story")
      end
    end

    it 'unvotes and returns ok' do
      allow(controller).to receive(:find_story).and_return(story)
      allow(story).to receive(:is_gone?).and_return(false)
      allow(Vote).to receive(:vote_thusly_on_story_or_comment_for_user_because)
      delete :unvote, params: { id: story.short_id }
      expect(Vote).to have_received(:vote_thusly_on_story_or_comment_for_user_because).with(0, story.id, nil, user.id,
                                                                                            nil)
      expect(response.body).to eq('ok')
    end
  end

  describe 'POST upvote' do
    it 'returns 400 when story missing or gone' do
      allow(controller).to receive(:find_story).and_return(nil)
      post :upvote, params: { id: 'missing' }
      expect(response.status).to eq(400)
      expect(response.body).to include("can't find story")
    end

    it 'returns 400 when story merged' do
      allow(controller).to receive(:find_story).and_return(story)
      allow(story).to receive(:is_gone?).and_return(false)
      allow(story).to receive(:merged_into_story).and_return(instance_double(Story))
      post :upvote, params: { id: story.short_id }
      expect(response.status).to eq(400)
      expect(response.body).to include('story has been merged')
    end

    it 'upvotes and returns ok' do
      allow(controller).to receive(:find_story).and_return(story)
      allow(story).to receive(:is_gone?).and_return(false)
      allow(story).to receive(:merged_into_story).and_return(nil)
      allow(Vote).to receive(:vote_thusly_on_story_or_comment_for_user_because)
      post :upvote, params: { id: story.short_id }
      expect(Vote).to have_received(:vote_thusly_on_story_or_comment_for_user_because).with(1, story.id, nil, user.id,
                                                                                            nil)
      expect(response.body).to eq('ok')
    end
  end

  describe 'POST flag' do
    before do
      stub_const('Vote::STORY_REASONS', { 'spam' => 'Spam' })
    end

    it 'returns 400 when story missing' do
      allow(controller).to receive(:find_story).and_return(nil)
      post :flag, params: { id: 'missing', reason: 'spam' }
      expect(response.status).to eq(400)
    end

    it 'returns 400 for invalid reason' do
      allow(controller).to receive(:find_story).and_return(story)
      allow(story).to receive(:is_gone?).and_return(false)
      post :flag, params: { id: story.short_id, reason: 'nope' }
      expect(response.status).to eq(400)
      expect(response.body).to include('invalid reason')
    end

    it 'returns 400 when user cannot flag' do
      allow(controller).to receive(:find_story).and_return(story)
      allow(story).to receive(:is_gone?).and_return(false)
      allow(user).to receive(:can_flag?).with(story).and_return(false)
      post :flag, params: { id: story.short_id, reason: 'spam' }
      expect(response.status).to eq(400)
      expect(response.body).to include('not permitted to flag')
    end

    it 'flags and returns ok' do
      allow(controller).to receive(:find_story).and_return(story)
      allow(story).to receive(:is_gone?).and_return(false)
      allow(user).to receive(:can_flag?).with(story).and_return(true)
      allow(Vote).to receive(:vote_thusly_on_story_or_comment_for_user_because)
      post :flag, params: { id: story.short_id, reason: 'spam' }
      expect(Vote).to have_received(:vote_thusly_on_story_or_comment_for_user_because).with(-1, story.id, nil, user.id,
                                                                                            'spam')
      expect(response.body).to eq('ok')
    end
  end

  describe 'POST hide' do
    before do
      allow(controller).to receive(:story_path) do |s, _opts = {}|
        "/stories/#{s.short_id}"
      end
    end

    it 'returns 400 when missing' do
      allow(controller).to receive(:find_story).and_return(nil)
      post :hide, params: { id: 'missing' }
      expect(response.status).to eq(400)
    end

    it 'returns 400 when merged' do
      allow(controller).to receive(:find_story).and_return(story)
      allow(story).to receive(:merged_into_story).and_return(instance_double(Story))
      post :hide, params: { id: story.short_id }
      expect(response.status).to eq(400)
      expect(response.body).to include('story has been merged')
    end

    it 'hides via XHR and returns ok' do
      allow(controller).to receive(:find_story).and_return(story)
      allow(story).to receive(:merged_into_story).and_return(nil)
      allow(HiddenStory).to receive(:hide_story_for_user)
      request.env['HTTP_X_REQUESTED_WITH'] = 'XMLHttpRequest'
      post :hide, params: { id: story.short_id }
      expect(HiddenStory).to have_received(:hide_story_for_user).with(story, user)
      expect(response.body).to eq('ok')
    end

    it 'hides and redirects for non-XHR' do
      allow(controller).to receive(:find_story).and_return(story)
      allow(story).to receive(:merged_into_story).and_return(nil)
      allow(HiddenStory).to receive(:hide_story_for_user)
      post :hide, params: { id: story.short_id }
      expect(response).to redirect_to("/stories/#{story.short_id}")
    end
  end

  describe 'DELETE unhide' do
    before do
      allow(controller).to receive(:story_path) do |s, _opts = {}|
        "/stories/#{s.short_id}"
      end
    end

    it 'returns 400 when missing' do
      allow(controller).to receive(:find_story).and_return(nil)
      delete :unhide, params: { id: 'missing' }
      expect(response.status).to eq(400)
    end

    it 'unhides via XHR and returns ok' do
      allow(controller).to receive(:find_story).and_return(story)
      allow(HiddenStory).to receive(:unhide_story_for_user)
      request.env['HTTP_X_REQUESTED_WITH'] = 'XMLHttpRequest'
      delete :unhide, params: { id: story.short_id }
      expect(HiddenStory).to have_received(:unhide_story_for_user).with(story, user)
      expect(response.body).to eq('ok')
    end

    it 'unhides and redirects for non-XHR' do
      allow(controller).to receive(:find_story).and_return(story)
      allow(HiddenStory).to receive(:unhide_story_for_user)
      delete :unhide, params: { id: story.short_id }
      expect(response).to redirect_to("/stories/#{story.short_id}")
    end
  end

  describe 'POST save' do
    it 'returns 400 when missing' do
      allow(controller).to receive(:find_story).and_return(nil)
      post :save, params: { id: 'missing' }
      expect(response.status).to eq(400)
    end

    it 'returns 400 when merged' do
      allow(controller).to receive(:find_story).and_return(story)
      allow(story).to receive(:merged_into_story).and_return(instance_double(Story))
      post :save, params: { id: story.short_id }
      expect(response.status).to eq(400)
      expect(response.body).to include('story has been merged')
    end

    it 'saves and returns ok' do
      allow(controller).to receive(:find_story).and_return(story)
      allow(story).to receive(:merged_into_story).and_return(nil)
      allow(SavedStory).to receive(:save_story_for_user)
      post :save, params: { id: story.short_id }
      expect(SavedStory).to have_received(:save_story_for_user).with(story.id, user.id)
      expect(response.body).to eq('ok')
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

  describe 'GET check_url_dupe (JSON)' do
    before do
      s = story
      allow(Story).to receive(:new).and_return(s)
      allow(s).to receive(:tags).and_return([])
      allow(s).to receive(:tags_was=)
      allow(s).to receive(:url_is_editable_by_user?).with(user).and_return(true)
      allow(s).to receive(:attributes=)
      allow(s).to receive(:is_resubmit?).and_return(false)
      allow(s).to receive(:check_already_posted_recently?).and_return(true)
      allow(controller).to receive(:story_params).and_return({ url: 'http://example.com', title: 'T', description: 'D',
                                                               tags: [] })
      allow(Link).to receive(:recently_linked_from_comments).and_return([])
    end

    it 'requires URL parameter' do
      expect do
        get :check_url_dupe, params: { story: { url: '' } }, format: :json
      end.to raise_error(ActionController::ParameterMissing)
    end

    it 'renders JSON with similar stories' do
      allow(story).to receive(:url).and_return('http://example.com')
      allow(story).to receive(:public_similar_stories).with(user).and_return([instance_double(Story,
                                                                                              as_json: { id: 's1' })])
      allow(story).to receive(:as_json).and_return({ id: 'abc123' })

      get :check_url_dupe, params: { story: { url: 'http://example.com' } }, format: :json
      body = JSON.parse(response.body)
      expect(body['id']).to eq('abc123')
      expect(body['similar_stories']).to eq([{ 'id' => 's1' }])
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
