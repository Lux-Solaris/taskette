# frozen_string_literal: true

require './app'

set :port, 4567

run Sinatra::Application
