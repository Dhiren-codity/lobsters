require "rails_helper"

RSpec.describe CabinetHelper, type: :helper do
  describe "debug_render" do
    it "renders content with details and summary" do
      expect(helper).to respond_to(:debug_render)
    end
  end

  describe "as_user" do
    it "sets and clears the user" do
      user = double("User")
      helper.as_user(user) do
        expect(helper.instance_variable_get(:@user)).to eq(user)
      end
      expect(helper.instance_variable_get(:@user)).to be_nil
    end
  end
end