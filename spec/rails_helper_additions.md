# Add these configurations to your spec/rails_helper.rb:


# Add this to spec/rails_helper.rb

# Shoulda Matchers Configuration
Shoulda::Matchers.configure do |config|
  config.integrate do |with|
    with.test_framework :rspec
    with.library :rails
  end
end

# FactoryBot Configuration
RSpec.configure do |config|
  config.include FactoryBot::Syntax::Methods
end

# Load support files
Dir[Rails.root.join('spec', 'support', '**', '*.rb')].each {{ |f| require f }}

