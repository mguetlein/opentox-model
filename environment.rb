['rubygems', 'sinatra', 'redis', 'builder', 'opentox-ruby-api-wrapper'].each do |lib|
	require lib
end

case ENV['RACK_ENV']
when 'production'
	  @@redis = Redis.new :db => 0
when 'development'
	  @@redis = Redis.new :db => 1
when 'test'
	  @@redis = Redis.new :db => 2
	  @@redis.flush_db
end

set :default_content, :yaml
load 'models.rb'
