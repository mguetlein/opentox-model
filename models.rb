class Model
	include DataMapper::Resource
	property :id, Serial
	property :name, String
	property :uri, URI
	property :feature_dataset_uri, URI
	property :training_dataset_uri, URI
	property :finished, Boolean, :default => false

	def predictions
		Prediction.all(:model_uri => uri)
	end
end

class Prediction
	include DataMapper::Resource
	property :id, Serial
	property :uri, URI
	property :model_uri, URI
	property :compound_uri, URI
	property :classification, Boolean 
	property :confidence, Float
	property :finished, Boolean, :default => false

	def neighbors
		Neighbor.all(:prediction_uri => uri)
	end

	def features
		Feature.all(:prediction_uri => uri)
	end
end

class Neighbor
	include DataMapper::Resource
	property :id, Serial
	property :compound_uri, URI
	property :prediction_uri, URI
	property :similarity, Float
end

class Feature
	include DataMapper::Resource
	property :id, Serial
	property :feature_uri, URI
	property :prediction_uri, URI
end
