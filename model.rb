class Model 

	include OpenTox::Utils
	attr_accessor :uri, :activity_dataset_uri, :feature_dataset_uri, :name

	def initialize(params)
		@uri = params[:uri]
		@activity_dataset_uri = params[:activity_dataset_uri]
		@feature_dataset_uri = params[:feature_dataset_uri]
		begin
			@name = URI.split(@uri)[5]
		rescue
			puts "Bad URI #{@uri}"
		end
	end

	def self.create(params)
		params[:uri] = params[:activity_dataset_uri].sub(/dataset/,'model')
		@@redis.set_add "models", params[:uri]
		@@redis.set(File.join(params[:uri],"activity_dataset"), params[:activity_dataset_uri])
		@@redis.set(File.join(params[:uri],"feature_dataset"), params[:feature_dataset_uri])
		Model.new(params)
	end

	def self.find(uri)
		if @@redis.set_member? "models", uri
			activity_dataset_uri = @@redis.get File.join(uri,"activity_dataset")
			feature_dataset_uri = @@redis.get File.join(uri,"feature_dataset")
			Model.new(:uri => uri, :activity_dataset_uri => activity_dataset_uri, :feature_dataset_uri => feature_dataset_uri)
		else
			nil
		end
	end

	def self.find_all
		@@redis.set_members("models")
	end

	def predict(compound)

		training_activities = OpenTox::Dataset.find :uri => @uri.sub(/model/,'dataset')
		# find database activities
		# find prediction
		training_features = OpenTox::Dataset.find(:uri => @feature_dataset_uri)

		prediction_dataset = OpenTox::Dataset.find_or_create(:name => training_activities.name + '_predictions')
		prediction_neighbors = OpenTox::Dataset.find_or_create(:name => training_activities.name + '_neighbors')
		prediction_features = OpenTox::Dataset.find_or_create(:name => training_activities.name + '_prediction_features')

		feature_uris = compound.match(training_features)
		prediction_features.add({compound.uri => feature_uris})

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

		prediction_neighbors.add({compound.uri => neighbors})
		prediction_uri = OpenTox::Feature.new(:name => @name, :values => {:classification => classification, :confidence => conf}).uri
		prediction_uri

	end

end
