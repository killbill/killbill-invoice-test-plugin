require 'bundler'
require 'rspec'

require 'invoice_test'

RSpec.configure do |config|
  config.color_enabled = true
  config.tty = true
  config.formatter = 'documentation'
end
