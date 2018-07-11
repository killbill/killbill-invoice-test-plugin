require 'bundler'
require 'rspec'

require 'invoice_test'

RSpec.configure do |config|
  config.color = true
  config.tty = true
  config.formatter = 'documentation'
end
