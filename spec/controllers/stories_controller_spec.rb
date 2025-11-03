require 'rails_helper'

RSpec.describe StoriesController do
  let(:user) { create(:user) }
  let(:story) { create(:story, user: user) }
  let(:valid_attributes) { { title: "Test Story", url: "http://example.com", description: "A test story" } }
  let(:invalid_attributes) { { title: "", url: "", description: "" } }

  before do
    allow(controller).to receive(:require_logged_in_user).and_return(true)
    allow(controller).to receive(:require_logged_in_user_or_400).and_return(true)
    allow(controller).to receive(:verify_user_can_submit_stories).and_return(true)
    allow(controller).to receive(:find_user_story).and_return(true)
    allow(controller).to receive(:track_story_reads).and_yield
    allow(controller).to receive(:show_title_h1).and_return(true)
    allow(controller).to receive(:find_story).and_return(story)
  end

  describe "POST #create" do
    context "with valid params" do
      it "creates a new Story" do
        expect {
          post :create, params: { story: valid_attributes }
        }.to change(Story, :count).by(1)
      end

      it "redirects to the created story" do
        post :create, params: { story: valid_attributes }
        expect(response).to redirect_to(Routes.title_path(Story.last))
      end
    end

    context "with invalid params" do
      it "renders the 'new' template" do
        post :create, params: { story: invalid_attributes }
        expect(response).to render_template("new")
      end
    end
  end

  describe "DELETE #destroy" do
    context "when the user can edit the story" do
      before do
        allow(story).to receive(:is_editable_by_user?).and_return(true)
      end

      it "deletes the story" do
        story # create the story
        expect {
          delete :destroy, params: { id: story.to_param }
        }.to change(Story, :count).by(-1)
      end

      it "redirects to the stories list" do
        delete :destroy, params: { id: story.to_param }
        expect(response).to redirect_to(Routes.title_path(story))
      end
    end

    context "when the user cannot edit the story" do
      before do
        allow(story).to receive(:is_editable_by_user?).and_return(false)
      end

      it "does not delete the story" do
        story # create the story
        expect {
          delete :destroy, params: { id: story.to_param }
        }.not_to change(Story, :count)
      end

      it "redirects to the root path" do
        delete :destroy, params: { id: story.to_param }
        expect(response).to redirect_to("/")
      end
    end
  end

  describe "PATCH #update" do
    context "with valid params" do
      it "updates the requested story" do
        patch :update, params: { id: story.to_param, story: { title: "Updated Title" } }
        story.reload
        expect(story.title).to eq("Updated Title")
      end

      it "redirects to the story" do
        patch :update, params: { id: story.to_param, story: valid_attributes }
        expect(response).to redirect_to(Routes.title_path(story))
      end
    end

    context "with invalid params" do
      it "renders the 'edit' template" do
        patch :update, params: { id: story.to_param, story: invalid_attributes }
        expect(response).to render_template("edit")
      end
    end
  end

  describe "POST #upvote" do
    context "when the story is found" do
      it "upvotes the story" do
        expect(Vote).to receive(:vote_thusly_on_story_or_comment_for_user_because).with(1, story.id, nil, user.id, nil)
        post :upvote, params: { id: story.to_param }
        expect(response.body).to eq("ok")
      end
    end

    context "when the story is not found" do
      before do
        allow(controller).to receive(:find_story).and_return(nil)
      end

      it "returns an error" do
        post :upvote, params: { id: "invalid" }
        expect(response.body).to eq("can't find story")
        expect(response.status).to eq(400)
      end
    end
  end

  describe "POST #flag" do
    context "with a valid reason" do
      before do
        allow(Vote::STORY_REASONS).to receive(:[]).and_return(true)
        allow(user).to receive(:can_flag?).and_return(true)
      end

      it "flags the story" do
        expect(Vote).to receive(:vote_thusly_on_story_or_comment_for_user_because).with(-1, story.id, nil, user.id, "reason")
        post :flag, params: { id: story.to_param, reason: "reason" }
        expect(response.body).to eq("ok")
      end
    end

    context "with an invalid reason" do
      before do
        allow(Vote::STORY_REASONS).to receive(:[]).and_return(false)
      end

      it "returns an error" do
        post :flag, params: { id: story.to_param, reason: "invalid" }
        expect(response.body).to eq("invalid reason")
        expect(response.status).to eq(400)
      end
    end
  end
end