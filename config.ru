require 'rubygems'
require 'sinatra'
require 'application.rb'
require 'rack'
require 'rack/contrib'

FileUtils.mkdir_p 'log' unless File.exists?('log')
FileUtils.mkdir_p 'db' unless File.exists?('db')
log = File.new("log/#{ENV["RACK_ENV"]}.log", "a")
$stdout.reopen(log)
$stderr.reopen(log)

run Sinatra::Application
