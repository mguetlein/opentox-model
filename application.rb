require 'rubygems'
gem 'opentox-ruby-api-wrapper', '= 1.3.1'
require 'opentox-ruby-api-wrapper'
LOGGER.progname = File.expand_path(__FILE__)

class Model
	include DataMapper::Resource
	property :id, Serial
	property :uri, String, :length => 255
	#property :owl, Text, :length => 2**32-1 
	property :yaml, Text, :length => 2**32-1 
	property :created_at, DateTime
end

DataMapper.auto_upgrade!

require 'lazar.rb'

get '/?' do # get index of models
	response['Content-Type'] = 'text/uri-list'
	Model.all.collect{|m| m.uri}.join("\n") + "\n"
end

get '/:id/?' do
	model = Model.get(params[:id])
	halt 404, "Model #{uri} not found." unless model
	accept = request.env['HTTP_ACCEPT']
	accept = "application/rdf+xml" if accept == '*/*' or accept =~ /html/ or accept == '' or accept.nil?
	case accept
	when "application/rdf+xml"
		response['Content-Type'] = 'application/rdf+xml'
		model.owl
	when /yaml/
		response['Content-Type'] = 'application/x-yaml'
		model.yaml
	else
		halt 400, "Unsupported MIME type '#{accept}'"
	end
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
