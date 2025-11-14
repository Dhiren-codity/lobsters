require 'rails_helper'

RSpec.describe StoriesController, type: :controller do
  let(:user) do
    instance_double(
      User,
      id: 1,
      is_moderator?: false,
      can_submit_stories?: true,
      wearable_hats: double(find_by: nil),
      notifications: double(read: double(of_comments: [])),
      mastodon_username: nil,
      mastodon_acct: nil,
      ids_replied_to: {}
    )
  end

  let(:moderator) do
    instance_double(
      User,
      id: 2,
      is_moderator?: true,
      can_submit_stories?: true,
      wearable_hats: double(find_by: nil),
      notifications: double(read: double(of_comments: [])),
      mastodon_username: nil,
      mastodon_acct: nil
    )
  end

  let(:merged_scope) do
    ds = double('merged_scope')
    allow(ds).to receive(:not_deleted).and_return(ds)
    allow(ds).to receive(:mod_single_preload?).and_return(ds)
    allow(ds).to receive(:for_presentation).and_return(ds)
    allow(ds).to receive(:includes).and_return(ds)
    allow(ds).to receive(:ids).and_return([2])
    allow(ds).to receive(:pluck).and_return([2])
    ds
  end

  let(:story_user) { double(id: 10, mastodon_username: nil, mastodon_acct: nil) }

  let(:story) do
    instance_double(
      Story,
      id: 123,
      short_id: 'abc123',
      title: 'Test Story',
      title_as_slug: 'test-story',
      merged_into_story: nil,
      header_anchor: 'h',
      is_gone?: false,
      can_be_seen_by_user?: true,
      user: story_user,
      comments_count: 0,
      merged_stories: merged_scope,
      is_editable_by_user?: true,
      is_undeletable_by_user?: true,
      url_is_editable_by_user?: true,
      tags: [],
      tags_was: [],
      valid?: true,
      already_posted_recently?: false,
      is_resubmit?: false,
      save: true,
      persisted?: true,
      as_json: { id: 123 },
      comments: double(new: nil),
      description: 'desc'
    )
  end

  let(:other_story) do
    instance_double(
      Story,
      id: 456,
      short_id: 'def456',
      title: 'Other',
      title_as_slug: 'other',
      merged_into_story: nil,
      header_anchor: 'x',
      user: story_user
    )
  end

  let(:valid_params) do
    {
      story: {
        title: 'Test Story',
        url: 'https://example.com',
        description: 'desc',
        tags: ['tech'],
        user_is_author: '0',
        user_is_following: '0'
      }
    }
  end

  before do
    allow(controller).to receive(:require_logged_in_user_or_400).and_return(true)
    allow(controller).to receive(:require_logged_in_user).and_return(true)
    allow(controller).to receive(:verify_user_can_submit_stories).and_return(true)
    allow(controller).to receive(:show_title_h1).and_return(true)
    controller.instance_variable_set(:@user, user)

    allow(Routes).to receive(:title_path).and_return("/stories/#{story.short_id}")
  end

  describe 'GET #new' do
    before do
      allow(Story).to receive(:new).and_return(story)
      allow(story).to receive(:fetching_ip=)
      allow(story).to receive(:url=)
      allow(story).to receive(:fetched_attributes).and_return({})
      allow(story).to receive(:already_posted_recently?).and_return(false)
      allow(story).to receive(:most_recent_similar).and_return(other_story)
      allow(story).to receive(:title=)
      allow(story).to receive(:title).and_return('Test Story')
    end

    it 'renders new successfully without url' do
      get :new
      expect(response).to be_successful
    end

    it 'canonicalizes URL and shows flash when fetched url differs' do
      allow(story).to receive(:fetched_attributes).and_return({ url: 'https://canonical.example.com',
                                                                title: 'Fetched Title' })

      get :new, params: { url: 'https://example.com', title: 'Fallback Title' }

      expect(flash.now[:notice]).to match(/URL has been changed/)
    end

    it 'redirects if already posted recently' do
      allow(story).to receive(:fetched_attributes).and_return({ url: 'https://example.com', title: 'Title' })
      allow(story).to receive(:already_posted_recently?).and_return(true)
      allow(Routes).to receive(:title_path).with(other_story).and_return("/stories/#{other_story.short_id}")

      get :new, params: { url: 'https://example.com' }

      expect(response).to redirect_to("/stories/#{other_story.short_id}")
      expect(flash[:success]).to match(/already been submitted recently/)
    end
  end

  describe 'POST #create' do
    let(:rr_scope) { double(first_or_create!: true) }

    before do
      allow(Story).to receive(:new).and_return(story)
      allow(story).to receive(:tags_was=)
      allow(story).to receive(:attributes=)
      allow(story).to receive(:url_is_editable_by_user?).with(user).and_return(true)
      allow(controller).to receive(:update_resubmit_comment_attributes).and_call_original
      allow(ReadRibbon).to receive(:where).and_return(rr_scope)
      allow(SendWebmentionJob).to receive_message_chain(:set, :perform_later)
      allow(story).to receive(:save).and_return(true)
      allow(story).to receive(:persisted?).and_return(true)
      allow(controller).to receive(:params).and_return(ActionController::Parameters.new(valid_params))
      allow(Tag).to receive(:where).and_return([])
    end

    it 'creates a story and redirects on success' do
      expect(ReadRibbon).to receive(:where).with(user: user, story: story).and_return(rr_scope)
      expect(rr_scope).to receive(:first_or_create!)
      expect(SendWebmentionJob).to receive_message_chain(:set, :perform_later).with(story)

      post :create, params: valid_params

      expect(response).to redirect_to("/stories/#{story.short_id}")
    end

    it 'renders new on validation failure' do
      allow(story).to receive(:valid?).and_return(false)
      allow(story).to receive(:persisted?).and_return(false)

      post :create, params: valid_params

      expect(response).to be_successful
    end

    it 'renders new when save fails' do
      allow(story).to receive(:save).and_return(false)
      allow(story).to receive(:persisted?).and_return(false)

      post :create, params: valid_params

      expect(response).to be_successful
    end

    it 'routes to preview when preview param present' do
      expect_any_instance_of(StoriesController).to receive(:preview).and_call_original

      post :create, params: valid_params.merge(preview: '1')

      expect(response).to be_successful
    end
  end

  describe 'DELETE #destroy' do
    before do
      controller.instance_variable_set(:@story, story)
      allow(controller).to receive(:find_user_story).and_return(true)
      allow(story).to receive(:is_editable_by_user?).with(user).and_return(true)
      allow(story).to receive(:editor=).with(user)
      allow(story).to receive(:is_deleted=).with(true)
      allow(story).to receive(:save).and_return(true)
      allow(Keystore).to receive(:increment_value_for)
      allow(Mastodon).to receive(:delete_post)
      allow(Tag).to receive(:where).and_return([])
    end

    it 'marks story deleted and redirects' do
      delete :destroy,
             params: { id: story.short_id,
                       story: { title: '', url: '', description: '', tags: [], user_is_author: '0',
                                user_is_following: '0' } }

      expect(response).to redirect_to("/stories/#{story.short_id}")
      expect(Keystore).to have_received(:increment_value_for).with("user:#{story_user.id}:stories_deleted")
      expect(Mastodon).to have_received(:delete_post).with(story)
    end

    it 'rejects unauthorized users' do
      allow(story).to receive(:is_editable_by_user?).with(user).and_return(false)
      allow(user).to receive(:is_moderator?).and_return(false)

      delete :destroy, params: { id: story.short_id }

      expect(response).to redirect_to('/')
      expect(flash[:error]).to eq('You cannot edit that story.')
    end
  end

  describe 'GET #edit' do
    before do
      controller.instance_variable_set(:@story, story)
      allow(controller).to receive(:find_user_story).and_return(true)
    end

    it 'renders edit for editable story' do
      allow(story).to receive(:is_editable_by_user?).with(user).and_return(true)

      get :edit, params: { id: story.short_id }

      expect(response).to be_successful
    end

    it 'redirects for non-editable story' do
      allow(story).to receive(:is_editable_by_user?).with(user).and_return(false)

      get :edit, params: { id: story.short_id }

      expect(response).to redirect_to('/')
      expect(flash[:error]).to eq('You cannot edit that story.')
    end
  end

  describe 'GET #fetch_url_attributes' do
    let(:new_story) { instance_double(Story, fetched_attributes: { title: 'Fetched', url: 'https://u' }) }

    it 'returns JSON attributes' do
      allow(Story).to receive(:new).and_return(new_story)
      allow(new_story).to receive(:fetching_ip=)
      allow(new_story).to receive(:url=)

      get :fetch_url_attributes, params: { fetch_url: 'https://u' }

      expect(response).to be_successful
      expect(JSON.parse(response.body)).to eq('title' => 'Fetched', 'url' => 'https://u')
    end
  end

  describe 'POST #preview' do
    before do
      allow(Story).to receive(:new).and_return(story)
      allow(story).to receive(:tags_was=)
      allow(story).to receive(:attributes=)
      allow(story).to receive(:url_is_editable_by_user?).and_return(true)
      allow(controller).to receive(:params).and_return(ActionController::Parameters.new(valid_params))
      allow(story).to receive(:is_resubmit?).and_return(false)
      allow(story).to receive(:user_id=).with(user.id)
      allow(story).to receive(:previewing=).with(true)
      allow(story).to receive(:current_vote=)
      allow(story).to receive(:score=)
      allow(story).to receive(:valid?).and_return(true)
      allow(Tag).to receive(:where).and_return([])
    end

    it 'renders new with preview story' do
      post :preview, params: valid_params

      expect(response).to be_successful
    end
  end

  describe 'GET #show' do
    let(:comments) { [instance_double(Comment, id: 5), instance_double(Comment, id: 6)] }
    let(:comments_scope) { double(for_presentation: comments, includes: comments) }
    let(:ribbon) { instance_double(ReadRibbon, bump: true) }
    let(:where_scope) do
      ds = double('where_scope')
      allow(ds).to receive(:mod_single_preload?).and_return(ds)
      allow(ds).to receive(:first!).and_return(story)
      ds
    end

    before do
      allow(Comment).to receive(:story_threads).with(story).and_return(comments_scope)
      allow(ReadRibbon).to receive(:where).and_return(double(first_or_initialize: ribbon))
      allow(Story).to receive(:where).and_return(where_scope)
      allow(controller).to receive(:load_user_votes)
    end

    it 'renders show for visible story' do
      get :show, params: { id: story.short_id }

      expect(response).to be_successful
    end

    it 'handles around_action track_story_reads with user' do
      controller.instance_variable_set(:@user, user)

      expect(ReadRibbon).to receive(:where).with(user: user,
                                                 story: story).and_return(double(first_or_initialize: ribbon))
      expect(ribbon).to receive(:bump)

      get :show, params: { id: story.short_id }

      expect(response).to be_successful
    end

    it 'redirects to merged story for HTML' do
      controller.instance_variable_set(:@user, nil)
      merged = other_story
      allow(story).to receive(:merged_into_story).and_return(merged)
      allow(Story).to receive(:where).and_return(double(first!: story))
      allow(Routes).to receive(:title_path).with(merged,
                                                 hash_including(anchor: story.header_anchor)).and_return("/stories/#{merged.short_id}")
      allow(story).to receive(:header_anchor).and_return('h')

      get :show, params: { id: story.short_id }

      expect(response).to redirect_to("/stories/#{merged.short_id}#h")
      expect(flash[:success]).to include("\"#{story.title}\" has been merged")
    end

    it 'redirects to merged story for JSON' do
      controller.instance_variable_set(:@user, nil)
      merged = other_story
      allow(story).to receive(:merged_into_story).and_return(merged)
      allow(Story).to receive(:where).and_return(double(first!: story))

      get :show, params: { id: story.short_id, format: :json }

      expect(response).to have_http_status(302)
    end

    it 'redirects when title slug mismatches' do
      controller.instance_variable_set(:@user, nil)
      allow(Story).to receive(:where).and_return(double(first!: story))
      get :show, params: { id: story.short_id, title: 'wrong-title' }
      expect(response).to redirect_to("/stories/#{story.short_id}")
    end

    it 'renders 404 for gone and not visible (HTML)' do
      controller.instance_variable_set(:@user, nil)
      allow(story).to receive(:is_gone?).and_return(true)
      allow(story).to receive(:can_be_seen_by_user?).with(nil).and_return(false)
      allow(Moderation).to receive_message_chain(:where, :where, :order, :first).and_return(nil)
      allow(Story).to receive(:where).and_return(double(first!: story))

      get :show, params: { id: story.short_id }

      expect(response).to have_http_status(404)
    end

    it 'raises not found for JSON when not visible' do
      controller.instance_variable_set(:@user, nil)
      allow(story).to receive(:is_gone?).and_return(false)
      allow(story).to receive(:can_be_seen_by_user?).with(nil).and_return(false)
      allow(Story).to receive(:where).and_return(double(first!: story))

      expect do
        get :show, params: { id: story.short_id, format: :json }
      end.to raise_error(ActiveRecord::RecordNotFound)
    end
  end

  describe 'POST #undelete' do
    before do
      controller.instance_variable_set(:@story, story)
      allow(controller).to receive(:find_user_story).and_return(true)
      allow(story).to receive(:is_editable_by_user?).with(user).and_return(true)
      allow(story).to receive(:is_undeletable_by_user?).with(user).and_return(true)
      allow(story).to receive(:editor=).with(user)
      allow(story).to receive(:is_deleted=).with(false)
      allow(story).to receive(:save).and_return(true)
      allow(Keystore).to receive(:increment_value_for)
      allow(Tag).to receive(:where).and_return([])
    end

    it 'undeletes and redirects' do
      post :undelete,
           params: { id: story.short_id,
                     story: { title: '', url: '', description: '', tags: [], user_is_author: '0',
                              user_is_following: '0' } }
      expect(response).to redirect_to("/stories/#{story.short_id}")
      expect(Keystore).to have_received(:increment_value_for).with("user:#{story_user.id}:stories_deleted", -1)
    end

    it 'denies undelete when not allowed' do
      allow(story).to receive(:is_editable_by_user?).with(user).and_return(false)

      post :undelete, params: { id: story.short_id }

      expect(response).to redirect_to('/')
      expect(flash[:error]).to eq('You cannot edit that story.')
    end
  end

  describe 'PATCH #update' do
    before do
      controller.instance_variable_set(:@story, story)
      allow(controller).to receive(:find_user_story).and_return(true)
      allow(story).to receive(:is_editable_by_user?).with(user).and_return(true)
      allow(story).to receive(:last_edited_at=)
      allow(story).to receive(:is_deleted=).with(false)
      allow(story).to receive(:editor=).with(user)
      allow(story).to receive(:tags_was=)
      allow(story).to receive(:attributes=)
      allow(story).to receive(:url_is_editable_by_user?).and_return(true)
      allow(Tag).to receive(:where).and_return([])
    end

    it 'updates and redirects on success' do
      allow(story).to receive(:save).and_return(true)

      patch :update, params: valid_params.merge(id: story.short_id)

      expect(response).to redirect_to("/stories/#{story.short_id}")
    end

    it 'renders edit on failure' do
      allow(story).to receive(:save).and_return(false)

      patch :update, params: valid_params.merge(id: story.short_id)

      expect(response).to be_successful
    end

    it 'denies update when not editable' do
      allow(story).to receive(:is_editable_by_user?).with(user).and_return(false)

      patch :update, params: valid_params.merge(id: story.short_id)

      expect(response).to redirect_to('/')
      expect(flash[:error]).to eq('You cannot edit that story.')
    end
  end

  describe 'DELETE #unvote' do
    it 'returns 400 when story not found' do
      allow(controller).to receive(:find_story).and_return(nil)

      delete :unvote, params: { id: 'missing' }

      expect(response.status).to eq(400)
    end

    it 'removes vote and returns ok' do
      allow(controller).to receive(:find_story).and_return(story)
      allow(story).to receive(:is_gone?).and_return(false)
      expect(Vote).to receive(:vote_thusly_on_story_or_comment_for_user_because).with(0, story.id, nil, user.id, nil)

      delete :unvote, params: { id: story.short_id }

      expect(response.body).to eq('ok')
    end
  end

  describe 'POST #upvote' do
    it 'returns 400 when story not found' do
      allow(controller).to receive(:find_story).and_return(nil)

      post :upvote, params: { id: 'missing' }

      expect(response.status).to eq(400)
    end

    it 'returns 400 when story is merged' do
      allow(controller).to receive(:find_story).and_return(story)
      allow(story).to receive(:is_gone?).and_return(false)
      allow(story).to receive(:merged_into_story).and_return(other_story)

      post :upvote, params: { id: story.short_id }

      expect(response.status).to eq(400)
      expect(response.body).to include('story has been merged')
    end

    it 'upvotes and returns ok' do
      allow(controller).to receive(:find_story).and_return(story)
      allow(story).to receive(:is_gone?).and_return(false)
      allow(story).to receive(:merged_into_story).and_return(nil)
      expect(Vote).to receive(:vote_thusly_on_story_or_comment_for_user_because).with(1, story.id, nil, user.id, nil)

      post :upvote, params: { id: story.short_id }

      expect(response.body).to eq('ok')
    end
  end

  describe 'POST #flag' do
    before do
      stub_const('Vote::STORY_REASONS', { 'spam' => 'spam' })
    end

    it 'returns 400 when story not found' do
      allow(controller).to receive(:find_story).and_return(nil)

      post :flag, params: { id: 'missing', reason: 'spam' }

      expect(response.status).to eq(400)
    end

    it 'returns 400 for invalid reason' do
      allow(controller).to receive(:find_story).and_return(story)
      allow(story).to receive(:is_gone?).and_return(false)

      post :flag, params: { id: story.short_id, reason: 'bad' }

      expect(response.status).to eq(400)
      expect(response.body).to include('invalid reason')
    end

    it 'returns 400 if user cannot flag' do
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
      expect(Vote).to receive(:vote_thusly_on_story_or_comment_for_user_because).with(-1, story.id, nil, user.id,
                                                                                      'spam')

      post :flag, params: { id: story.short_id, reason: 'spam' }

      expect(response.body).to eq('ok')
    end
  end

  describe 'POST #hide' do
    before do
      allow(controller).to receive(:find_story).and_return(story)
      allow(story).to receive(:merged_into_story).and_return(nil)
    end

    it 'returns 400 when story not found' do
      allow(controller).to receive(:find_story).and_return(nil)

      post :hide, params: { id: 'missing' }

      expect(response.status).to eq(400)
    end

    it 'returns 400 when story is merged' do
      allow(story).to receive(:merged_into_story).and_return(other_story)

      post :hide, params: { id: story.short_id }

      expect(response.status).to eq(400)
      expect(response.body).to include('story has been merged')
    end

    it 'hides story for user and returns ok for xhr' do
      request.headers['HTTP_X_REQUESTED_WITH'] = 'XMLHttpRequest'
      expect(HiddenStory).to receive(:hide_story_for_user).with(story, user)

      post :hide, params: { id: story.short_id }

      expect(response.body).to eq('ok')
    end

    it 'hides story and redirects for html' do
      expect(HiddenStory).to receive(:hide_story_for_user).with(story, user)
      allow(controller).to receive(:story_path).with(story).and_return("/stories/#{story.short_id}")

      post :hide, params: { id: story.short_id }

      expect(response).to redirect_to("/stories/#{story.short_id}")
    end
  end

  describe 'DELETE #unhide' do
    before do
      allow(controller).to receive(:find_story).and_return(story)
    end

    it 'returns 400 when story not found' do
      allow(controller).to receive(:find_story).and_return(nil)

      delete :unhide, params: { id: 'missing' }

      expect(response.status).to eq(400)
    end

    it 'unhides story and returns ok for xhr' do
      request.headers['HTTP_X_REQUESTED_WITH'] = 'XMLHttpRequest'
      expect(HiddenStory).to receive(:unhide_story_for_user).with(story, user)

      delete :unhide, params: { id: story.short_id }

      expect(response.body).to eq('ok')
    end

    it 'unhides story and redirects for html' do
      expect(HiddenStory).to receive(:unhide_story_for_user).with(story, user)
      allow(controller).to receive(:story_path).with(story).and_return("/stories/#{story.short_id}")

      delete :unhide, params: { id: story.short_id }

      expect(response).to redirect_to("/stories/#{story.short_id}")
    end
  end

  describe 'POST #save' do
    it 'returns 400 when story not found' do
      allow(controller).to receive(:find_story).and_return(nil)

      post :save, params: { id: 'missing' }

      expect(response.status).to eq(400)
    end

    it 'returns 400 when story is merged' do
      allow(controller).to receive(:find_story).and_return(story)
      allow(story).to receive(:merged_into_story).and_return(other_story)

      post :save, params: { id: story.short_id }

      expect(response.status).to eq(400)
      expect(response.body).to include('story has been merged')
    end

    it 'saves story for user' do
      allow(controller).to receive(:find_story).and_return(story)
      allow(story).to receive(:merged_into_story).and_return(nil)
      expect(SavedStory).to receive(:save_story_for_user).with(story.id, user.id)

      post :save, params: { id: story.short_id }

      expect(response.body).to eq('ok')
    end
  end

  describe 'DELETE #unsave' do
    it 'returns 400 when story not found' do
      allow(controller).to receive(:find_story).and_return(nil)

      delete :unsave, params: { id: 'missing' }

      expect(response.status).to eq(400)
    end

    it 'unsaves story for user' do
      allow(controller).to receive(:find_story).and_return(story)
      saved_scope = double
      expect(SavedStory).to receive(:where).with(user_id: user.id, story_id: story.id).and_return(saved_scope)
      expect(saved_scope).to receive(:delete_all)

      delete :unsave, params: { id: story.short_id }

      expect(response.body).to eq('ok')
    end
  end

  describe 'POST/GET #check_url_dupe' do
    before do
      allow(Story).to receive(:new).and_return(story)
      allow(controller).to receive(:update_story_attributes)
      allow(controller).to receive(:update_resubmit_comment_attributes)
      allow(story).to receive(:check_already_posted_recently?)
    end

    it 'raises ParameterMissing without url' do
      expect do
        post :check_url_dupe, params: { story: { title: 't' } }
      end.to raise_error(ActionController::ParameterMissing)
    end

    it 'renders HTML partial w/200' do
      allow(Link).to receive(:recently_linked_from_comments).and_return([])
      post :check_url_dupe, params: { story: { url: 'https://example.com' } }
      expect(response).to be_successful
    end

    it 'returns JSON with similar_stories' do
      allow(Link).to receive(:recently_linked_from_comments).and_return([])
      allow(story).to receive(:public_similar_stories).with(user).and_return([double(as_json: { id: 9 })])
      allow(story).to receive(:as_json).and_return({ id: 123 })

      get :check_url_dupe, params: { story: { url: 'https://example.com' }, format: :json }

      body = JSON.parse(response.body)
      expect(body['id']).to eq(123)
      expect(body['similar_stories']).to eq([{ 'id' => 9 }])
    end
  end

  describe 'POST #disown' do
    it 'returns 400 when not disownable' do
      allow(controller).to receive(:find_story).and_return(nil)

      post :disown, params: { id: 'missing' }

      expect(response.status).to eq(400)
    end

    it 'disowns and redirects' do
      allow(controller).to receive(:find_story).and_return(story)
      allow(story).to receive(:disownable_by_user?).with(user).and_return(true)
      expect(InactiveUser).to receive(:disown!).with(story)

      post :disown, params: { id: story.short_id }

      expect(response).to redirect_to("/stories/#{story.short_id}")
    end
  end

  describe 'authentication filters' do
    it 'returns 400 for actions requiring logged in user when unauthenticated' do
      controller.instance_variable_set(:@user, nil)
      allow(controller).to receive(:require_logged_in_user_or_400) do
        controller.render(plain: 'not logged in', status: 400) and return
      end

      post :upvote, params: { id: story.short_id }
      expect(response.status).to eq(400)
    end

    it 'redirects to root for actions requiring strict login when unauthenticated' do
      controller.instance_variable_set(:@user, nil)
      allow(controller).to receive(:require_logged_in_user) do
        controller.redirect_to('/') and return
      end

      get :new
      expect(response).to redirect_to('/')
    end
  end

  describe 'authorization for find_user_story' do
    it 'redirects when story not found or unauthorized' do
      allow(controller).to receive(:find_user_story) do
        controller.flash[:error] = 'Could not find story or you are not authorized to manage it.'
        controller.redirect_to('/') and false
      end

      get :edit, params: { id: 'missing' }

      expect(response).to redirect_to('/')
      expect(flash[:error]).to match(/not authorized/)
    end
  end
end
