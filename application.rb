require 'rubygems'
gem "opentox-ruby-api-wrapper", "= 1.6.0"
require 'opentox-ruby-api-wrapper'
LOGGER.progname = File.expand_path(__FILE__)

class Model
	include DataMapper::Resource
	property :id, Serial
	property :uri, String, :length => 255
	property :owl, Text, :length => 2**32-1 
	property :yaml, Text, :length => 2**32-1
	property :token_id, String, :length => 255 
	property :created_at, DateTime
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
	response['Content-Type'] = 'text/uri-list'
	Model.all(params).collect{|m| m.uri}.join("\n") + "\n"
end

delete '/:id/?' do
	begin
	  model = Model.get(params[:id])
	  uri = model.uri
		model.destroy!
		"Model #{params[:id]} deleted."
		if params["token_id"] and !Model.get(params[:id]) and uri
      begin
        aa = OpenTox::Authorization.delete_policy_from_uri(uri, params["token_id"])
      rescue
        LOGGER.warn "Policy delete error for Model URI: #{uri}"
      end
    end
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
