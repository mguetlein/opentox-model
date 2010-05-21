require 'rubygems'
gem "opentox-ruby-api-wrapper", "= 1.5.4"
require 'opentox-ruby-api-wrapper'
LOGGER.progname = File.expand_path(__FILE__)

class Model
	include DataMapper::Resource
	property :id, Serial
	property :uri, String, :length => 255
	property :owl, Text, :length => 2**32-1 
	property :yaml, Text, :length => 2**32-1 
	property :created_at, DateTime
end

DataMapper.auto_upgrade!

require 'lazar.rb'

get '/?' do # get index of models
	response['Content-Type'] = 'text/uri-list'
	Model.all.collect{|m| m.uri}.join("\n") + "\n"
end

delete '/:id/?' do
	begin
		Model.get(params[:id]).destroy!
		"Model #{params[:id]} deleted."
	rescue
		halt 404, "Model #{params[:id]} does not exist."
	end
end


delete '/?' do
	# TODO delete datasets
  Model.auto_migrate!
	response['Content-Type'] = 'text/plain'
	"All Models deleted."
end
