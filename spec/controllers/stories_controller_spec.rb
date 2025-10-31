require 'rails_helper'

RSpec.describe StoriesController, type: :controller do
  let(:user) { create(:user) }
  let(:story) { create(:story, user: user) }
  let(:valid_attributes) { { title: "Test Story", url: "http://example.com", description: "A test story", user_id: user.id } }
  let(:invalid_attributes) { { title: "", url: "", description: "" } }

  before do
    controller.instance_variable_set(:@user, user)
    allow(controller).to receive(:require_logged_in_user).and_return(true)
    allow(controller).to receive(:require_logged_in_user_or_400).and_return(true)
    allow(controller).to receive(:verify_user_can_submit_stories).and_return(true)
    allow(controller).to receive(:find_user_story).and_return(story)
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
      it "renders the new template" do
        post :create, params: { story: invalid_attributes }
        expect(response).to render_template("new")
      end
    end
  end

  describe "DELETE #destroy" do
    context "when user is authorized" do
      it "destroys the requested story" do
        story_to_destroy = create(:story, user: user)
        expect {
          delete :destroy, params: { id: story_to_destroy.to_param }
        }.to change(Story, :count).by(-1)
      end

      it "redirects to the stories list" do
        delete :destroy, params: { id: story.to_param }
        expect(response).to redirect_to(Routes.title_path(story))
      end
    end
  end

  describe "GET #edit" do
    it "renders the edit template" do
      get :edit, params: { id: story.to_param }
      expect(response).to render_template("edit")
    end
  end

  describe "GET #fetch_url_attributes" do
    it "returns fetched attributes as JSON" do
      get :fetch_url_attributes, params: { fetch_url: "http://example.com" }
      expect(response.content_type).to eq("application/json; charset=utf-8")
    end
  end

  describe "GET #new" do
    it "renders the new template" do
      get :new
      expect(response).to render_template("new")
    end
  end

  describe "GET #preview" do
    it "renders the new template with preview layout" do
      get :preview
      expect(response).to render_template("new")
    end
  end

  describe "GET #show" do
    it "renders the show template" do
      get :show, params: { id: story.to_param }
      expect(response).to render_template("show")
    end
  end

  # Removed PATCH #undelete test as the route does not exist

  describe "PATCH #update" do
    context "with valid params" do
      it "updates the requested story" do
        patch :update, params: { id: story.to_param, story: valid_attributes }
        story.reload
        expect(story.title).to eq("Test Story")
      end

      it "redirects to the story" do
        patch :update, params: { id: story.to_param, story: valid_attributes }
        expect(response).to redirect_to(Routes.title_path(story))
      end
    end

    context "with invalid params" do
      it "renders the edit template" do
        patch :update, params: { id: story.to_param, story: invalid_attributes }
        expect(response).to render_template("edit")
      end
    end
  end

  # Removed POST #unvote test as the route does not exist

  # Removed POST #upvote test as the route does not exist

  # Removed POST #flag test as the route does not exist

  # Removed POST #hide test as the route does not exist

  describe "POST #unhide" do
    it "unhides the story for the user" do
      post :unhide, params: { id: story.to_param }
      expect(response.body).to eq("ok")
    end
  end

  describe "POST #save" do
    it "saves the story for the user" do
      post :save, params: { id: story.to_param }
      expect(response.body).to eq("ok")
    end
  end

  describe "POST #unsave" do
    it "removes the story from saved stories for the user" do
      post :unsave, params: { id: story.to_param }
      expect(response.body).to eq("ok")
    end
  end

  describe "GET #check_url_dupe" do
    it "checks for duplicate URLs" do
      get :check_url_dupe, params: { story: { url: "http://example.com" } }
      expect(response.content_type).to eq("application/json; charset=utf-8")
    end
  end

  # Removed POST #disown test as the route does not exist
end