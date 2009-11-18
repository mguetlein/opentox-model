require 'rubygems'
require 'sinatra'
require 'application.rb'
require 'rack'
require 'rack/contrib'

['db','public','log','tmp'].each do |dir|
	FileUtils.mkdir_p dir unless File.exists?(dir)
end

log = File.new("log/#{ENV["RACK_ENV"]}.log", "a")
$stdout.reopen(log)
$stderr.reopen(log)

run Sinatra::Application
