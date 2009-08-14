require 'rubygems'
require 'rake'

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
	puts "No tests for lazar."
	#load 'test.rb'
end

