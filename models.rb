class Model
	include DataMapper::Resource
	property :id, Serial
	property :name, String
	property :uri, String, :size => 255
	property :feature_dataset_uri, String, :size => 255
	property :training_dataset_uri, String, :size => 255
	property :finished, Boolean, :default => false

	def predictions
		Prediction.all(:model_uri => uri)
	end
end

class Prediction
	include DataMapper::Resource
	property :id, Serial
	property :uri, String, :size => 255
	property :model_uri, String, :size => 255
	property :compound_uri, String, :size => 255
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
	property :uri, String, :size => 255
	property :prediction_uri, String, :size => 255
	property :similarity, Float
end

class Feature
	include DataMapper::Resource
	property :id, Serial
	property :feature_uri, String, :size => 255
	property :prediction_uri, String, :size => 255
end
