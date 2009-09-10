require 'rubygems'
require 'sinatra'
require 'application.rb'

FileUtils.mkdir_p 'log' unless File.exists?('log')
log = File.new("log/#{ENV["RACK_ENV"]}.log", "a")
$stdout.reopen(log)
$stderr.reopen(log)

run Sinatra::Application
