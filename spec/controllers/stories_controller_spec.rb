require 'rails_helper'
require 'spec_helper'
# Add gem 'rails-controller-testing' to your Gemfile

RSpec.describe StoriesController, type: :controller do
  before do
    # Assuming FactoryBot is configured correctly
    @user = FactoryBot.create(:user)
    sign_in @user
  end

  describe "GET #new" do
    it "returns http success" do
      get :new
      expect(response).to have_http_status(:success)
    end
  end

  describe "POST #create" do
    context "with valid attributes" do
      it "creates a new story" do
        expect {
          post :create, params: { story: FactoryBot.attributes_for(:story) }
        }.to change(Story, :count).by(1)
      end

      it "redirects to the new story" do
        post :create, params: { story: FactoryBot.attributes_for(:story) }
        expect(response).to redirect_to Routes.title_path(Story.last)
      end
    end

    context "with invalid attributes" do
      it "does not save the new story" do
        expect {
          post :create, params: { story: FactoryBot.attributes_for(:invalid_story) }
        }.to_not change(Story, :count)
      end

      it "re-renders the new method" do
        post :create, params: { story: FactoryBot.attributes_for(:invalid_story) }
        expect(response).to render_template :new
      end
    end
  end

  describe "GET #edit" do
    it "returns http success" do
      story = FactoryBot.create(:story, user: @user)
      get :edit, params: { id: story.id }
      expect(response).to have_http_status(:success)
    end
  end

  describe "PATCH #update" do
    before :each do
      @story = FactoryBot.create(:story, title: "Old Title", user: @user)
    end

    context "valid attributes" do
      it "located the requested @story" do
        patch :update, params: { id: @story.id, story: FactoryBot.attributes_for(:story) }
        expect(assigns(:story)).to eq(@story)
      end

      it "changes @story's attributes" do
        patch :update, params: { id: @story.id, story: { title: "New Title" } }
        @story.reload
        expect(@story.title).to eq("New Title")
      end

      it "redirects to the updated story" do
        patch :update, params: { id: @story.id, story: FactoryBot.attributes_for(:story) }
        expect(response).to redirect_to Routes.title_path(@story)
      end
    end

    context "invalid attributes" do
      it "does not change @story's attributes" do
        patch :update, params: { id: @story.id, story: { title: nil } }
        @story.reload
        expect(@story.title).to eq("Old Title")
      end

      it "re-renders the edit method" do
        patch :update, params: { id: @story.id, story: { title: nil } }
        expect(response).to render_template :edit
      end
    end
  end

  describe "DELETE #destroy" do
    before :each do
      @story = FactoryBot.create(:story, user: @user)
    end

    it "deletes the story" do
      expect {
        delete :destroy, params: { id: @story.id }
      }.to change(Story, :count).by(-1)
    end

    it "redirects to stories#index" do
      delete :destroy, params: { id: @story.id }
      expect(response).to redirect_to "/"
    end
  end
end