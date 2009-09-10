['rubygems', 'sinatra', 'redis', 'builder', 'opentox-ruby-api-wrapper'].each do |lib|
	require lib
end

load File.join(File.dirname(__FILE__), 'model.rb')

case ENV['RACK_ENV']
when 'production'
  @@redis = Redis.new :db => 0
when 'development'
  @@redis = Redis.new :db => 1
when 'test'
  @@redis = Redis.new :db => 2
  @@redis.flush_db
end

set :default_content, :yaml

helpers do

	def find
		uri = uri(params[:splat].first)
		halt 404, "Dataset \"#{uri}\" not found." unless @model = Model.find(uri)
	end

	def uri(name)
		uri = url_for("/model/", :full) + URI.encode(name)
	end
end

get '/algorithms' do
	url_for("/algorithm/classification", :full)
end

post '/algorithm/classification/?' do # create a model
	#halt 403, 
	activity_dataset_uri = OpenTox::Dataset.find(:uri => params[:dataset_uri]).uri
	feature_dataset_uri = OpenTox::Algorithm::Fminer.create(activity_dataset_uri)
	Model.create(:activity_dataset_uri => activity_dataset_uri, :feature_dataset_uri => feature_dataset_uri).uri
end

get '/models/?' do # get index of models
	Model.find_all.join("\n")
end

get '/model/*/?' do
	#halt 404, "Model #{name} not found." unless @model = Model.find(request.url)
	find
	@model.to_yaml
end

delete '/model/*' do
	name = params[:splat].first
	halt 404, "Model #{name} not found." unless @model = Model.find(request.url)
	@model.destroy
	"Model #{params[:id]} succesfully deleted."
end

post '/model/*' do # create prediction
	name = params[:splat].first
	halt 404, "Model #{name} not found." unless @model = Model.find(request.url)
	compound = OpenTox::Compound.new :uri => params[:compound_uri]
	@model.predict(compound)
end

# PREDICTIONS
get '/model/*/predictions?' do # get dataset URI
	name = params[:splat].first
	halt 404, "Model #{name} not found." unless @model = Model.find(request.url)
	# Dataset.find
end

get '/model/*/prediction/*' do	# display prediction for a compound
	name = params[:splat].first
	compound_uri = params[:splat][1]
	halt 404, "Model #{name} not found." unless @model = Model.find(request.url)
	# prediction not found
	#prediction.to_yaml
	#xml prediction
end

get '/model/*/prediction/*/neighbors' do	
	name = params[:splat].first
	compound_uri = params[:splat][1]
	halt 404, "Model #{name} not found." unless @model = Model.find(request.url)
	# prediction not found
	# prediction.neighbors
end

get '/model/*/prediction/*/features' do	
	name = params[:splat].first
	compound_uri = params[:splat][1]
	halt 404, "Model #{name} not found." unless @model = Model.find(request.url)
	# prediction not found
	# prediction not found
	# prediction.features
end

delete '/model/*/prediction/*' do	# display prediction for a compound
	name = params[:splat].first
	halt 404, "Model #{name} not found." unless @model = Model.find(request.url)
	# Prediction.destroy
end
