
# spec/support/controller_helpers.rb

module ControllerHelpers
  def sign_in(user)
    session[:user_id] = user.id
  end

  def sign_out
    session.delete(:user_id)
  end

  def current_user
    @current_user ||= User.find_by(id: session[:user_id])
  end
end

RSpec.configure do |config|
  config.include ControllerHelpers, type: :controller
  config.include ControllerHelpers, type: :request
end
