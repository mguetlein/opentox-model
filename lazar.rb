require 'datamapper'

DataMapper::setup(:default, "sqlite3://#{Dir.pwd}/db/#{ENV['RACK_ENV']}.db")

class LazarModel
	include DataMapper::Resource
	property :id, Serial
	property :activity_dataset_uri, String, :length => 256 # default is too short for URIs
	property :feature_dataset_uri, String, :length => 256 # default is too short for URIs
	property :created_at, DateTime

	def uri
		File.join(OpenTox::Model::LazarClassification.base_uri,"lazar_classification", self.id.to_s)
	end

	def predict(compound)

		training_activities = OpenTox::Dataset.find :uri => @activity_dataset_uri
		# TODO: find database activities
		# TODO: find prediction
		training_features = OpenTox::Dataset.find :uri => @feature_dataset_uri

		prediction_dataset = OpenTox::Dataset.find_or_create(:name => training_activities.name + '_predictions')
		prediction_neighbors = OpenTox::Dataset.find_or_create(:name => training_activities.name + '_neighbors')
		prediction_features = OpenTox::Dataset.find_or_create(:name => training_activities.name + '_prediction_features')

		feature_uris = compound.match(training_features)
		prediction_features.add({compound.uri => feature_uris}.to_yaml)

		conf = 0.0
		neighbors = []

		training_features.compounds.each do |neighbor|
			sim = OpenTox::Algorithm::Similarity.weighted_tanimoto(training_features,neighbor,prediction_features,compound).to_f
			if sim > 0.3
				neighbors << neighbor.uri
				training_activities.features(neighbor).each do |a|
					case OpenTox::Feature.new(:uri => a.uri).value('classification').to_s
					when 'true'
						conf += OpenTox::Utils.gauss(sim) 
					when 'false'
						conf -= OpenTox::Utils.gauss(sim)
					end
				end
			end
		end
		conf = conf/neighbors.size
		if conf > 0.0
			classification = true
		elsif conf < 0.0
			classification = false
		end

		prediction = OpenTox::Feature.new(:name => training_activities.name + " prediction", :classification => classification, :confidence => conf)
		prediction_neighbors.add({compound.uri => neighbors}.to_yaml)
		prediction_dataset.add({compound.uri => [prediction.uri]}.to_yaml)

		prediction.uri

	end
end

# automatically create the post table
LazarModel.auto_migrate! #unless LazarModel.table_exists?
LazarModel.auto_migrate! if ENV['RACK_ENV'] == 'test'

get '/lazar_classification/?' do # get index of models
	LazarModel.all.collect{|m| m.uri}.join("\n")
end

get '/lazar_classification/:id/?' do
	halt 404, "Model #{params[:id]} not found." unless @model = LazarModel.get(params[:id])
	@model.to_yaml
end

delete '/lazar_classification/:id/?' do
	halt 404, "Model #{params[:id]} not found." unless @model = LazarModel.get(params[:id])
	@model.destroy
	"Model #{params[:id]} succesfully deleted."
end

post '/lazar_classification/?' do # create model
	halt 404, "Dataset #{params[:activity_dataset_uri]} not found" unless  OpenTox::Dataset.find(:uri => params[:activity_dataset_uri])
	halt 404, "Dataset #{params[:feature_dataset_uri]} not found" unless OpenTox::Dataset.find(:uri => params[:feature_dataset_uri])
	model = LazarModel.new(params)
	model.save
	model.uri
end

# PREDICTIONS
post '/lazar_classification/:id/?' do # create prediction
	halt 404, "Model #{params[:id]} not found." unless @model = LazarModel.get(params[:id])
	compound = OpenTox::Compound.new :uri => params[:compound_uri]
	@model.predict(compound)
end

get '/lazar_classification/*/predictions?' do # get dataset URI
	name = params[:splat].first
	halt 404, "Model #{name} not found." unless @model = LazarModel.get(request.url)
	# Dataset.find
end

get '/lazar_classification/*/prediction/*' do	# display prediction for a compound
	name = params[:splat].first
	compound_uri = params[:splat][1]
	halt 404, "Model #{name} not found." unless @model = LazarModel.get(request.url)
	# prediction not found
	#prediction.to_yaml
	#xml prediction
end

get '/lazar_classification/*/prediction/*/neighbors' do	
	name = params[:splat].first
	compound_uri = params[:splat][1]
	halt 404, "Model #{name} not found." unless @model = LazarModel.get(request.url)
	# prediction not found
	# prediction.neighbors
end

get '/lazar_classification/*/prediction/*/features' do	
	name = params[:splat].first
	compound_uri = params[:splat][1]
	halt 404, "Model #{name} not found." unless @model = LazarModel.get(request.url)
	# prediction not found
	# prediction not found
	# prediction.features
end

delete '/lazar_classification/*/prediction/*' do	# display prediction for a compound
	name = params[:splat].first
	halt 404, "Model #{name} not found." unless @model = LazarModel.get(request.url)
	# Prediction.destroy
end

