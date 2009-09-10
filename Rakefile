require 'rubygems'
require 'rake'
require 'tasks/opentox'

desc "Install required gems"
task :install do
	puts `sudo gem sources -a http://gems.github.com`
	puts `sudo gem install sinatra datamapper dm-more builder helma-opentox-ruby-api-wrapper`
end

desc "Update gems"
task :update do
	puts `sudo gem update sinatra datamapper dm-more builder helma-opentox-ruby-api-wrapper`
end

desc "Run tests"
task :test do
	load 'test/test.rb'
end

