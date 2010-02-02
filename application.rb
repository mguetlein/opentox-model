require 'rubygems'
gem 'opentox-ruby-api-wrapper', '= 1.2.7'
require 'opentox-ruby-api-wrapper'

class Model
	include DataMapper::Resource
	property :id, Serial
	property :uri, String, :length => 100
	property :owl, Text
	property :yaml, Text
	property :created_at, DateTime
end

DataMapper.auto_upgrade!

require 'lazar.rb'

get '/?' do # get index of models
	Model.all.collect{|m| m.uri}.join("\n")
end

get '/:id/?' do
	model = Model.get(params[:id])
	halt 404, "Model #{uri} not found." unless model
	accept = request.env['HTTP_ACCEPT']
	accept = "application/rdf+xml" if accept == '*/*' or accept == '' or accept.nil?
	case accept
	when "application/rdf+xml"
		model.owl
	when /yaml/
		model.yaml
	else
		halt 400, "Unsupported MIME type '#{request.content_type}'"
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
	Model.all.each { |d| d.destroy! }
	"All Models deleted."
end
