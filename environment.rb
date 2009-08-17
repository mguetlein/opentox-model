require 'rubygems' 

['sinatra', 'sinatra/url_for', 'dm-core', 'dm-more', 'builder', 'opentox-ruby-api-wrapper'].each do |lib|
	require lib
end

require "openbabel"

sqlite = "#{File.expand_path(File.dirname(__FILE__))}/#{Sinatra::Base.environment}.sqlite3"
DataMapper.setup(:default, "sqlite3:///#{sqlite}")
#DataMapper.setup(:default, 'sqlite3::memory:')

DataMapper::Logger.new(STDOUT, 0)

load 'models.rb'

unless File.exists?(sqlite)
	Model.auto_migrate! 
	Prediction.auto_migrate!
	Neighbor.auto_migrate!
	Feature.auto_migrate!
end

