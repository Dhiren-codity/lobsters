require 'rails_helper'

RSpec.describe StoriesController do
  let(:user) { create(:user) }
  let(:story) { create(:story, user: user) }
  let(:moderator) { create(:user, :moderator) }

  before do
    allow(controller).to receive(:require_logged_in_user_or_400)
    allow(controller).to receive(:require_logged_in_user)
    allow(controller).to receive(:verify_user_can_submit_stories)
    allow(controller).to receive(:find_user_story).and_return(true)
    allow(controller).to receive(:track_story_reads).and_yield
    allow(controller).to receive(:show_title_h1)
    allow(controller).to receive(:find_story).and_return(story)
  end

  describe '#create' do
    context 'when preview is true' do
      it 'calls the preview method' do
        allow(controller).to receive(:params).and_return(preview: true)
        expect(controller).to receive(:preview)
        controller.create
      end
    end

    context 'when story is valid and not already posted recently' do
      it 'saves the story and redirects to the story path' do
        allow(controller).to receive(:params).and_return(preview: false)
        allow_any_instance_of(Story).to receive(:valid?).and_return(true)
        allow_any_instance_of(Story).to receive(:already_posted_recently?).and_return(false)
        allow_any_instance_of(Story).to receive(:is_resubmit?).and_return(false)

        expect_any_instance_of(Story).to receive(:save).and_return(true)
        expect(controller).to receive(:redirect_to).with(Routes.title_path(story))

        controller.create
      end
    end

    context 'when story is invalid' do
      it 'renders the new action' do
        allow(controller).to receive(:params).and_return(preview: false)
        allow_any_instance_of(Story).to receive(:valid?).and_return(false)

        expect(controller).to receive(:render).with(action: "new")

        controller.create
      end
    end
  end

  describe '#destroy' do
    context 'when user cannot edit the story' do
      it 'redirects to root with an error message' do
        allow_any_instance_of(Story).to receive(:is_editable_by_user?).and_return(false)
        allow(user).to receive(:is_moderator?).and_return(false)

        expect(controller).to receive(:redirect_to).with("/")
        controller.destroy
      end
    end

    context 'when user can edit the story' do
      it 'marks the story as deleted and redirects to the story path' do
        allow_any_instance_of(Story).to receive(:is_editable_by_user?).and_return(true)

        expect_any_instance_of(Story).to receive(:save).and_return(true)
        expect(controller).to receive(:redirect_to).with(Routes.title_path(story))

        controller.destroy
      end
    end
  end

  describe '#edit' do
    context 'when user cannot edit the story' do
      it 'redirects to root with an error message' do
        allow_any_instance_of(Story).to receive(:is_editable_by_user?).and_return(false)

        expect(controller).to receive(:redirect_to).with("/")
        controller.edit
      end
    end

    context 'when user can edit the story' do
      it 'sets the title for editing' do
        allow_any_instance_of(Story).to receive(:is_editable_by_user?).and_return(true)

        controller.edit
        expect(assigns(:title)).to eq("Edit Story")
      end
    end
  end

  describe '#fetch_url_attributes' do
    it 'renders the fetched attributes as JSON' do
      allow(controller).to receive(:params).and_return(fetch_url: 'http://example.com')
      allow_any_instance_of(Story).to receive(:fetched_attributes).and_return({ title: 'Example' })

      expect(controller).to receive(:render).with(json: { title: 'Example' })

      controller.fetch_url_attributes
    end
  end

  describe '#new' do
    it 'initializes a new story and sets the title' do
      allow(controller).to receive(:params).and_return(url: 'http://example.com')

      controller.new
      expect(assigns(:title)).to eq("Submit Story")
      expect(assigns(:story)).to be_a_new(Story)
    end
  end

  describe '#preview' do
    it 'renders the new action with a preview layout' do
      allow(controller).to receive(:params).and_return({})
      allow(controller).to receive(:request).and_return(double(xhr?: false))

      expect(controller).to receive(:render).with(action: "new", layout: true)

      controller.preview
    end
  end

  describe '#show' do
    context 'when story is merged' do
      it 'redirects to the merged story path' do
        allow(story).to receive(:merged_into_story).and_return(story)

        expect(controller).to receive(:redirect_to).with(Routes.title_path(story, anchor: story.header_anchor))

        controller.show
      end
    end

    context 'when story is not visible to user' do
      it 'renders the missing action with 404 status' do
        allow(story).to receive(:can_be_seen_by_user?).and_return(false)

        expect(controller).to receive(:render).with(action: "_missing", status: 404, locals: { story: story, moderation: nil })

        controller.show
      end
    end
  end

  describe '#undelete' do
    context 'when user cannot undelete the story' do
      it 'redirects to root with an error message' do
        allow_any_instance_of(Story).to receive(:is_editable_by_user?).and_return(false)

        expect(controller).to receive(:redirect_to).with("/")
        controller.undelete
      end
    end

    context 'when user can undelete the story' do
      it 'marks the story as not deleted and redirects to the story path' do
        allow_any_instance_of(Story).to receive(:is_editable_by_user?).and_return(true)
        allow_any_instance_of(Story).to receive(:is_undeletable_by_user?).and_return(true)

        expect_any_instance_of(Story).to receive(:save).and_return(true)
        expect(controller).to receive(:redirect_to).with(Routes.title_path(story))

        controller.undelete
      end
    end
  end

  describe '#update' do
    context 'when user cannot edit the story' do
      it 'redirects to root with an error message' do
        allow_any_instance_of(Story).to receive(:is_editable_by_user?).and_return(false)

        expect(controller).to receive(:redirect_to).with("/")
        controller.update
      end
    end

    context 'when user can edit the story' do
      it 'updates the story and redirects to the story path' do
        allow_any_instance_of(Story).to receive(:is_editable_by_user?).and_return(true)

        expect_any_instance_of(Story).to receive(:save).and_return(true)
        expect(controller).to receive(:redirect_to).with(Routes.title_path(story))

        controller.update
      end
    end
  end

  describe '#unvote' do
    it 'removes the vote and returns ok' do
      expect(Vote).to receive(:vote_thusly_on_story_or_comment_for_user_because).with(0, story.id, nil, user.id, nil)
      expect(controller).to receive(:render).with(plain: "ok")

      controller.unvote
    end
  end

  describe '#upvote' do
    context 'when story is merged' do
      it 'returns an error message' do
        allow(story).to receive(:merged_into_story).and_return(story)

        expect(controller).to receive(:render).with(plain: "story has been merged", status: 400)

        controller.upvote
      end
    end

    context 'when story is not merged' do
      it 'adds an upvote and returns ok' do
        expect(Vote).to receive(:vote_thusly_on_story_or_comment_for_user_because).with(1, story.id, nil, user.id, nil)
        expect(controller).to receive(:render).with(plain: "ok")

        controller.upvote
      end
    end
  end

  describe '#flag' do
    context 'when reason is invalid' do
      it 'returns an error message' do
        allow(controller).to receive(:params).and_return(reason: 'invalid')

        expect(controller).to receive(:render).with(plain: "invalid reason", status: 400)

        controller.flag
      end
    end

    context 'when user cannot flag' do
      it 'returns an error message' do
        allow(controller).to receive(:params).and_return(reason: 'spam')
        allow(user).to receive(:can_flag?).and_return(false)

        expect(controller).to receive(:render).with(plain: "not permitted to flag", status: 400)

        controller.flag
      end
    end

    context 'when user can flag' do
      it 'adds a flag and returns ok' do
        allow(controller).to receive(:params).and_return(reason: 'spam')
        allow(user).to receive(:can_flag?).and_return(true)

        expect(Vote).to receive(:vote_thusly_on_story_or_comment_for_user_because).with(-1, story.id, nil, user.id, 'spam')
        expect(controller).to receive(:render).with(plain: "ok")

        controller.flag
      end
    end
  end

  describe '#hide' do
    context 'when story is merged' do
      it 'returns an error message' do
        allow(story).to receive(:merged_into_story).and_return(story)

        expect(controller).to receive(:render).with(plain: "story has been merged", status: 400)

        controller.hide
      end
    end

    context 'when story is not merged' do
      it 'hides the story and returns ok' do
        expect(HiddenStory).to receive(:hide_story_for_user).with(story, user)
        expect(controller).to receive(:render).with(plain: "ok")

        controller.hide
      end
    end
  end

  describe '#unhide' do
    it 'unhides the story and returns ok' do
      expect(HiddenStory).to receive(:unhide_story_for_user).with(story, user)
      expect(controller).to receive(:render).with(plain: "ok")

      controller.unhide
    end
  end

  describe '#save' do
    context 'when story is merged' do
      it 'returns an error message' do
        allow(story).to receive(:merged_into_story).and_return(story)

        expect(controller).to receive(:render).with(plain: "story has been merged", status: 400)

        controller.save
      end
    end

    context 'when story is not merged' do
      it 'saves the story and returns ok' do
        expect(SavedStory).to receive(:save_story_for_user).with(story.id, user.id)
        expect(controller).to receive(:render).with(plain: "ok")

        controller.save
      end
    end
  end

  describe '#unsave' do
    it 'unsaves the story and returns ok' do
      expect(SavedStory).to receive(:where).with(user_id: user.id, story_id: story.id).and_return(double(delete_all: true))
      expect(controller).to receive(:render).with(plain: "ok")

      controller.unsave
    end
  end

  describe '#check_url_dupe' do
    context 'when URL is missing' do
      it 'raises an error' do
        allow(controller).to receive(:params).and_return(story: { url: nil })

        expect { controller.check_url_dupe }.to raise_error(ActionController::ParameterMissing)
      end
    end

    context 'when URL is present' do
      it 'renders the form errors partial' do
        allow(controller).to receive(:params).and_return(story: { url: 'http://example.com' })
        allow_any_instance_of(Story).to receive(:check_already_posted_recently?).and_return(false)

        expect(controller).to receive(:render).with(partial: "stories/form_errors", layout: false, content_type: "text/html", locals: { linking_comments: [], story: instance_of(Story) })

        controller.check_url_dupe
      end
    end
  end

  describe '#disown' do
    context 'when story is not disownable' do
      it 'returns an error message' do
        allow(story).to receive(:disownable_by_user?).and_return(false)

        expect(controller).to receive(:render).with(plain: "can't find story", status: 400)

        controller.disown
      end
    end

    context 'when story is disownable' do
      it 'disowns the story and redirects to the story path' do
        allow(story).to receive(:disownable_by_user?).and_return(true)

        expect(InactiveUser).to receive(:disown!).with(story)
        expect(controller).to receive(:redirect_to).with(Routes.title_path(story))

        controller.disown
      end
    end
  end
end