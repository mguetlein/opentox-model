require 'rubygems'
require 'opentox-ruby'
require 'config/config_ru'
set :app_file, __FILE__ # to get the view path right
run Sinatra::Application
set :raise_errors, false
set :show_exceptions, false