require 'rubygems'
gem "opentox-ruby-api-wrapper", "= 1.6.2.1"
require 'opentox-ruby-api-wrapper'

class Model
	include DataMapper::Resource
	property :id, Serial
	property :uri, String, :length => 255
	property :owl, Text, :length => 2**32-1 
	property :yaml, Text, :length => 2**32-1 
	property :created_at, DateTime
end

class Prediction
  # cache predictions
	include DataMapper::Resource
	property :id, Serial
	property :compound_uri, String, :length => 255
	property :model_uri, String, :length => 255
	property :yaml, Text, :length => 2**32-1 
end

DataMapper.auto_upgrade!

require 'lazar.rb'


helpers do
	def activity(a)
		case a.to_s
		when "true"
			act = "active"
		when "false"
			act = "inactive"
		else
			act = "not available"
		end
		act
	end
end

get '/?' do # get index of models
  uri_list = Model.all(params).collect{|m| m.uri}.join("\n") + "\n"
  case request.env['HTTP_ACCEPT'].to_s
  when /text\/html/
    content_type "text/html"
    OpenTox.text_to_html uri_list
  else
    content_type 'text/uri-list'
    uri_list
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

delete '/prediction?' do
  Prediction.auto_migrate!
	response['Content-Type'] = 'text/plain'
	"All datasets deleted."
end
